# 01 — No input level normalization in Zoom's VDI path (main cause)

**Component:** Zoom VDI plugin for Citrix, Mac version 7.0.14 (`/Applications/ZoomVDI.app`); its audio engine runs on the Mac as
`zoom.app` inside it (`us.zoom.osx.zoomhdxMediaEngine`)
**Effect:** normal speech reaches the meeting below the level Zoom itself considers good; others hear you quieter than other participants.
**Caused the original problem:** yes, this is the main cause.

## What happens

- With the media plugin, Zoom captures the microphone **on the Mac**. Your voice never passes through Citrix.
- The microphone delivers normal speech at roughly **−25 dBFS** on its loudest moments (earbuds; varying with how you speak).
- Zoom's own input meter turns **green only from about −19 dBFS** (block 4 of 9; calibrated with known signals:
  a steady tone at −12 dBFS peak lights block 4, recorded speech reaches block 4 at about −19 dBFS loudest 50 ms).
  Normal speech showed **1–3 blocks** (red/orange: "too quiet").
- Nothing in Zoom's VDI path raises the level **above unity gain**:
  - "Automatically adjust microphone volume" only moves the Mac's input slider, which is already at 100% = unchanged → it can only lower (finding 04).
  - The input volume slider in the VDI window does nothing (finding 03).
  - "Noise removal" adds a **fixed** ≈ +3 dB, independent of how quiet the input is.
- Zoom does not level participants against each other on the receiving side, so a quiet sender stays quiet.

## Why it is Zoom's to fix

The level problem is not specific to one headset: the MacBook's **built-in mic with Apple's own default processing**
also arrives below Zoom's green zone (Zoom gain +3.1 dB from a similar raw level). If the platform's reference
hardware with the platform's reference processing does not meet Zoom's target, the target or the missing correction is Zoom's.
Zoom is the only component that defines the target (its meter) and is positioned to reach it.

What is missing is a **digital automatic gain control that can also raise the level** toward a target, as WebRTC-based
call apps do (up to about +30 dB).

## Evidence

| Measurement | Value |
|---|---|
| Jabra, Zoom Noise removal: Zoom gain | +3.3 / +3.4 dB (two sessions) |
| MacBook mic + macOS Voice Isolation, Zoom Noise removal: Zoom gain | +3.1 dB |
| Speech 15 dB quieter (raw −45 vs −30 dBFS), Noise removal | only ~2 dB more Zoom gain (+5.5 vs +3.3 dB): no normalization toward a target, which would have added ~15 dB |
| Recorded normal speech, share in Zoom's green zone without any boost | 0 of 21 half-seconds |

## Workaround

CallLift: a gain stage between the microphone and Zoom (+20 dB with a limiter), feeding Zoom through BlackHole 2ch.
A future "auto" mode in CallLift could do real normalization (adaptive gain toward −19 dBFS).

## Status

Not reported to Zoom yet. Untested: whether native Zoom on the Mac (without Citrix) behaves the same.
