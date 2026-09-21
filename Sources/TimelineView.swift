import SwiftUI

struct TimelineView: View {
    @EnvironmentObject var model: EditorModel

    private let height: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = max(model.duration, 0.001)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25))

                ForEach(Array(model.segments.enumerated()), id: \.element.id) { i, clip in
                    let x = width * clip.start / span
                    let w = max(width * clip.duration / span - 2, 1)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(fill(index: i, clip: clip))
                        .frame(width: w, height: height - 16)
                        .position(x: x + w / 2 + 1, y: height / 2)
                }

                ForEach(Array(model.segments.enumerated()), id: \.element.id) { i, clip in
                    let x = width * clip.start / span
                    let w = max(width * clip.duration / span - 2, 1)
                    if w > 26 {
                        ClipBadge(number: i + 1, included: clip.included) { model.toggleIncluded(i) }
                            .position(x: x + 20, y: 18)
                    }
                }

                ForEach(Array(model.segments.dropLast().enumerated()), id: \.element.id) { i, clip in
                    ZStack {
                        Color.clear.frame(width: 16, height: height)
                        Capsule().fill(Color.white).frame(width: 3, height: height - 8)
                    }
                    .contentShape(Rectangle())
                    .position(x: width * clip.end / span, y: height / 2)
                        .gesture(
                            // Named space: a gesture on the handle reports location in the handle's own bounds.
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
                                .onChanged { model.moveMarker(after: i, to: $0.location.x / width * span) }
                        )
                        .onTapGesture(count: 2) { model.removeMarker(after: i) }
                        .help("Drag to move this cut, double-click to remove it")
                }

                ForEach(Array(model.segments.enumerated()), id: \.element.id) { i, clip in
                    if clip.panIsManual {
                        ForEach(clip.pan, id: \.time) { key in
                            KeyframeDiamond()
                                .position(x: width * key.time / span, y: height - 12)
                                .onTapGesture { model.seek(to: key.time) }
                                .onTapGesture(count: 2) { model.removeKeyframe(clip: i, at: key.time) }
                                .help("Keyframe — click to jump here, double-click to remove")
                        }
                    }
                }

                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2, height: height)
                    .position(x: width * model.currentTime / span, y: height / 2)
                    .allowsHitTesting(false)
            }
            .coordinateSpace(name: "timeline")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
                    .onChanged { model.seek(to: $0.location.x / width * span) }
            )
        }
        .frame(height: height)
    }

    private func fill(index: Int, clip: Segment) -> Color {
        guard clip.included else { return .white.opacity(index == model.currentIndex ? 0.14 : 0.07) }
        return .accentColor.opacity(index == model.currentIndex ? 0.75 : 0.35)
    }
}

struct KeyframeDiamond: View {
    var body: some View {
        ZStack {
            Color.clear.frame(width: 18, height: 18)
            Rectangle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .rotationEffect(.degrees(45))
                .shadow(color: .black.opacity(0.6), radius: 1)
        }
        .contentShape(Rectangle())
    }
}

struct ClipBadge: View {
    let number: Int
    let included: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 3) {
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9, weight: .bold))
                Text("\(number)").font(.caption2.bold())
            }
            .foregroundStyle(included ? Color.white : Color.white.opacity(0.4))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.3), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(included ? "Click to leave clip \(number) out of the export"
                       : "Click to put clip \(number) back in the export")
    }
}
