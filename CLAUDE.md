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

Every edit is a snapshot of `segments` registered with the **window's** `UndoManager`, not a
private stack — that way ⌘Z comes off the standard Edit menu and a focused text field keeps its
own undo through the responder chain. Registering an undo from inside an undo is what gives redo.

Anything that mutates `segments` must call `snapshot(_:)` first. Continuous gestures snapshot once
when they begin — `cropDragStart == nil`, `draggingMarker != i`, the slider's `onEditingChanged` —
or a single drag would bury the stack under dozens of steps.

## Panning: tracked or keyframed

`Segment.pan` is a list of `TrackPoint`s, and `panIsManual` says who put them there. Automatic
tracking and hand-set keyframes produce the same shape, so playback and export don't branch on
which made it — only the UI does.

`Tracker` samples at 8 Hz and asks Vision for a face, then a person, then the most salient object,
so footage with nobody in it still follows something. A `TrackPoint` stores **where the subject
was**, not a crop offset — the offset depends on zoom and the subject's position doesn't, so
storing offsets would silently decentre a panned clip the moment its zoom changed. Keyframes set
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
```

Exports land in `<name> Story/` on the Desktop, as `<name>_01.mp4`, where the name is the editable
field in the footer. No Finder window is opened afterwards — that was deliberate, not an oversight.
