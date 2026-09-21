# MakingStories

Turns one long video into story-sized vertical clips.

Any video editor does this, but most of the time it's overkill and it's tedious: a ten-minute video becomes twenty
30-second clips, and every one of them needs the frame moved so the subject is actually inside
a 9:16 crop. This does only that job. Drop a video in, it cuts at 30 seconds, you frame each
clip, you export.

## Building

```
./build.sh
```

Produces `build/MakingStories.app`. Needs only the Xcode Command Line Tools — no Xcode, no
package manager, no dependencies. Subject tracking uses Vision, which ships with macOS.

## Using it

Drop a video on the window (or ⌘O). It's cut into 30-second clips straight away, so the common
case needs no setup at all.

**Cuts.** `M` cuts at the playhead. Drag the white markers on the timeline to move a cut,
double-click one to remove it. **Every 30s** re-cuts the whole thing, **One Clip** removes every
cut.

**Framing.** Drag on the video to move the 9:16 frame. Scroll over the video to zoom, or use
⌘−/⌘+; the percentage readout is a button that puts you back to 100%. Zoom below 100% opens the
frame out past the footage and gives you bars, which is sometimes what you want. **Apply to All**
gives every clip the current clip's framing.

**Following a moving subject.** **Track** analyses the clip and pans to follow whoever's in it —
Vision looks for a face, then a person, then whatever it reads as salient, so footage with nobody
in it still follows something. Note that a clip with no room to pan can't do anything: an
already-vertical source at 100% zoom is the whole frame, so zoom in first.

**Keyframes**, for when there are several people and only you know which one matters. Put the
playhead where you want it, frame the shot, press `K`. Move the playhead, drag the frame, and it
keyframes again automatically. Diamonds appear on the timeline — click to jump to one,
double-click to remove it. **Clear Pan** drops back to a fixed frame.

**Choosing what to export.** Every clip has a checkmark badge on the timeline; click it to leave
that clip out. **Only This** exports just the clip under the playhead. Numbering runs over what
you actually picked, so skipping the second of three gives you `_01` and `_02`, not `_01` and
`_03`.

⌘Z undoes all of it. A drag is one step, not forty.

## Export

⌘E. Clips land in `<name> Story/` on the Desktop, named after the editable field in the footer.
1080×1920 H.264, audio kept, no Finder window thrown in your face afterwards.

Mute (`S`) is preview only — exported clips keep their sound.
