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
                        .fill(Color.accentColor.opacity(i == model.currentIndex ? 0.75 : 0.35))
                        .frame(width: w, height: height - 16)
                        .position(x: x + w / 2 + 1, y: height / 2)
                        .overlay(alignment: .topLeading) {
                            Text("\(i + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.leading, 6)
                                .padding(.top, 10)
                                .offset(x: x)
                                .allowsHitTesting(false)
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
}
