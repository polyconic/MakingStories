import AVFoundation
import CoreGraphics
import Vision

/// Where the subject was, normalized to the display frame with a top-left origin. Deliberately
/// not a crop offset — the offset depends on zoom, and the subject's position doesn't.
struct TrackPoint: Equatable {
    var time: Double
    var subject: CGPoint
}

enum Tracker {
    /// How often the subject is located. Between samples the export ramps, so this is a
    /// detection rate, not a frame rate.
    private static let sampleRate: Double = 8

    /// Follows the most prominent subject through `range` and returns crop offsets over time.
    /// Tries faces, then people, then whatever Vision finds salient, so it degrades to
    /// "follow the interesting thing" on footage with nobody in it.
    static func track(source: URL, range: CMTimeRange,
                      progress: @Sendable @escaping (Double) -> Void) async throws -> [TrackPoint] {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw StoryError("No video track in that file.")
        }
        let transform = try await videoTrack.load(.preferredTransform)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? StoryError("Couldn't read the video for tracking.")
        }

        let orientation = imageOrientation(for: transform)
        let start = range.start.seconds
        let span = max(range.duration.seconds, 0.001)
        var raw: [TrackPoint] = []
        var nextSample = start

        while let buffer = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            guard time >= nextSample, let pixels = CMSampleBufferGetImageBuffer(buffer) else { continue }
            nextSample = time + 1 / sampleRate

            if let center = subject(in: pixels, orientation: orientation) {
                // Vision is normalized with a bottom-left origin; everything here is top-left.
                raw.append(TrackPoint(time: time, subject: CGPoint(x: center.x, y: 1 - center.y)))
            }
            progress(min((time - start) / span, 1))
        }

        if reader.status == .failed { throw reader.error ?? StoryError("Tracking failed.") }
        guard raw.count >= 2 else {
            throw StoryError("Couldn't find a subject to follow in that clip.")
        }
        return smooth(raw)
    }

    private static func subject(in pixels: CVPixelBuffer,
                                orientation: CGImagePropertyOrientation) -> CGPoint? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: orientation)

        let faces = VNDetectFaceRectanglesRequest()
        if (try? handler.perform([faces])) != nil,
           let box = largest((faces.results ?? []).map(\.boundingBox)) {
            return CGPoint(x: box.midX, y: box.midY)
        }

        let people = VNDetectHumanRectanglesRequest()
        people.upperBodyOnly = false
        if (try? handler.perform([people])) != nil,
           let box = largest((people.results ?? []).map(\.boundingBox)) {
            return CGPoint(x: box.midX, y: box.midY)
        }

        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        if (try? handler.perform([saliency])) != nil,
           let observation = saliency.results?.first,
           let box = largest((observation.salientObjects ?? []).map(\.boundingBox)) {
            return CGPoint(x: box.midX, y: box.midY)
        }
        return nil
    }

    private static func largest(_ boxes: [CGRect]) -> CGRect? {
        boxes.max { $0.width * $0.height < $1.width * $1.height }
    }

    /// Raw detections jitter frame to frame, which reads as a seasick pan. A deadzone drops
    /// movement too small to be real, then a forward and backward pass smooths without the lag
    /// a causal filter alone would leave behind the subject.
    private static func smooth(_ raw: [TrackPoint], deadzone: CGFloat = 0.02,
                               alpha: CGFloat = 0.3) -> [TrackPoint] {
        var points = raw
        var held = points[0].subject
        for i in points.indices {
            let candidate = points[i].subject
            if abs(candidate.x - held.x) > deadzone { held.x = candidate.x }
            if abs(candidate.y - held.y) > deadzone { held.y = candidate.y }
            points[i].subject = held
        }
        for i in points.indices.dropFirst() {
            points[i].subject = blend(points[i - 1].subject, points[i].subject, alpha)
        }
        for i in points.indices.dropLast().reversed() {
            points[i].subject = blend(points[i + 1].subject, points[i].subject, alpha)
        }
        return points
    }

    private static func blend(_ a: CGPoint, _ b: CGPoint, _ alpha: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * alpha, y: a.y + (b.y - a.y) * alpha)
    }

    private static func imageOrientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        default: .up
        }
    }
}
