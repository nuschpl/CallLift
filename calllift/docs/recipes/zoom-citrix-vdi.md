# Recipe: Mac host + Citrix (Windows desktop) + Zoom VDI media plugin

CallLift preset: **Mac + Citrix (Windows) + Zoom media plugin** (default).
Status: **tested** (November 2026). Every setting below was checked by measurement; the reason is given so you can
decide for yourself if your setup differs.

Tested with: macOS 27.2, Citrix Workspace app for Mac 26.09, Zoom VDI plugin for Citrix, Mac version 7.0.14 (27210)
(installed as `/Applications/ZoomVDI.app`, bundle ID `us.zoom.ZoomVDI`),
Zoom Workplace in the Windows desktop, Jabra Elite 10 earbuds (firmware 4.6.0) over Bluetooth, BlackHole 2ch.

## How the audio actually flows here

```
headset ──Bluetooth (call mode, 16 kHz)──► Mac ──► CallLift (+20 dB, limiter) ──► BlackHole 2ch
        ──► Zoom VDI plugin ON THE MAC: ZoomVDI.app → zoom.app (us.zoom.osx.zoomhdxMediaEngine):
            echo cancellation, noise removal, encoding
        ──► internet ──► Zoom servers ──► other participants
Citrix carries only Zoom's user interface and settings, not the audio.
```

So everything that changes your voice happens **on the Mac**, even though you click the settings in Zoom inside Windows.
In Control Center → Mic Mode and in macOS's microphone privacy list, this audio engine appears as **zoom** / **ZoomVDI**.

## Settings: Zoom inside the Citrix/Windows desktop

Zoom → Settings → **Audio**:

| Setting | Value | Why |
|---|---|---|
| Microphone | **BlackHole 2ch** | CallLift's boosted voice arrives there. "Same as system" is not enough: pick it explicitly. |
| Speaker | your headset, or "Same as system (headset)" | **Never BlackHole 2ch**: Zoom would play the meeting into your own microphone path and you would hear nothing. |
| Input volume slider | leave at maximum | **Has no effect** in VDI: it only mirrors the Mac value; in a meeting it keeps a value but changes nothing (measured: 100% / 50% / 25% gave the same level ±0.3 dB). |
| Automatically adjust microphone volume | **OFF** | It turned the Mac's input slider for the headset down to 36% (about −9 dB) and the lowered value **stayed** after switching it off. With CallLift's "Keep mic volumes at 100%" this is undone, but keep it off anyway. |

Zoom → Settings → Audio → **Microphone modes**:

| Mode | Use? | Why |
|---|---|---|
| **Original sound for musicians**, with **all three boxes unchecked** (High-fidelity, Echo cancellation, Stereo) | **ON** (top bar shows "Original sound for musicians: on") | With CallLift supplying the level, Zoom's own processing is not needed and only hurts: Noise removal trims the already slow word starts of Bluetooth earbuds (finding 11) and its double-talk handling cut people off when both spoke ("walkie-talkie"). In a 37-minute real call with this setting: no walkie-talkie effect, speech at about −7 dBFS (Zoom's green zone), no complaints. The headset's own noise gate keeps background noise out. **Provisional:** confirmed in one real call so far. |
| Noise removal (default) | alternative | Use it if keyboard or room noise comes through (e.g. without a gating headset, or with the MacBook mic). Adds about +3 dB but keeps only 87–97% of quiet speech and penalizes noisy input. |
| Personalized audio isolation | **NEVER** with Bluetooth earbuds | Removed the earbud voice almost completely: **−41 to −48 dB**, in every echo setting. (Worked with the MacBook mic.) |

With Original sound, macOS Mic Mode for the Zoom entry **must be Standard**: Original sound + Voice Isolation cost the
earbuds **−10 dB** (finding 06).

Zoom → Settings → Audio → **Advanced**:

| Setting | Value | Why |
|---|---|---|
| Echo cancellation | **Auto** | Used in the successful real call together with Original sound. In our tests Auto/Low/Aggressive could not be told apart (nothing played in the ears while talking); Auto adapts if the boosted signal carries echo remnants from the earbuds. |
| Windows system audio enhancements | Off | Applies to Windows audio devices; your audio is processed on the Mac, so it does not matter, but Off avoids surprises. |
| Signal processing by Windows audio device drivers | Off | Same reason. |
| Suggest switching to USB audio devices | any | Only a pop-up. |

Check that the **media plugin is connected**: Zoom → Settings → Statistics (or About) shows the VDI plugin as connected.
If it is not (fallback mode), Zoom uses Citrix's own audio path instead, and everything here changes.

**Citrix Workspace app** (Mac): microphone/webcam access for the Citrix session can stay **"Don't use my microphone and
webcam"**. The Zoom plugin captures audio on the Mac itself and does not need it; Windows then has no access to your mic.

## Settings: the Mac (host)

| Setting | Value | Why |
|---|---|---|
| System Settings → Sound → **Input** | **your headset** | CallLift follows the macOS default input (or use CallLift → Microphone → "Always use"). **Never BlackHole 2ch** as the default input in this setup. |
| System Settings → Sound → **Output** | your headset | You hear the meeting there. Not BlackHole. |
| Input volume slider for the headset (Sound → Input) | **100%** | Below 100% is a straight loss (36% ≈ −9 dB). CallLift's "Keep mic volumes at 100%" holds it there. |
| Control Center → **Mic Mode** → the **Zoom** entry | **Standard** | Voice Isolation **is offered** for the headset too, and together with Original sound it cost **−10 dB**; with Noise removal it made no difference. Wide Spectrum was not offered for Zoom. |
| Control Center → Mic Mode → the **CallLift** entry | Standard (has no effect) | CallLift reads the microphone directly, without Apple's voice processing. |
| CallLift → **Keep mic volumes at 100%** | **ON** | Undoes any lowering by auto-volume or other apps. |
| CallLift → **Boost** | **+20 dB** (green) | See "What we measured". Use +24 if you speak quietly and the icon stays yellow. |

Optional but recommended: keep **Zoom's own meter** in mind only as a cross-check. It lags 1–2 s through Citrix;
CallLift's menu bar icon uses the same thresholds live.

## What we measured

All levels in dBFS. "Zoom gain" = level received by a second, muted meeting participant minus the raw microphone level
(independent of how loudly you spoke). Same speech, same sitting, unless noted.

**The core problem**

| Measurement | Result |
|---|---|
| Normal speech through the earbuds, loudest moments | about −25 dBFS (varied −30 … −45 between sessions) |
| Zoom's meter: first green block (block 4 of 9) | steady tone −12 dBFS; your speech at about −19 dBFS loudest moments |
| Your normal speech on Zoom's meter | 1–3 of 9 blocks (red/orange zone), typically 2 |
| MacBook built-in mic, same speech | similar raw level: not a headset defect |

**Zoom modes with the earbuds (no boost)**

| Zoom setting | Zoom gain | Speech kept |
|---|---|---|
| Noise removal, echo Low/Auto/Aggressive | +3.3 … +3.4 dB | 87–97% |
| Original sound, any sub-options | −1.1 … +0.1 dB | 86–100% |
| Original sound + macOS Voice Isolation | **−10.5 dB** | 96% |
| Personalized audio isolation | **−41 … −48 dB** | voice removed |
| Noise removal / Original sound + auto-volume (short runs) | no change (±1 dB) | |

**Volume controls**

| Control | Effect |
|---|---|
| Mac input slider (Sound → Input) | the only one that changes the level |
| Zoom auto-volume | lowered the Mac slider to 36% and it stayed there |
| Zoom input slider in VDI | display only / no effect (100% vs 25%: ±0.3 dB) |

**With CallLift**

| Measurement | Result |
|---|---|
| Gain accuracy | exactly the set value (+10.0 dB measured at +10) |
| Extra delay | 22.1 ms, identical for 12 clicks |
| Stability | 0 dropouts in 50–60 s runs, 16 kHz → 48 kHz with drift control |
| Recorded normal speech, share of time in Zoom's green zone | none at 0 dB · 5 of 22 half-seconds at +10 dB · 18 of 22 at +15 dB; in live use +20 dB was needed for normal conversation |
| Headset taken out mid-call | silence + red icon within 1 s; resumed 35 ms after it came back |
| Bluetooth call-mode switch at call start | 2–4 s (macOS/Bluetooth, not CallLift) |

**Things that are not the problem**

- **Citrix**: the audio does not pass through it (verified: the Zoom media engine on the Mac owns the microphone).
- **Network / stutter**: no gaps added between the microphone and the receiving participant in any test run.
- **Bluetooth codec**: the headset microphone always runs as mSBC 16 kHz (call mode); this limits clarity (up to ~8 kHz), not loudness.
