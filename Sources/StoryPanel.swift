import AVFoundation
import AppKit
import SwiftUI

// MARK: - The story as it will export

final class StoryVideoNSView: NSView {
    let playerLayer = AVPlayerLayer()
    var videoFrame: CGRect = .zero { didSet { needsLayout = true } }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        // The frame it's given always has the video's own aspect, so fill it exactly.
        playerLayer.videoGravity = .resize
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = videoFrame
        CATransaction.commit()
    }
}

/// A second view onto the same player, positioned so the crop lands on the band and clipped
/// to the story frame. Clipping happens in the layer, where it's reliable for AppKit content.
struct StoryVideoView: NSViewRepresentable {
    let player: AVPlayer?
    let videoFrame: CGRect
    let background: CGColor

    func makeNSView(context: Context) -> StoryVideoNSView {
        let view = StoryVideoNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: StoryVideoNSView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        view.videoFrame = videoFrame
        view.layer?.backgroundColor = background
    }
}

struct StoryPreview: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        GeometryReader { geo in
            let frame = CropMath.videoRect(container: geo.size, content: CropMath.storySize)
            let k = frame.width / CropMath.storySize.width
            let layout = model.layout
            let source = model.displaySize
            let clip = model.currentSegment
            let crop = CropMath.cropRect(source: source, aspect: layout.aspect,
                                         offset: clip.offset(at: model.currentTime, source: source,
                                                             aspect: layout.aspect),
                                         zoom: clip.zoom)
            let band = layout.band
            let s = crop.width > 0 ? band.width * k / crop.width : 0
            // The whole source frame, relative to the story frame, placed so the crop fills the band.
            let video = CGRect(x: band.minX * k - crop.minX * s, y: band.minY * k - crop.minY * s,
                               width: source.width * s, height: source.height * s)

            ZStack {
                StoryVideoView(player: model.player, videoFrame: video, background: layout.barColor.cgColor)
                if let overlay = model.previewOverlay() {
                    Image(decorative: overlay, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .shadow(color: .black.opacity(0.4), radius: 6)
        }
    }
}

// MARK: - Letterbox and captions

struct StoryPanel: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                letterbox
                Divider()
                CaptionEditor(top: true)
                CaptionEditor(top: false)
                Divider()
                HStack {
                    Text("Text color")
                    Spacer()
                    ColorPicker("Text color", selection: Binding(get: { model.layout.textColor.cgColor },
                                                                 set: { model.setTextColor($0) }),
                                supportsOpacity: false)
                        .labelsHidden()
                }
                Button("Apply Text to All Clips") { model.applyCaptionsToAll() }
                    .frame(maxWidth: .infinity)
                    .help("Give every clip this clip's top and bottom text")
            }
            .padding(16)
        }
    }

    private var letterbox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Letterbox").font(.headline)
            HStack(spacing: 6) {
                band("Full", nil)
                band("4:5", 4.0 / 5.0)
                band("1:1", 1)
                band("16:9", 16.0 / 9.0)
            }
            bar("Top", top: true)
            bar("Bottom", top: false)
            HStack {
                Text("Bar color")
                Spacer()
                ColorPicker("Bar color", selection: Binding(get: { model.layout.barColor.cgColor },
                                                            set: { model.setBarColor($0) }),
                            supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func band(_ label: String, _ ratio: CGFloat?) -> some View {
        let help = ratio == nil ? "No bars — footage fills the frame" : "Footage in a \(label) band, equal bars above and below"
        if model.bandMatches(ratio) {
            Button(label) { model.applyBand(ratio) }.buttonStyle(.borderedProminent).help(help)
        } else {
            Button(label) { model.applyBand(ratio) }.buttonStyle(.bordered).help(help)
        }
    }

    private func bar(_ label: String, top: Bool) -> some View {
        let value = top ? model.layout.topBar : model.layout.bottomBar
        let other = top ? model.layout.bottomBar : model.layout.topBar
        let limit = max(model.layout.maxBars - other, 1)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value)) px").foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.caption)
            Slider(value: Binding(get: { Double(value) }, set: { model.setBar(CGFloat($0), top: top) }),
                   in: 0...Double(limit)) { editing in
                // One undo step for the whole drag.
                if editing { model.beginEdit("Letterbox") }
            }
        }
    }
}

struct CaptionEditor: View {
    @EnvironmentObject var model: EditorModel
    let top: Bool

    var body: some View {
        let style = top ? model.layout.top : model.layout.bottom
        VStack(alignment: .leading, spacing: 8) {
            Text(top ? "Top text" : "Bottom text").font(.headline)
            CaptionField(text: model.caption(top: top)) { model.setCaption($0, top: top) }
                .frame(height: 54)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.35)))
                .overlay(alignment: .topLeading) {
                    if model.caption(top: top).isEmpty {
                        Text(top ? "NEW SINGLE OUT FRIDAY" : "Artist — Track")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 7)
                            .padding(.top, 4)
                            .allowsHitTesting(false)
                    }
                }
            FontPicker(fontName: style.fontName) { model.setFont($0, top: top) }
                .equatable()
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Size")
                    Spacer()
                    Text("\(Int(style.size)) px").foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.caption)
                Slider(value: Binding(get: { Double(style.size) },
                                      set: { model.setFontSize(CGFloat($0), top: top) }),
                       in: Double(StoryLayout.sizeRange.lowerBound)...Double(StoryLayout.sizeRange.upperBound)) { editing in
                    if editing { model.beginEdit("Text Size") }
                }
            }
        }
    }
}

/// A caption box that leaves undo to the model. SwiftUI's TextField keeps a private undo manager,
/// so its typing unwound on a separate stack from every other edit — in focus order rather than
/// the order things happened, and restoring text another undo had already taken back. With the
/// text view's own undo off, ⌘Z falls through to the window's manager and captions undo in
/// sequence with everything else.
struct CaptionField: NSViewRepresentable {
    let text: String
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.allowsUndo = false
        view.isRichText = false
        view.font = .systemFont(ofSize: NSFont.systemFontSize)
        view.textContainerInset = NSSize(width: 2, height: 4)
        view.backgroundColor = .textBackgroundColor
        view.delegate = context.coordinator
        view.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void = { _ in }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            onChange(view.string)
        }

        /// Return is a line break in a caption; Tab moves on, the way it does in a form.
        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertTab(_:)) {
                view.window?.selectNextKeyView(nil)
                return true
            }
            if selector == #selector(NSResponder.insertBacktab(_:)) {
                view.window?.selectPreviousKeyView(nil)
                return true
            }
            return false
        }
    }
}

/// Plain value in, closure out. Equatable so the several-hundred-item family menu isn't rebuilt
/// on every playhead tick — the panel above it redraws that often.
struct FontPicker: View, Equatable {
    let fontName: String
    let onSelect: (String) -> Void

    static func == (a: FontPicker, b: FontPicker) -> Bool { a.fontName == b.fontName }

    var body: some View {
        let family = Fonts.family(of: fontName)
        VStack(alignment: .leading, spacing: 6) {
            Picker("Font", selection: Binding(get: { family }, set: { chosen in
                if let face = Fonts.closestFace(in: chosen, to: fontName) { onSelect(face) }
            })) {
                if !Fonts.suggested.isEmpty {
                    Section("Suggested") {
                        ForEach(Fonts.suggested, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("All fonts") {
                    ForEach(Fonts.families, id: \.self) { Text($0).tag($0) }
                }
            }
            Picker("Style", selection: Binding(get: { fontName }, set: { onSelect($0) })) {
                ForEach(Fonts.faces(of: family), id: \.name) { Text($0.label).tag($0.name) }
            }
        }
    }
}
