# 08 — Bluetooth call mode: 16 kHz and a 2–4 s switch

**Component:** Bluetooth standard (HFP), macOS, headset
**Effect:** headset microphone limited to 16 kHz (sound up to ~8 kHz); 2–4 s delay when a call opens the microphone.
**Caused the original problem:** no: it limits clarity, not loudness.

## What happens

- Whenever the microphone is used, the headset switches from music mode (A2DP, stereo, 44.1 kHz) to call mode (HFP).
  The Jabra's microphone then runs as **mSBC, 16 kHz mono** (never the 8 kHz CVSD fallback in our tests).
- The switch took **2.1–3.9 s** (measured each time CallLift opened the mic). Zoom opening the headset directly has the same delay.
- macOS's Bluetooth controller lists **LEA** (LE Audio) and a `SuperWideBandAudio` feature flag, and its Bluetooth
  service contains LE Audio microphone code; the Jabra connected in classic mode only. Whether LE Audio or 32 kHz
  super-wideband could work for this headset on the Mac was not tested.
- AirPods use a proprietary Apple microphone path (AAC-ELD) that third-party headsets cannot use.

## Workaround

None needed for loudness. For better clarity: a USB/wired headset or a manufacturer's USB dongle.

## Status

By design of the Bluetooth standard; LE Audio experiment deferred.
