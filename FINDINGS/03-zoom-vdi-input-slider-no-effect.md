# 03 — Zoom's input volume slider has no effect in VDI

**Component:** Zoom VDI media plugin / Zoom in the Windows desktop
**Effect:** the obvious fix ("turn the mic volume up in Zoom") does nothing.
**Caused the original problem:** no, but it prevents fixing it inside Zoom.

## What happens

- **Outside a meeting:** the slider in Zoom → Settings → Audio only **displays** the Mac's input volume for the selected
  microphone. Dragging it changes nothing on the Mac, and it snaps back to the Mac value after about 2 s.
  (It showed ~33% when the Mac slider was at 36%, finding 04.)
- **In a meeting:** the slider keeps the value you set, but has **no effect** on what others hear.
- The main Zoom settings window and the in-meeting audio settings showed different values at the same time.

## Evidence

Fixed reference speech played into Zoom's microphone (BlackHole 2ch), measured at a muted second participant, same meeting:

| In-meeting slider | Zoom gain |
|---|---|
| 100% | +2.4 dB |
| ~50% | +2.7 dB |
| 25% | +2.2 dB |

A working slider at 25% would have cost about −12 dB. The Mac's input volume stayed at 100% throughout; the plugin's
stored value (`micphone_volume` in the `us.zoom.osx.zoomhdxMediaEngine` preferences) stayed at 255/255.

The read direction (Mac value → VDI display) works repeatably within ~2 s; the write direction never did. Consistent
behaviour, so most likely the plugin's design rather than an unreliable Citrix virtual channel (inferred).

Even a working slider would stop at the Mac's 100% (unity): it would not fix finding 01 on its own.

## Workaround

Set the level on the Mac: System Settings → Sound → Input → the microphone → 100%. Use CallLift for more than unity.

## Status

Not reported to Zoom yet.
