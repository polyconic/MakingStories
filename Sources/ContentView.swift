import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        Group {
            if model.url == nil {
                DropZone()
            } else {
                EditorView()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.load(url)
            return true
        } isTargeted: { model.dropTargeted = $0 }
    }
}

struct DropZone: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "crop")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(model.dropTargeted ? Color.accentColor : .secondary)
            Text("Drop a video here").font(.title2)
            Text(model.status.isEmpty ? "It gets cut into 30-second story clips" : model.status)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Choose a Video…") { model.choose() }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.dropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}

struct EditorView: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            PreviewView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 10) {
                TransportBar()
                FramingBar()
                TimelineView()
                FooterBar()
            }
            .padding(16)
            .background(.bar)
        }
    }
}

struct TransportBar: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 14)
            }
            .keyboardShortcut(.space, modifiers: [])
            .help("Play or pause (Space)")

            Button { model.toggleMute() } label: {
                Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 16)
            }
            .keyboardShortcut("s", modifiers: [])
            .help(model.isMuted ? "Unmute preview (S)" : "Mute preview (S)")

            Text("\(time(model.currentTime)) / \(time(model.duration))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Divider().frame(height: 16)

            Button("Add Cut") { model.addMarker(at: model.currentTime) }
                .keyboardShortcut("m", modifiers: [])
                .help("Cut at the playhead (M)")
            Button("Every 30s") { model.splitEvery(30) }
                .help("Re-cut the whole video into 30-second clips")
            Button("One Clip") { model.clearMarkers() }
                .help("Remove every cut")

            Spacer()

            Text(framingState)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var framingState: String {
        let clip = model.currentSegment
        if clip.isTracked { return "following subject" }
        if clip.panIsManual { return "\(clip.pan.count) keyframe\(clip.pan.count == 1 ? "" : "s")" }
        return "fixed frame"
    }

    private func time(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

struct FramingBar: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            ZoomControl()

            Spacer()

            if model.isTracking {
                ProgressView(value: model.trackProgress).frame(width: 90)
                Text("following…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Track") { model.trackCurrent() }
                    .help("Find the subject and follow it through this clip")
                Button("Keyframe") { model.addKeyframe() }
                    .keyboardShortcut("k", modifiers: [])
                    .help("Pin this framing at the playhead (K), then move the playhead and drag the frame")
                if model.currentSegment.hasPan {
                    Button("Clear Pan") { model.clearPan() }
                        .help("Drop the tracking or keyframes and hold one fixed frame")
                }
                Button("Reset") { model.resetFraming() }
                    .help("Center this clip, zoom back to 100%, and drop any pan")
                Button("Apply to All") { model.applyFramingToAll() }
                    .help("Give every clip this clip's framing and zoom")
            }
        }
    }
}

struct ZoomControl: View {
    @EnvironmentObject var model: EditorModel

    /// The slider is logarithmic so 100% sits at the middle of the track.
    private var slider: Binding<Double> {
        Binding(
            get: {
                let low = CropMath.zoomRange.lowerBound, high = CropMath.zoomRange.upperBound
                return log(Double(model.currentSegment.zoom / low)) / log(Double(high / low))
            },
            set: { t in
                let low = CropMath.zoomRange.lowerBound, high = CropMath.zoomRange.upperBound
                model.setZoom(low * pow(high / low, CGFloat(t)))
            }
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            Button { model.nudgeZoom(1 / 1.15) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .keyboardShortcut("-", modifiers: .command)
            .help("Zoom out (⌘−)")

            Slider(value: slider, in: 0...1) { editing in
                // One undo step for the whole drag, taken before the first value lands.
                if editing { model.beginZoomEdit() }
            }
            .frame(width: 110)

            Button { model.nudgeZoom(1.15) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .keyboardShortcut("=", modifiers: .command)
            .help("Zoom in (⌘+), or pinch on the video")

            Button("\(Int((model.currentSegment.zoom * 100).rounded()))%") { model.resetZoom() }
                .font(.caption.monospacedDigit())
                .frame(width: 52)
                .disabled(model.currentSegment.zoom == 1)
                .help("Back to 100%")
        }
    }
}

struct FooterBar: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            TextField("Name", text: $model.exportName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
                .help("Clips are named after this")

            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.exportBase)_01.mp4 → Desktop")
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if model.isExporting {
                ProgressView(value: model.exportProgress).frame(width: 140)
            } else {
                Button("All") { model.includeAll() }
                    .help("Put every clip back in the export")
                Button("Only This") { model.includeOnlyCurrent() }
                    .help("Export just the clip under the playhead")
                Button("Open Another…") { model.choose() }
                Button("Export \(model.includedCount) Clip\(model.includedCount == 1 ? "" : "s")") {
                    model.exportAll()
                }
                .keyboardShortcut("e", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(model.includedCount == 0)
            }
        }
    }

    private var detail: String {
        if !model.status.isEmpty { return model.status }
        let out = CropMath.storySize
        let clip = model.currentSegment
        let skipped = model.segments.count - model.includedCount
        return String(format: "Clip %d of %d · %.1fs · out %d×%d%@",
                      model.currentIndex + 1, model.segments.count, clip.duration,
                      Int(out.width), Int(out.height),
                      skipped > 0 ? " · \(skipped) skipped" : "")
    }
}
