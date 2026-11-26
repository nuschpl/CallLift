# Findings

Each file is one issue found while debugging "my microphone is too quiet in Zoom" on a Mac with Citrix and the
Zoom VDI media plugin (November 2026). Every file states the responsible component, the effect, the measured
evidence, the workaround and the status.

Test setup: macOS 27.2, Citrix Workspace app for Mac 26.09, Zoom VDI plugin for Citrix (Mac) 7.0.14 (27210)
(`/Applications/ZoomVDI.app`, `us.zoom.ZoomVDI`; its audio engine is `zoom.app` inside it, `us.zoom.osx.zoomhdxMediaEngine`),
Zoom Workplace in the Windows desktop, Jabra Elite 10 earbuds (firmware 4.6.0) over Bluetooth, MacBook Pro built-in mic,
BlackHole 2ch. Levels in dBFS. "Zoom gain" = level received by a second, muted meeting participant minus the raw
microphone level, which is independent of how loudly the speaker talked.

| # | Finding | Component | Caused the original problem? |
|---|---|---|---|
| 01 | [No input level normalization in Zoom's VDI path](01-zoom-no-input-normalization.md) | Zoom VDI plugin | **yes: main cause** |
| 02 | [Corrected: Apple does not boost the built-in mic; Zoom's Noise removal penalizes noisy input](02-apple-voice-processing-builtin-only.md) | Zoom (with macOS Mic Mode) | no (earlier version wrongly said yes) |
| 03 | [Zoom's input volume slider has no effect in VDI](03-zoom-vdi-input-slider-no-effect.md) | Zoom VDI plugin | no, but blocks the obvious fix |
| 04 | [Zoom's auto-volume only lowers, and the lowered level sticks](04-zoom-auto-volume-only-lowers.md) | Zoom VDI plugin | no (seen later), but a trap |
| 05 | [Personalized audio isolation removes a Bluetooth earbud voice](05-zoom-personalized-isolation-removes-voice.md) | Zoom | no (not used then), severe |
| 06 | [Original sound + macOS Voice Isolation costs 10 dB](06-original-sound-plus-voice-isolation.md) | Zoom + macOS | possibly in later tests, not originally |
| 07 | [Zoom VDI user interface shows stale state](07-zoom-vdi-ui-stale.md) | Zoom VDI plugin / Citrix | no, confusing |
| 08 | [Bluetooth call mode: 16 kHz and a 2–4 s switch](08-bluetooth-call-mode.md) | Bluetooth / macOS / headset | no (clarity, not loudness) |
| 09 | [macOS falls back to a virtual device when the headset disconnects](09-macos-fallback-to-virtual-device.md) | macOS | no |
| 10 | [What was ruled out, and what is still open](10-ruled-out-and-open.md) | — | — |
| 11 | [The headset fades words in over about 100 ms](11-jabra-word-start-fade-in.md) | Jabra firmware | contributes: weak sentence starts and short words |
