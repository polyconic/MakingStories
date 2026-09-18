import CoreGraphics

enum CropMath {
    static let storySize = CGSize(width: 1080, height: 1920)
    static let storyAspect: CGFloat = storySize.width / storySize.height

    /// The largest rect of `aspect` that fits in `source`, positioned by `offset`
    /// (0...1 along whichever axis has slack; 0.5 is centered). Top-left origin.
    static func cropRect(source: CGSize, aspect: CGFloat = storyAspect, offset: CGPoint) -> CGRect {
        guard source.width > 0, source.height > 0 else { return .zero }
        var size = source
        if source.width / source.height > aspect {
            size.width = source.height * aspect
        } else {
            size.height = source.width / aspect
        }
        let slack = CGSize(width: source.width - size.width, height: source.height - size.height)
        return CGRect(x: slack.width * offset.x, y: slack.height * offset.y,
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
