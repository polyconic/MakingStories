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

            VStack(spacing: 12) {
                TransportBar()
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
        HStack(spacing: 14) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 14)
            }
            .keyboardShortcut(.space, modifiers: [])
            .help("Play or pause (Space)")

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

            Button("Center") { model.centerCurrent() }
                .help("Center the framing on this clip")
            Button("Apply Framing to All") { model.applyFramingToAll() }
                .help("Give every clip this clip's framing")
        }
    }

    private func time(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

struct FooterBar: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.url?.lastPathComponent ?? "")
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
                Button("Open Another…") { model.choose() }
                Button("Export \(model.segments.count) Clip\(model.segments.count == 1 ? "" : "s")") {
                    model.exportAll()
                }
                .keyboardShortcut("e", modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var detail: String {
        if !model.status.isEmpty { return model.status }
        let out = CropMath.storySize
        let clip = model.currentSegment
        return String(format: "Clip %d · %.1fs · out %d×%d",
                      model.currentIndex + 1, clip.duration, Int(out.width), Int(out.height))
    }
}
