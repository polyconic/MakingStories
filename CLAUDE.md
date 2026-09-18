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

Headless, which is how the crop math gets tested:

```
MakingStories.app/Contents/MacOS/MakingStories --export <in> <out> <startSec> <endSec> <offsetX> <offsetY> [zoom]
```

Exports land in `<name> Story/` on the Desktop, as `<name>_01.mp4`, where the name is the editable
field in the footer. No Finder window is opened afterwards — that was deliberate, not an oversight.
