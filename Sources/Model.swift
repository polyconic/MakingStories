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

    /// The pan over time. Either found by the tracker or set by hand — same shape either way,
    /// so playback and export don't care which made it.
    var pan: [TrackPoint] = []
    var panIsManual = false

    var duration: Double { end - start }
    var hasPan: Bool { !pan.isEmpty }
    var isTracked: Bool { hasPan && !panIsManual }

    /// Where the frame sits at a given moment — the fixed offset, or the pan.
    func offset(at time: Double, source: CGSize) -> CGPoint {
        guard hasPan else { return offset }
        return CropMath.offset(centering: subject(at: time), source: source, zoom: zoom)
    }

    private func subject(at time: Double) -> CGPoint {
        if time <= pan[0].time { return pan[0].subject }
        guard let i = pan.firstIndex(where: { $0.time > time }) else { return pan[pan.count - 1].subject }
        let (a, b) = (pan[i - 1], pan[i])
        let t = (time - a.time) / max(b.time - a.time, 0.0001)
        return CGPoint(x: a.subject.x + (b.subject.x - a.subject.x) * t,
                       y: a.subject.y + (b.subject.y - a.subject.y) * t)
    }
}

/// A scroll event reduced to values that can cross an isolation boundary.
struct ScrollInput {
    var deltaY: CGFloat
    var location: NSPoint
    var windowNumber: Int
    var precise: Bool
    var inverted: Bool
    var began: Bool
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
    private var draggingMarker: Int?
    private var lastScroll = Date.distantPast

    /// The preview's AppKit view, so scroll events can be gated to the video area.
    weak var previewView: NSView?

    // MARK: - Undo

    /// The window's manager, so ⌘Z comes off the standard Edit menu and a focused text field
    /// still gets its own undo through the responder chain.
    private var undoManager: UndoManager? {
        NSApp.keyWindow?.undoManager ?? NSApp.mainWindow?.undoManager
    }

    /// Records the state before a change. Registering from inside an undo is what makes redo work.
    private func snapshot(_ label: String) {
        guard let manager = undoManager else { return }
        let before = segments
        manager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.snapshot(label)
                model.segments = before
                // The old status describes a change that no longer stands.
                model.status = ""
            }
        }
        manager.setActionName(label)
    }

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
                // A new video is a fresh start; there's nothing sensible to undo back into.
                undoManager?.removeAllActions()
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
        snapshot("Split Every \(Int(interval))s")
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
        snapshot("Add Cut")
        let tail = Segment(start: time, end: segments[i].end, offset: segments[i].offset,
                           zoom: segments[i].zoom, included: segments[i].included)
        segments[i].end = time
        segments.insert(tail, at: i + 1)
    }

    /// Removes the boundary between segment `i` and `i + 1`, merging them.
    func removeMarker(after i: Int) {
        guard segments.indices.contains(i), segments.indices.contains(i + 1) else { return }
        snapshot("Remove Cut")
        segments[i].end = segments[i + 1].end
        segments.remove(at: i + 1)
    }

    func moveMarker(after i: Int, to time: Double) {
        guard segments.indices.contains(i), segments.indices.contains(i + 1) else { return }
        // One undo step per drag, not per mouse-move.
        if draggingMarker != i {
            snapshot("Move Cut")
            draggingMarker = i
        }
        let t = min(max(time, segments[i].start + minClip), segments[i + 1].end - minClip)
        segments[i].end = t
        segments[i + 1].start = t
    }

    func endMarkerDrag() { draggingMarker = nil }

    func clearMarkers() {
        guard duration > 0 else { return }
        snapshot("Merge Into One Clip")
        let offset = segments.first?.offset ?? CGPoint(x: 0.5, y: 0.5)
        segments = [Segment(start: 0, end: duration, offset: offset)]
    }

    // MARK: - Choosing clips

    var includedCount: Int { segments.filter(\.included).count }

    func toggleIncluded(_ i: Int) {
        guard segments.indices.contains(i) else { return }
        snapshot(segments[i].included ? "Skip Clip" : "Include Clip")
        segments[i].included.toggle()
    }

    func includeAll() {
        snapshot("Include All Clips")
        for i in segments.indices { segments[i].included = true }
    }

    func includeOnlyCurrent() {
        snapshot("Export Only This Clip")
        let current = currentIndex
        for i in segments.indices { segments[i].included = (i == current) }
    }

    // MARK: - Framing

    /// Drag translation is in view points; slack is the room the crop has to move there.
    func dragCrop(by translation: CGSize, slack: CGSize) {
        guard segments.indices.contains(currentIndex) else { return }
        let i = currentIndex

        if cropDragStart == nil {
            snapshot("Reframe")
            // Pick up from whatever is on screen, then decide what the drag means.
            segments[i].offset = segments[i].offset(at: currentTime, source: displaySize)
            // An automatic pan is replaced by the hand on the frame; hand-set keys are kept
            // and edited, the way an editor's auto-keyframe does it.
            if segments[i].isTracked { segments[i].pan = [] }
            cropDragStart = segments[i].offset
        }
        guard let start = cropDragStart else { return }

        var offset = start
        if slack.width > 0.5 { offset.x = start.x + translation.width / slack.width }
        if slack.height > 0.5 { offset.y = start.y + translation.height / slack.height }
        offset = CGPoint(x: CropMath.clamp(offset.x), y: CropMath.clamp(offset.y))
        segments[i].offset = offset
        if segments[i].panIsManual { setKey(on: i, at: currentTime, offset: offset) }
    }

    func endCropDrag() { cropDragStart = nil }

    // MARK: - Keyframes

    /// Pins the current framing at the playhead. The first one turns a fixed frame into a pan.
    func addKeyframe() {
        guard segments.indices.contains(currentIndex) else { return }
        let i = currentIndex
        snapshot("Add Keyframe")
        let offset = segments[i].offset(at: currentTime, source: displaySize)
        if !segments[i].panIsManual {
            segments[i].pan = []
            segments[i].panIsManual = true
        }
        segments[i].offset = offset
        setKey(on: i, at: currentTime, offset: offset)
        status = "Keyframe at \(String(format: "%.1fs", currentTime))"
    }

    func removeKeyframe(clip: Int, at time: Double) {
        guard segments.indices.contains(clip) else { return }
        snapshot("Remove Keyframe")
        segments[clip].pan.removeAll { abs($0.time - time) < 0.001 }
        if segments[clip].pan.isEmpty { segments[clip].panIsManual = false }
    }

    func clearPan() {
        guard segments.indices.contains(currentIndex) else { return }
        snapshot("Clear Pan")
        segments[currentIndex].offset = segments[currentIndex].offset(at: currentTime,
                                                                      source: displaySize)
        segments[currentIndex].pan = []
        segments[currentIndex].panIsManual = false
        status = ""
    }

    private func setKey(on clip: Int, at time: Double, offset: CGPoint) {
        let subject = CropMath.subject(centeredBy: offset, source: displaySize,
                                       zoom: segments[clip].zoom)
        let point = TrackPoint(time: time, subject: subject)
        // Within a frame or so of an existing key counts as the same key.
        if let existing = segments[clip].pan.firstIndex(where: { abs($0.time - time) < 0.05 }) {
            segments[clip].pan[existing] = point
        } else {
            let at = segments[clip].pan.firstIndex { $0.time > time } ?? segments[clip].pan.count
            segments[clip].pan.insert(point, at: at)
        }
    }

    func setZoom(_ zoom: CGFloat) {
        guard segments.indices.contains(currentIndex) else { return }
        segments[currentIndex].zoom = min(max(zoom, CropMath.zoomRange.lowerBound),
                                          CropMath.zoomRange.upperBound)
    }

    func beginZoomEdit() { snapshot("Zoom") }

    func nudgeZoom(_ factor: CGFloat) {
        snapshot("Zoom")
        setZoom(currentSegment.zoom * factor)
    }

    func resetZoom() {
        guard segments.indices.contains(currentIndex) else { return }
        snapshot("Zoom to 100%")
        segments[currentIndex].zoom = 1
    }

    /// Scroll over the video to zoom. SwiftUI has no scroll-wheel hook, so this is fed from an
    /// AppKit event monitor. Returns false when the scroll wasn't over the preview and should
    /// pass through untouched.
    func scrollZoom(_ scroll: ScrollInput) -> Bool {
        guard let view = previewView, let window = view.window,
              window.windowNumber == scroll.windowNumber,
              view.bounds.contains(view.convert(scroll.location, from: nil))
        else { return false }

        // Natural scrolling already flips the sign; undo that so the physical motion decides.
        let delta = scroll.inverted ? -scroll.deltaY : scroll.deltaY
        guard delta != 0 else { return true }

        let now = Date()
        // One undo step per burst — a scroll fires continuously.
        if scroll.began || now.timeIntervalSince(lastScroll) > 0.6 { snapshot("Zoom") }
        lastScroll = now

        // A trackpad sends many small precise deltas; a wheel sends a few large notches.
        let rate: CGFloat = scroll.precise ? 0.004 : 0.08
        setZoom(currentSegment.zoom * exp(delta * rate))
        return true
    }

    func resetFraming() {
        guard segments.indices.contains(currentIndex) else { return }
        snapshot("Reset Framing")
        segments[currentIndex].offset = CGPoint(x: 0.5, y: 0.5)
        segments[currentIndex].zoom = 1
        segments[currentIndex].pan = []
        segments[currentIndex].panIsManual = false
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
                    snapshot("Track Subject")
                    segments[index].pan = points
                    segments[index].panIsManual = false
                }
                status = "Clip \(index + 1) now follows the subject"
            } catch {
                status = error.localizedDescription
            }
            isTracking = false
        }
    }

    func applyFramingToAll() {
        snapshot("Apply Framing To All")
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
                                              zoom: clip.zoom, pan: clip.pan, to: output)
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
