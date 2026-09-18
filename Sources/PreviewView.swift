import AVFoundation
import AppKit
import SwiftUI

final class PlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer = CALayer()
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerNSView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

struct PreviewView: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        GeometryReader { geo in
            let video = CropMath.videoRect(container: geo.size, content: model.displaySize)
            let scale = model.displaySize.width > 0 ? video.width / model.displaySize.width : 1
            let source = CropMath.cropRect(source: model.displaySize, offset: model.currentSegment.offset)
            let crop = CGRect(x: video.minX + source.minX * scale, y: video.minY + source.minY * scale,
                              width: source.width * scale, height: source.height * scale)
            let slack = CGSize(width: video.width - crop.width, height: video.height - crop.height)

            ZStack {
                PlayerView(player: model.player)
                Path { path in
                    path.addRect(video)
                    path.addRect(crop)
                }
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: crop.width, height: crop.height)
                    .position(x: crop.midX, y: crop.midY)
                    .shadow(color: .black.opacity(0.5), radius: 3)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { model.dragCrop(by: $0.translation, slack: slack) }
                    .onEnded { _ in model.endCropDrag() }
            )
        }
        .background(Color.black)
    }
}
