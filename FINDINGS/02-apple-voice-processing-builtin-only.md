# 02 — Corrected: Apple does not boost the built-in mic; Zoom's Noise removal penalizes noisy input

> **Correction (November 2026).** An earlier version of this finding was titled "Apple's voice processing boosts only
> the built-in mic" and named it as the reason the headset sounded worse than the laptop. **That was wrong.** The same
> measurements, read correctly, show no boost from Apple. The difference comes from Zoom's Noise removal.

**Component:** Zoom (Noise removal), interacting with macOS Mic Mode
**Effect:** with Zoom's Noise removal, a built-in mic **without** Apple's Voice Isolation arrives about 8.5 dB quieter
than with it. Apple's processing itself adds no level.
**Caused the original problem:** no. With the default settings the built-in mic and the Bluetooth headset reach Zoom
about equally loud (+3.1 vs +3.3 dB Zoom gain).

## Evidence

MacBook built-in mic, Zoom gain (received level minus raw level):

| | Zoom mode | macOS Mic Mode (Zoom entry) | Zoom gain |
|---|---|---|---|
| A | Original sound (Zoom's processing **off**) | Standard | +0.6 dB |
| B | Original sound | Voice Isolation | −0.1 dB |
| C | Noise removal (Zoom's processing **on**) | Standard | **−5.4 dB** |
| D | Noise removal | Voice Isolation (macOS's default for the built-in mic) | **+3.1 dB** |

For comparison, the Jabra over Bluetooth with Noise removal: +3.3 dB (Standard), +2.9 dB (Voice Isolation).

- **A vs B: Apple adds nothing.** With Zoom's processing off, Voice Isolation changes the level by 0.7 dB. It was
  really active: the pause level drops from −62 dBFS (room noise passes) to −96 dBFS (noise removed).
- **C vs D: the 8.5 dB appears only with Zoom's Noise removal.** The raw built-in signal carries room noise between
  words (about −62 dBFS); with Noise removal on that input, Zoom delivers it about 5 dB quieter. Once Apple has removed
  the noise (D), Zoom's usual +3 dB applies. The Jabra delivers digital silence between words (its own noise gate), so
  it gets the +3 dB either way.
- macOS selects **Voice Isolation** automatically for the built-in mic when Zoom uses it (observed in Control Center →
  Mic Mode); for the Jabra the mode stayed Standard.

**Caveat:** single runs, from different sessions. The explanation "Zoom's Noise removal lowers noisy input" is the
most likely reading, not yet confirmed by a dedicated test of each stage.

## Workaround

For the built-in mic with Zoom's Noise removal, keep macOS's default Voice Isolation. CallLift's boost covers the
general level gap (finding 01).

## Status

Not reported. Being re-tested stage by stage; this text will be updated with the result.
