# MakingStories

Drop a video in, it cuts into 30-second story clips, drag to reframe each one to 9:16, export.

`./build.sh` → `build/MakingStories.app`. Plain `swiftc`, Command Line Tools only, no Xcode, ad-hoc signed,
Apple Silicon — same layout as crate and nyquist.

## Constraints

**No `@State`.** The CLT SwiftUI SDK has no SwiftUIMacros plugin, so it won't compile. All UI state,
including transient things like `dropTargeted`, lives on `EditorModel` as `@Published`. Don't
reintroduce `@State` unless the build moves to Xcode.

**Gestures on timeline children need the named coordinate space.** A `DragGesture` attached to a
marker handle reports `location` in that handle's own 16pt bounds, not the timeline's, so the
time math silently comes out wrong. Both timeline gestures use `.named("timeline")`.

## Crop and export

`Segment.offset` is normalized 0...1 along whichever axis has slack — 0.5 centered. `Segment.zoom`
is 1 when the story frame is filled edge to edge; above 1 punches in, and below 1 lets the crop rect
grow past the source, which is what puts bars around the footage. An axis whose slack has gone
negative centers itself, because there is nothing left to choose there.

`CropMath.cropRect` is the single source of truth and drives both the preview overlay and the
export, so what the white box shows is what renders.

The export transform works in **top-left, y-down** coordinates and needs no y-flip. This was
verified, not assumed: color-banded test videos exported at offsets 0 and 1 on both axes, then
probed per-pixel, plus a rotated (non-identity `preferredTransform`) source checked against
ffmpeg's own rendering frame-for-frame. Don't "correct" the transform with a flip without
re-running that test.

Output is always 1080x1920, even when the crop is smaller than that and it means upscaling —
every story platform re-encodes to that spec anyway, and a clean local upscale beats theirs.
Change `CropMath.storySize` if that call turns out wrong.

## Undo

Every edit is a snapshot of `segments` **and** `layout`, registered with the editor **window's**
`UndoManager` so ⌘Z comes off the standard Edit menu. Registering an undo from inside an undo is
what gives redo. The manager is found through `previewView?.window`, not `NSApp.keyWindow` —
through the key window, an edit landing while the app is in the background (tracking finishing)
went unrecorded, and a missing step is worse than none: undoing an earlier change then quietly
reverts the unrecorded one too.

Anything that mutates `segments` or `layout` must call `snapshot(_:)` first. Continuous gestures
snapshot once when they begin — `cropDragStart == nil`, `draggingMarker != i`, a slider's
`onEditingChanged` — or a single drag would bury the stack under dozens of steps. Typing and color
wells use `burstSnapshot`: one step per burst of changes a second apart.

**There must be exactly one undo stack for caption text.** SwiftUI's `TextField` keeps a *private*
undo manager (measured: its did-undo notifications came from a different object than the
window's). Two stacks unwind in focus order, not in the order things happened, and the field's
undo echoes its restored text back through the binding *after* the undo finishes, where it was
recorded as a new edit — ⌘Z ping-ponged the caption and never reached the change before it. The
caption box is therefore `CaptionField`, an `NSTextView` with `allowsUndo = false`, so ⌘Z falls
through to the window's manager and caption edits undo in sequence with everything else. Don't
swap it back for a `TextField`. (The export-name field is still a `TextField`; its name isn't part
of the snapshot, so its private undo harms nothing.)

## Letterbox and captions

`StoryLayout` is one per export — bars, bar and text colors, font and size for each line — and
persists in UserDefaults. Caption *text* is per clip on `Segment`. The layout decodes field by
field with defaults, because a synthesized decoder needs every key and adding a setting would
otherwise silently discard the saved layout.

The bars shrink the band the footage fills, and **`layout.aspect` is the crop's aspect**, not 9:16.
Every `CropMath` call that frames footage must pass it — the source crop box, the story preview,
drag slack, keyframe conversion and export. Pan stays correct across letterbox changes for the
same reason it survives zoom: `TrackPoint` stores the subject, not an offset.

`CaptionRenderer.overlay` draws bars and text onto a transparent 1080×1920 image. The story
preview shows that exact image and the export burns in that exact image through
`AVVideoCompositionCoreAnimationTool`, so the two can't disagree about wrapping or placement. With
no bars and no text it returns nil and the export skips the animation tool entirely — the
original verified path, untouched.

Verified per-pixel against the color-banded test clip: band edges land within a few pixels of the
bar heights at 1:1 and asymmetric bars; the square crop takes source x 280–1000 as predicted; top
text lands in the *top* bar (the overlay isn't flipped) and is centered in its bar to within 4px.

## Panning: tracked or keyframed

`Segment.pan` is a list of `TrackPoint`s, and `panIsManual` says who put them there. Automatic
tracking and hand-set keyframes produce the same shape, so playback and export don't branch on
which made it — only the UI does.

`Tracker` samples at 8 Hz and asks Vision for a face, then a person, then the most salient object,
so footage with nobody in it still follows something. A `TrackPoint` stores **where the subject
was**, not a crop offset — the offset depends on zoom and the subject's position doesn't, so
storing offsets would silently decenter a panned clip the moment its zoom changed. Keyframes set
by dragging go through `CropMath.subject(centeredBy:)`, the exact inverse of
`CropMath.offset(centering:)`; if that round trip ever stops being exact, hand-set keyframes
drift away from where they were put.

Dragging the frame on a **tracked** clip throws the track away and takes manual control. Dragging
on a **keyframed** clip creates or updates a keyframe at the playhead, the way an editor's
auto-keyframe behaves — it must not wipe the other keys, or you could never set the second one.

Detections jitter frame to frame, which reads as a seasick pan. `smooth` applies a deadzone that
drops movement too small to be real, then a forward and a backward pass, the second of which
cancels the lag a causal filter alone would leave behind the subject.

Export ramps the transform between detections. A tracked clip with nothing to pan into — a 9:16
source at 100% zoom has no slack — correctly does nothing; zoom in first.

Headless, which is how the crop math gets tested:

```
MakingStories.app/Contents/MacOS/MakingStories --export <in> <out> <startSec> <endSec> <offsetX> <offsetY> [zoom]
MakingStories.app/Contents/MacOS/MakingStories --track-export <in> <out> <startSec> <endSec>
MakingStories.app/Contents/MacOS/MakingStories --pan-export <in> <out> <startSec> <endSec> <x0> <x1>
MakingStories.app/Contents/MacOS/MakingStories --story-export <in> <out> <startSec> <endSec> <topBar> <bottomBar> [top] [bottom]
```

Exports land in `<name> Story/` on the Desktop, as `<name>_01.mp4`, where the name is the editable
field in the footer. No Finder window is opened afterwards — that was deliberate, not an oversight.
