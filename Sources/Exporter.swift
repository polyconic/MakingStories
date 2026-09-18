import AVFoundation
import Foundation

struct StoryError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct VideoInfo {
    var displaySize: CGSize
    var duration: Double
}

enum Exporter {
    static func probe(_ url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw StoryError("No video track in that file.")
        }
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        let duration = try await asset.load(.duration)
        let oriented = CGRect(origin: .zero, size: natural).applying(transform)
        return VideoInfo(displaySize: CGSize(width: abs(oriented.width), height: abs(oriented.height)),
                         duration: duration.seconds)
    }

    /// Renders `range` of `source` cropped to a story frame positioned by `offset`.
    static func export(source: URL, range: CMTimeRange, offset: CGPoint, to output: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw StoryError("No video track in that file.")
        }
        let (natural, transform, minFrame) = try await track.load(.naturalSize, .preferredTransform,
                                                                  .minFrameDuration)
        let duration = try await asset.load(.duration)

        let oriented = CGRect(origin: .zero, size: natural).applying(transform)
        let display = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let crop = CropMath.cropRect(source: display, offset: offset)
        let render = CropMath.storySize
        guard crop.width > 0 else { throw StoryError("Can't work out a crop for that video.") }

        // Oriented pixels to the render canvas: normalize, shift the crop to the origin, fill.
        let t = transform
            .concatenating(CGAffineTransform(translationX: -oriented.minX - crop.minX,
                                             y: -oriented.minY - crop.minY))
            .concatenating(CGAffineTransform(scaleX: render.width / crop.width,
                                             y: render.height / crop.height))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(t, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
        instruction.layerInstructions = [layer]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = render
        videoComposition.frameDuration = minFrame.isValid && minFrame.seconds > 0
            ? minFrame : CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw StoryError("Can't create an export session.")
        }
        session.videoComposition = videoComposition
        session.timeRange = range
        session.shouldOptimizeForNetworkUse = true
        try? FileManager.default.removeItem(at: output)
        try await session.export(to: output, as: .mp4)
    }
}
