import CoreGraphics

enum CropMath {
    static let storySize = CGSize(width: 1080, height: 1920)
    static let storyAspect: CGFloat = storySize.width / storySize.height

    static let zoomRange: ClosedRange<CGFloat> = 0.25...4

    /// The rect of `aspect` that the story frame takes from `source`, positioned by `offset`
    /// (0...1 along whichever axis has slack; 0.5 is centered). Top-left origin.
    ///
    /// `zoom` 1 is the largest such rect that fits — the frame filled edge to edge. Above 1 punches
    /// in. Below 1 the rect grows past the source, which is what puts bars around the footage, and
    /// an axis with nothing left to choose centers itself.
    static func cropRect(source: CGSize, aspect: CGFloat = storyAspect,
                         offset: CGPoint, zoom: CGFloat = 1) -> CGRect {
        guard source.width > 0, source.height > 0 else { return .zero }
        var size = source
        if source.width / source.height > aspect {
            size.width = source.height * aspect
        } else {
            size.height = source.width / aspect
        }
        let z = min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound)
        size = CGSize(width: size.width / z, height: size.height / z)

        let slack = CGSize(width: source.width - size.width, height: source.height - size.height)
        return CGRect(x: slack.width * (slack.width > 0 ? offset.x : 0.5),
                      y: slack.height * (slack.height > 0 ? offset.y : 0.5),
                      width: size.width, height: size.height)
    }

    /// The offset that puts `subject` (normalized, top-left origin) in the middle of the crop,
    /// as far as the slack allows. Derived at use time, so a tracked clip survives a zoom change.
    static func offset(centering subject: CGPoint, source: CGSize,
                       aspect: CGFloat = storyAspect, zoom: CGFloat = 1) -> CGPoint {
        let crop = cropRect(source: source, aspect: aspect, offset: CGPoint(x: 0.5, y: 0.5), zoom: zoom)
        let slack = CGSize(width: source.width - crop.width, height: source.height - crop.height)
        let point = CGPoint(x: subject.x * source.width, y: subject.y * source.height)
        return CGPoint(
            x: slack.width > 0 ? clamp((point.x - crop.width / 2) / slack.width) : 0.5,
            y: slack.height > 0 ? clamp((point.y - crop.height / 2) / slack.height) : 0.5)
    }

    /// The inverse: which subject point a given framing is centered on. Lets a frame positioned
    /// by hand be stored the same way a tracked one is.
    static func subject(centeredBy offset: CGPoint, source: CGSize,
                        aspect: CGFloat = storyAspect, zoom: CGFloat = 1) -> CGPoint {
        guard source.width > 0, source.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        let crop = cropRect(source: source, aspect: aspect, offset: offset, zoom: zoom)
        return CGPoint(x: crop.midX / source.width, y: crop.midY / source.height)
    }

    static func clamp(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }

    /// Where an aspect-fit video sits inside its container.
    static func videoRect(container: CGSize, content: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        var size = container
        if content.width / content.height > container.width / container.height {
            size.height = container.width * content.height / content.width
        } else {
            size.width = container.height * content.width / content.height
        }
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}
