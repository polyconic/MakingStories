import AppKit
import CoreGraphics

/// Draws bars and captions onto a transparent story-sized canvas. The preview shows this exact
/// image and the export burns in this exact image, so the two can't disagree about wrapping,
/// size or placement.
enum CaptionRenderer {
    private static let sideMargin: CGFloat = 0.07
    private static let padding: CGFloat = 24
    /// Where text goes when it doesn't fit in a bar and has to sit over the footage — clear of
    /// the app chrome Reels and TikTok draw at the top and bottom of the screen.
    private static let safeTop: CGFloat = 0.12
    private static let safeBottom: CGFloat = 0.20

    static func overlay(layout: StoryLayout, top: String, bottom: String) -> CGImage? {
        let top = top.trimmingCharacters(in: .whitespacesAndNewlines)
        let bottom = bottom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard layout.hasBars || !top.isEmpty || !bottom.isEmpty else { return nil }

        let size = CropMath.storySize
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Top-left origin, y down, like every other coordinate in the app.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)

        ctx.setFillColor(layout.barColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: layout.topBar))
        ctx.fill(CGRect(x: 0, y: size.height - layout.bottomBar, width: size.width, height: layout.bottomBar))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let width = size.width * (1 - 2 * sideMargin)

        if !top.isEmpty {
            let height = measure(top, style: layout.top, width: width)
            let fits = layout.topBar >= height + 2 * padding
            let y = fits ? (layout.topBar - height) / 2 : size.height * safeTop
            draw(top, style: layout.top, color: layout.textColor, overFootage: !fits,
                 in: CGRect(x: size.width * sideMargin, y: y, width: width, height: height))
        }
        if !bottom.isEmpty {
            let height = measure(bottom, style: layout.bottom, width: width)
            let fits = layout.bottomBar >= height + 2 * padding
            let y = fits
                ? size.height - layout.bottomBar + (layout.bottomBar - height) / 2
                : size.height * (1 - safeBottom) - height
            draw(bottom, style: layout.bottom, color: layout.textColor, overFootage: !fits,
                 in: CGRect(x: size.width * sideMargin, y: y, width: width, height: height))
        }

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private static func measure(_ text: String, style: CaptionStyle, width: CGFloat) -> CGFloat {
        ceil(attributed(text, style: style, color: .white, shadow: false)
            .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
            .height)
    }

    private static func draw(_ text: String, style: CaptionStyle, color: RGBA, overFootage: Bool,
                             in rect: CGRect) {
        // Text on a bar is legible as it is; text on footage needs a shadow to survive a bright frame.
        attributed(text, style: style, color: color, shadow: overFootage)
            .draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private static func attributed(_ text: String, style: CaptionStyle, color: RGBA,
                                   shadow: Bool) -> NSAttributedString {
        let font = NSFont(name: style.fontName, size: style.size) ?? .boldSystemFont(ofSize: style.size)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: color.cgColor) ?? .white,
            .paragraphStyle: paragraph,
        ]
        if shadow {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.55)
            s.shadowBlurRadius = style.size * 0.2
            s.shadowOffset = .zero
            attributes[.shadow] = s
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}
