# 05 — "Personalized audio isolation" removes a Bluetooth earbud voice

**Component:** Zoom (microphone mode "Personalized audio isolation")
**Effect:** with the Jabra earbuds, the voice reached the other participant at about **−80 dBFS**: practically silence.
**Caused the original problem:** no (this mode was not used then), but it is the most severe setting found.

## Evidence

| Mic | Echo cancellation | Zoom gain |
|---|---|---|
| Jabra | Low | −40.9 dB |
| Jabra | Auto | −40.6 dB |
| Jabra | Aggressive | −48.0 dB |
| MacBook built-in | Low | **+3.4 dB** (works) |

Likely cause (not confirmed): the mode does not recognise the speaker's voice in the narrowband, already processed
Bluetooth signal and treats it as someone else.

## Workaround

Never use Personalized audio isolation with Bluetooth earbuds. Use Noise removal.

## Status

Not reported to Zoom yet.
