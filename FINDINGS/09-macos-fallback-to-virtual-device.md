# 09 — macOS falls back to a virtual device when the headset disconnects

**Component:** macOS
**Effect:** when the headset disconnects, macOS may switch its default input and output to a BlackHole device; apps
set to "same as system" then play to / record from it until the headset is back.
**Caused the original problem:** no.

## Observed

- Headset into the case: default input → BlackHole 16ch (once) / BlackHole 2ch (once); default output → BlackHole 16ch.
- When the headset came back, macOS switched both back to it by itself.

## Consequences

- A call app on "same as system" output plays into BlackHole: you hear nothing during that time.
- CallLift ignores this automatic switch for its own microphone: it sends silence and shows a red icon instead of
  picking up the fallback device (or the laptop mic), and resumes when the headset is back.

## Status

macOS behaviour with any virtual audio device installed.
