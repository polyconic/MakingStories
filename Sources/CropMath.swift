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
