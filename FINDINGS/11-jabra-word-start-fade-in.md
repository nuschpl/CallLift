# 11 — The headset fades words in over about 100 ms

**Component:** Jabra Elite 10 (noise gate / noise reduction in the earbud firmware)
**Effect:** sentence beginnings and short words ("yes", "no", "ok") arrive weak; listeners report "hardly audible at the
start of sentences" and a varying volume.
**Caused the original problem:** contributes (perceived quietness), independent of the overall level.

## What happens

Between words the earbuds output near digital silence (about −90 dBFS). When you start speaking, the gate opens and the
level **ramps up over roughly 100 ms** instead of starting at once. The first 10 ms of a word arrive about 40–50 dB below
its peak. Short words are often only 150–250 ms long, so a large part of them is attenuated.

## Evidence

Time from the gate opening until the level is within 6 dB of the word's peak (10 ms frames):

| Recording | Speech bursts | Median time to near-full level | First 10 ms vs peak |
|---|---|---|---|
| Real 37-min call (after CallLift +20 dB, before Zoom) | 133 | **110 ms** | −42.5 dB |
| Jabra raw, test without Zoom (three runs) | 17 / 15 / 9 | **120 / 180 / 50 ms** | −53 / −53 / −48 dB |
| MacBook built-in mic, same speech | 16 | **30 ms** | −12.5 dB |

The MacBook comparison is approximate: its "start" is the rise above room noise rather than a gate opening. The
behaviour is the same with and without Zoom, so it comes from the headset itself. Amplification (CallLift) does not
change the shape of the fade-in, which is why lowering or raising the boost did not help.

## Workarounds

- Do not stack more trimming on top: Zoom's Noise removal keeps only 87–97% of quiet speech; with CallLift supplying
  the level, use Zoom's **Original sound** (all boxes unchecked). In a real call this removed the complaints.
- Possible CallLift experiment: lift quiet word starts (upward compression) without lifting the gate's silence.
- A wired/USB headset or the built-in mic do not have this fade-in.

## Status

Headset firmware behaviour; cannot be switched off in the Jabra app as far as known. Not reported.
