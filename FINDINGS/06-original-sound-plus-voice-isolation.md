# 06 — Zoom "Original sound" + macOS "Voice Isolation" costs 10 dB with a Bluetooth headset

**Component:** Zoom (Original sound bypasses its processing) together with macOS Mic Mode
**Effect:** about **−10 dB** with the Jabra; no effect with the built-in mic.
**Caused the original problem:** not originally (Original sound was switched on afterwards); it explains a −10 dB run in early tests.

## Evidence

| Mic | Zoom mode | macOS Mic Mode | Zoom gain |
|---|---|---|---|
| Jabra | Original sound | Standard | +0.1 dB |
| Jabra | Original sound | **Voice Isolation** | **−10.5 dB** |
| Jabra | Noise removal | Voice Isolation | +2.9 dB (no penalty) |
| MacBook built-in | Original sound | Voice Isolation | −0.1 dB |

- Zoom adds level only when its own processing is on (Noise removal ≈ +3 dB). Original sound deliberately changes nothing.
- With Noise removal the Voice Isolation penalty disappears: either Zoom compensates it, or Zoom only routes the signal
  through Apple's processing in Original sound mode. Whether this pushes users toward Zoom's processing on purpose cannot
  be told from the measurements; similar experiences with Windows audio enhancements fit the same pattern (not tested).

## Rule

Use Zoom's processing (Noise removal) **or** the system's, never system processing with Zoom's switched off.
For the Zoom entry in Control Center → Mic Mode, keep **Standard** with a Bluetooth headset.

## Status

Not reported.
