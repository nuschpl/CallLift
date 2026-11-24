# 04 — Zoom's auto-volume only lowers, and the lowered level sticks

**Component:** Zoom VDI media plugin ("Automatically adjust microphone volume")
**Effect:** the Mac's input slider for the headset ended at **36%** (≈ −9 dB) and stayed there after auto-volume was switched off.
**Caused the original problem:** no (the slider was 100% before the tests), but it is a trap that makes things worse later.

## What happens

- Auto-volume works by moving the **Mac's** input slider. At 100% (unity, the maximum) it can only go **down**.
- After a test call with auto-volume on, the Jabra's input volume was **0.357 = exactly 91/255**. The 0–255 step fits
  Zoom's own volume scale, not the headset's Bluetooth gain steps (1/15).
- Switching auto-volume off does **not** restore the slider. Every later call starts at the lowered level, and the VDI
  slider (finding 03) cannot fix it.

## Evidence

- Jabra input volume 1.00 at the start of the session and right after the auto-volume test runs; 0.357 after the next call with auto-volume still on.
- Live watching of every input volume change afterwards: reconnecting the headset and three Zoom uses with auto-volume **off** never changed the value.
- In short measured runs, auto-volume changed the transmitted level by no more than ±1 dB; the damage is the persistent slider.

## Workaround

Keep auto-volume **off**. Check System Settings → Sound → Input → headset = 100%. CallLift's "Keep mic volumes at 100%"
resets any lowering automatically.

## Status

Not reported to Zoom yet.
