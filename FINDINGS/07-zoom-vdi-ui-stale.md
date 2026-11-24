# 07 — Zoom VDI user interface shows stale state

**Component:** Zoom VDI plugin / Zoom in the Windows desktop over Citrix
**Effect:** what the settings show is not what is used; confusing when debugging.
**Caused the original problem:** no.

## Observed

- After the headset reconnected, Zoom showed "Same as system (BlackHole 16ch)" as speaker while the plugin actually
  played to the headset (checked on the Mac: the media engine's output device was the Jabra). Reopening settings refreshes it.
- Zoom's input level meter lags about **1–2 s** behind your voice: the plugin measures on the Mac, the value travels
  through Citrix to the Windows UI, and the picture travels back. The audio itself does not take that path.
- The in-meeting audio settings and the main settings window showed different input volume values (finding 03).

## Workaround

Trust the Mac: System Settings → Sound, or CallLift's live icon. Use Zoom's meter only as a delayed cross-check.

## Status

Not reported.
