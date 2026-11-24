# 02 — Apple's voice processing boosts only the built-in mic

**Component:** macOS (voice processing / Mic Mode used by the Zoom plugin)
**Effect:** the MacBook's built-in mic gets about +8.5 dB from Apple's processing; a Bluetooth headset gets nothing.
**Caused the original problem:** yes, it is the most likely measured reason why the headset sounded worse than the laptop.

## What happens

- macOS selects **Voice Isolation** automatically for the built-in mic (observed: switching Zoom to the MacBook mic
  turned Control Center → Mic Mode → Zoom to Voice Isolation by itself). For the Jabra the mode was Standard.
- With Zoom Noise removal:

| Mic | macOS Mic Mode (Zoom entry) | Zoom gain |
|---|---|---|
| MacBook built-in | Standard | **−5.4 dB** |
| MacBook built-in | Voice Isolation (its default) | **+3.1 dB** |
| Jabra (Bluetooth) | Standard | +3.3 dB |
| Jabra (Bluetooth) | Voice Isolation | +2.9 dB |

So Apple's processing lifts the built-in mic by about **8.5 dB**, but does not lift the Bluetooth headset.
Apple's processing apparently assumes a headset handles its own level.

## Note

At equal raw level, built-in (with its default) and headset then arrive about equally loud. The remaining difference
people hear likely also comes from how you speak and from narrowband sound (finding 10).

## Workaround

CallLift's boost; for the built-in mic keep macOS's default Voice Isolation when using Zoom Noise removal.

## Status

macOS behaviour; not reported.
