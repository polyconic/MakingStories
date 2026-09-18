import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let body = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(srgbRed: 0.28, green: 0.30, blue: 0.86, alpha: 1),
                        NSColor(srgbRed: 0.12, green: 0.13, blue: 0.36, alpha: 1)])!
        .draw(in: body, angle: -90)

    let frameHeight = rect.height * 0.62
    let frameWidth = frameHeight * 9 / 16
    let frame = NSRect(x: rect.midX - frameWidth / 2, y: rect.midY - frameHeight / 2,
                       width: frameWidth, height: frameHeight)
    let path = NSBezierPath(roundedRect: frame, xRadius: frameWidth * 0.12, yRadius: frameWidth * 0.12)
    path.lineWidth = max(s * 0.035, 1)
    NSColor.white.setStroke()
    path.stroke()

    let dot = max(s * 0.055, 1.5)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: frame.midX - dot / 2, y: frame.midY - dot / 2,
                                width: dot, height: dot)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for px in [16, 32, 64, 128, 256, 512, 1024] {
    try! render(px).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(px).png"))
}
