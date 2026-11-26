# 10 — What was ruled out, and what is still open

## Ruled out (measured)

| Suspect | Result |
|---|---|
| Citrix / virtual channel | The audio does not pass through Citrix: the Zoom media engine on the Mac owns the microphone; Citrix carries only UI and settings. |
| Network / stutter | No gaps added between microphone and receiving participant in any run (detector validated with injected dropouts). |
| Mac input slider (original problem) | 100% at the start; the 36% (finding 04) appeared only after auto-volume tests. |
| Headset defect | Raw earbud level similar to the built-in mic; no dropouts; noise between words digitally silent. |
| Bluetooth codec | Always mSBC 16 kHz: clarity, not loudness (finding 08). |
| Zoom echo cancellation level | Auto / Low / Aggressive not distinguishable in tests. |
| Zoom auto-volume (short runs) | ±1 dB on the transmitted level; its harm is the persistent slider (finding 04). |

## Still open (plausible, not proven)

Why the headset sounded quieter than the laptop to colleagues (at equal default settings both reach Zoom about equally loud, finding 02):

1. **Speaking more quietly with earbuds.** With closed ears you hear your own voice louder inside your head and tend to
   speak softer. Earbud raw levels varied by about 15 dB between sessions; the laptop mic stayed stable.
2. **Narrowband sound is heard as quieter.** The headset carries sound only up to ~8 kHz; at equal measured level,
   speech without high frequencies sounds duller and less present.
3. **The headset's noise gate trims word starts and endings**, which listeners describe as "quiet" or "far away".

A passive recorder (not part of CallLift) logs the real speaking level in calls to check point 1.
