import AppKit
import CoreGraphics

/// A color as plain numbers, so a layout can be saved, compared and restored by undo.
struct RGBA: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    static let black = RGBA(r: 0, g: 0, b: 0)
    static let white = RGBA(r: 1, g: 1, b: 1)

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

extension RGBA {
    init(_ color: CGColor) {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = color.converted(to: srgb, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0, 1]
        self.init(r: Double(c[0]), g: Double(c[1]), b: Double(c[2]), a: Double(c.count > 3 ? c[3] : 1))
    }
}

struct CaptionStyle: Codable, Equatable {
    /// PostScript name, so a face like "Condensed Black" survives a save.
    var fontName: String
    /// In output pixels, on the 1080-wide story frame.
    var size: CGFloat
}

/// Bars above and below the footage, and how captions look. One layout for the whole export — a
/// campaign should look like one campaign — while the caption text itself is per clip.
struct StoryLayout: Codable, Equatable {
    var topBar: CGFloat = 0
    var bottomBar: CGFloat = 0
    var barColor = RGBA.black
    var textColor = RGBA.white
    var top = CaptionStyle(fontName: "HelveticaNeue-Bold", size: 72)
    var bottom = CaptionStyle(fontName: "HelveticaNeue-Medium", size: 48)

    /// The footage is never squeezed shorter than this.
    static let minBand: CGFloat = 480
    static let sizeRange: ClosedRange<CGFloat> = 24...180

    /// Where the footage sits on the story frame. Its aspect is the crop's aspect, so bars
    /// change the shape of what's taken from the source, not just what's shown.
    var band: CGRect {
        let frame = CropMath.storySize
        return CGRect(x: 0, y: topBar, width: frame.width, height: frame.height - topBar - bottomBar)
    }

    var aspect: CGFloat { band.width / band.height }
    var hasBars: Bool { topBar > 0 || bottomBar > 0 }
    var maxBars: CGFloat { CropMath.storySize.height - Self.minBand }

    /// Equal bars leaving a band of the given width-to-height ratio.
    static func bars(for ratio: CGFloat) -> CGFloat {
        let frame = CropMath.storySize
        return max((frame.height - frame.width / ratio) / 2, 0).rounded()
    }
}

extension StoryLayout {
    /// Field by field: a synthesized decoder needs every key present, so adding a setting later
    /// would silently throw away the saved layout.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StoryLayout()
        topBar = (try? c.decode(CGFloat.self, forKey: .topBar)) ?? d.topBar
        bottomBar = (try? c.decode(CGFloat.self, forKey: .bottomBar)) ?? d.bottomBar
        barColor = (try? c.decode(RGBA.self, forKey: .barColor)) ?? d.barColor
        textColor = (try? c.decode(RGBA.self, forKey: .textColor)) ?? d.textColor
        top = (try? c.decode(CaptionStyle.self, forKey: .top)) ?? d.top
        bottom = (try? c.decode(CaptionStyle.self, forKey: .bottom)) ?? d.bottom
        if topBar + bottomBar > maxBars { (topBar, bottomBar) = (0, 0) }
    }

    private static let defaultsKey = "storyLayout"

    static func saved() -> StoryLayout {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let layout = try? JSONDecoder().decode(StoryLayout.self, from: data)
        else { return StoryLayout() }
        return layout
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

enum Fonts {
    struct Face: Hashable {
        let name: String
        let label: String
        let weight: Int
        let italic: Bool
    }

    static let families: [String] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted()

    /// Good caption faces, where installed, ahead of the full list.
    static let suggested: [String] = [
        "Helvetica Neue", "Futura", "Avenir Next", "Avenir Next Condensed", "Impact", "Arial Black",
        "DIN Condensed", "DIN Alternate", "Gill Sans", "Didot", "American Typewriter", "Courier New",
    ].filter(families.contains)

    static func faces(of family: String) -> [Face] {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { member in
            guard member.count >= 4, let name = member[0] as? String, let label = member[1] as? String
            else { return nil }
            let traits = (member[3] as? UInt) ?? 0
            return Face(name: name, label: label, weight: (member[2] as? Int) ?? 5,
                        italic: traits & NSFontTraitMask.italicFontMask.rawValue != 0)
        }
    }

    static func family(of fontName: String) -> String {
        NSFont(name: fontName, size: 12)?.familyName ?? "Helvetica Neue"
    }

    /// Switching family keeps the weight you had, so a bold caption stays bold.
    static func closestFace(in family: String, to fontName: String) -> String? {
        let weight = NSFont(name: fontName, size: 12).map { NSFontManager.shared.weight(of: $0) } ?? 5
        let faces = faces(of: family)
        let upright = faces.filter { !$0.italic }
        return (upright.isEmpty ? faces : upright).min { abs($0.weight - weight) < abs($1.weight - weight) }?.name
    }
}
