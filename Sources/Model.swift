import AVFoundation
import AppKit
import SwiftUI

struct Segment: Identifiable, Equatable {
    var id = UUID()
    var start: Double
    var end: Double
    var offset = CGPoint(x: 0.5, y: 0.5)
    var zoom: CGFloat = 1
    var included = true
    var track: [TrackPoint] = []

    var duration: Double { end - start }
    var isTracked: Bool { track.count >= 2 }

    /// Where the frame sits at a given moment — the fixed offset, or the tracked pan.
    func offset(at time: Double, source: CGSize) -> CGPoint {
        guard isTracked else { return offset }
        return CropMath.offset(centering: subject(at: time), source: source, zoom: zoom)
    }

    private func subject(at time: Double) -> CGPoint {
        if time <= track[0].time { return track[0].subject }
        guard let i = track.firstIndex(where: { $0.time > time }) else { return track[track.count - 1].subject }
        let (a, b) = (track[i - 1], track[i])
        let t = (time - a.time) / max(b.time - a.time, 0.0001)
        return CGPoint(x: a.subject.x + (b.subject.x - a.subject.x) * t,
                       y: a.subject.y + (b.subject.y - a.subject.y) * t)
    }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var url: URL?
    @Published var player: AVPlayer?
    @Published var displaySize: CGSize = .zero
    @Published var duration: Double = 0
    @Published var segments: [Segment] = []
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var exportName = ""
    @Published var dropTargeted = false
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var isTracking = false
    @Published var trackProgress: Double = 0
    @Published var status = ""

    /// Segment boundaries can't be dragged closer together than this.
    private let minClip: Double = 0.5
    private var timeObserver: Any?
    private var cropDragStart: CGPoint?
    private var pinchStartZoom: CGFloat?

    var currentIndex: Int {
        segments.firstIndex { $0.start <= currentTime && currentTime < $0.end }
            ?? max(segments.count - 1, 0)
    }

    var currentSegment: Segment {
        segments.indices.contains(currentIndex) ? segments[currentIndex] : Segment(start: 0, end: 0)
    }

    // MARK: - Loading

    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    func load(_ url: URL) {
        status = "Loading…"
        Task {
            do {
                let info = try await Exporter.probe(url)
                teardownObserver()
                let player = AVPlayer(url: url)
                player.isMuted = self.isMuted
                self.url = url
                self.player = player
                self.displaySize = info.displaySize
                self.duration = info.duration
                self.currentTime = 0
                self.isPlaying = false
                self.exportName = url.deletingPathExtension().lastPathComponent
                self.status = ""
                splitEvery(30)
                observe(player)
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func observe(_ player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds
                if self.isPlaying, time.seconds >= self.duration - 0.05 {
                    player.pause()
                    self.isPlaying = false
                }
            }
        }
    }

    private func teardownObserver() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    // MARK: - Playback

    func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            if currentTime >= duration - 0.05 { seek(to: 0) }
            player.play()
        }
        isPlaying.toggle()
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    func seek(to time: Double) {
        let t = min(max(time, 0), duration)
        currentTime = t
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Markers

    func splitEvery(_ interval: Double) {
        guard duration > 0 else { return }
        var bounds = Array(stride(from: 0, to: duration, by: interval))
        bounds.append(duration)
        // A stub of a final clip is tidier merged into the one before it.
        if bounds.count > 2, bounds[bounds.count - 1] - bounds[bounds.count - 2] < interval * 0.25 {
            bounds.remove(at: bounds.count - 2)
        }
        segments = zip(bounds, bounds.dropFirst()).map { Segment(start: $0, end: $1) }
    }

    func addMarker(at time: Double) {
        guard let i = segments.firstIndex(where: { $0.start < time && time < $0.end }) else { return }
        guard time - segments[i].start >= minClip, segments[i].end - time >= minClip else { return }
        let tail = Segment(start: time, end: segments[i].end, offset: segments[i].offset,
                           zoom: segments[i].zoom, included: segments[i].included)
        segments[i].end = time
        segments.insert(tail, at: i + 1)
    }

    /// Removes the boundary between segment `i` and `i + 1`, merging them.
    func removeMarker(after i: Int) {
        guard segments.indices.contains(i), segments.indices.contains(i + 1) else { return }
        segments[i].end = segments[i + 1].end
        segments.remove(at: i + 1)
    }

    func moveMarker(after i: Int, to time: Double) {
        guard segments.indices.contains(i), segments.indices.contains(i + 1) else { return }
        let t = min(max(time, segments[i].start + minClip), segments[i + 1].end - minClip)
        segments[i].end = t
        segments[i + 1].start = t
    }

    func clearMarkers() {
        guard duration > 0 else { return }
        let offset = segments.first?.offset ?? CGPoint(x: 0.5, y: 0.5)
        segments = [Segment(start: 0, end: duration, offset: offset)]
    }

    // MARK: - Choosing clips

    var includedCount: Int { segments.filter(\.included).count }

    func toggleIncluded(_ i: Int) {
        guard segments.indices.contains(i) else { return }
        segments[i].included.toggle()
    }

    func includeAll() {
        for i in segments.indices { segments[i].included = true }
    }

    func includeOnlyCurrent() {
        let current = currentIndex
        for i in segments.indices { segments[i].included = (i == current) }
    }

    // MARK: - Framing

    /// Drag translation is in view points; slack is the room the crop has to move there.
    func dragCrop(by translation: CGSize, slack: CGSize) {
        guard segments.indices.contains(currentIndex) else { return }
        // Grabbing the frame takes it back off the tracker, starting from wherever the pan is now.
        if segments[currentIndex].isTracked {
            segments[currentIndex].offset = segments[currentIndex].offset(at: currentTime,
                                                                          source: displaySize)
            segments[currentIndex].track = []
        }
        let start = cropDragStart ?? segments[currentIndex].offset
        cropDragStart = start
        var offset = start
        if slack.width > 0.5 { offset.x = start.x + translation.width / slack.width }
        if slack.height > 0.5 { offset.y = start.y + translation.height / slack.height }
        segments[currentIndex].offset = CGPoint(x: min(max(offset.x, 0), 1),
                                                y: min(max(offset.y, 0), 1))
    }

    func endCropDrag() { cropDragStart = nil }

    func setZoom(_ zoom: CGFloat) {
        guard segments.indices.contains(currentIndex) else { return }
        segments[currentIndex].zoom = min(max(zoom, CropMath.zoomRange.lowerBound),
                                          CropMath.zoomRange.upperBound)
    }

    func nudgeZoom(_ factor: CGFloat) {
        setZoom(currentSegment.zoom * factor)
    }

    /// Trackpad pinch: magnification is cumulative from the gesture's start, not per-event.
    func pinchZoom(_ magnification: CGFloat) {
        let start = pinchStartZoom ?? currentSegment.zoom
        pinchStartZoom = start
        setZoom(start * magnification)
    }

    func endPinch() { pinchStartZoom = nil }

    func resetFraming() {
        guard segments.indices.contains(currentIndex) else { return }
        segments[currentIndex].offset = CGPoint(x: 0.5, y: 0.5)
        segments[currentIndex].zoom = 1
        segments[currentIndex].track = []
    }

    // MARK: - Tracking

    func trackCurrent() {
        guard let url, !isTracking, segments.indices.contains(currentIndex) else { return }
        let index = currentIndex
        let clip = segments[index]
        isTracking = true
        trackProgress = 0
        status = "Following the subject…"
        Task {
            do {
                let range = CMTimeRange(start: CMTime(seconds: clip.start, preferredTimescale: 600),
                                        end: CMTime(seconds: clip.end, preferredTimescale: 600))
                let points = try await Tracker.track(source: url, range: range) { p in
                    Task { @MainActor in self.trackProgress = p }
                }
                // The clip may have been re-cut while this ran.
                if segments.indices.contains(index), segments[index].id == clip.id {
                    segments[index].track = points
                }
                status = "Clip \(index + 1) now follows the subject"
            } catch {
                status = error.localizedDescription
            }
            isTracking = false
        }
    }

    func clearTrack() {
        guard segments.indices.contains(currentIndex) else { return }
        segments[currentIndex].track = []
        status = ""
    }

    func applyFramingToAll() {
        let (offset, zoom) = (currentSegment.offset, currentSegment.zoom)
        for i in segments.indices {
            segments[i].offset = offset
            segments[i].zoom = zoom
        }
    }

    // MARK: - Export

    var exportBase: String {
        let cleaned = exportName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Story" : cleaned
    }

    private var desktop: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    func exportAll() {
        guard let url else { return }
        // Output numbering runs over the chosen clips only, so the files come out 01, 02, 03 with no gaps.
        let clips = segments.filter(\.included)
        guard !clips.isEmpty else { return }
        isExporting = true
        exportProgress = 0
        let base = exportBase
        Task {
            let folder = desktop.appendingPathComponent("\(base) Story")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            var failed = 0
            for (i, clip) in clips.enumerated() {
                status = "Exporting clip \(i + 1) of \(clips.count)…"
                let output = folder.appendingPathComponent(String(format: "%@_%02d.mp4", base, i + 1))
                let range = CMTimeRange(start: CMTime(seconds: clip.start, preferredTimescale: 600),
                                        end: CMTime(seconds: clip.end, preferredTimescale: 600))
                do {
                    try await Exporter.export(source: url, range: range, offset: clip.offset,
                                              zoom: clip.zoom, track: clip.track, to: output)
                } catch {
                    failed += 1
                    status = "Clip \(i + 1): \(error.localizedDescription)"
                }
                exportProgress = Double(i + 1) / Double(clips.count)
            }

            isExporting = false
            status = failed == 0
                ? "Exported \(clips.count) clip\(clips.count == 1 ? "" : "s") to Desktop / \(folder.lastPathComponent)"
                : "\(clips.count - failed) of \(clips.count) exported, \(failed) failed"
        }
    }
}
