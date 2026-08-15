# Audio Architecture

This is the hardest and most important part of the app. Get this right
before touching UI.

## What "low-latency monitoring" actually means

This is **not** record-then-play. Buffering audio through a Dart stream,
even with a small buffer, adds round-trip latency on top of the OS's own
input/output latency — often enough to feel laggy and distracting. What
the product needs is a **direct tap**: audio frames routed from input to
output inside the native audio engine, with Dart only controlling
start/stop and reading levels for the visualizer, not touching the sample
data in the hot path.

Round-trip latency = input latency + processing time + output latency.
Target: keep total round-trip low enough that self-speech doesn't feel
delayed — this needs to be measured on real hardware, not assumed from a
package's marketing number.

## Recommended approach: native tap via platform channel

- **iOS**: `AVAudioEngine` with the input node tapped directly into the
  output node (or a minimal-latency render callback), `AVAudioSession`
  configured for `.playAndRecord` with `.allowBluetooth` /
  `.allowBluetoothA2DP` options and a low-latency I/O buffer duration.
- **Android**: Oboe (or raw AAudio) in exclusive MMAP mode, using the
  `VOICE_COMMUNICATION` or `VOICE_RECOGNITION` input preset to avoid extra
  DSP (AEC/AGC/NS) fighting the passthrough. Route via
  `AudioDeviceCallback`, not the deprecated headset broadcast APIs.
- **Flutter side**: a thin `MethodChannel` to start/stop the native engine
  and configure routing, plus an `EventChannel` (or periodic poll) for
  level metering to drive the subtle waveform visualizer. All actual audio
  processing stays native — never bridge raw PCM frames through Dart in
  the hot path.

This means real platform code (Swift/Kotlin) is required. That's expected
and acceptable per the product brief — prefer a robust native
implementation over a convenient cross-platform package.

## Packages considered, and why they're not the primary path

- `flutter_sound` / `record`: good for file/stream recording, not built
  for sub-frame-buffer passthrough monitoring. Useful later for the
  transcription pipeline, not for the live loop.
- `flutter_soloud`: FFI to the SoLoud C++ engine, capable of real-time DSP
  and lower latency than pure-Dart stream approaches. Worth a timeboxed
  spike as a cross-platform alternative to hand-rolled native code, but
  verify actual round-trip latency with headphones before committing —
  don't take a buffer-size claim as a latency guarantee.
- `audio_io`: a newer stream-based low-latency I/O plugin claiming
  sub-2ms buffers. If it proves genuinely stable on real headphone
  hardware during the Step 3 spike below, it's an acceptable alternative
  to hand-written native code — but confirm on-device, since claimed
  buffer size isn't the same as measured round-trip latency.

Whichever path is chosen, treat it as a spike with a pass/fail latency
test, not an assumption.

## Required behavior

- Detect current audio route (headphones vs. speaker) where the platform
  allows it. If no headphones and safe monitoring can't be guaranteed,
  warn before starting — don't create speaker feedback.
- Handle Bluetooth connect/disconnect mid-session gracefully (pause
  monitoring, notify the user, don't crash).
- Handle audio interruptions (phone call, Siri/Assistant, another app
  taking audio focus) — pause and allow resume where sensible.
- Correct mic permission flow, including recovery after a prior denial
  (deep-link to system settings where the platform requires it).

## Latency test protocol (must run before declaring this feature done)

1. On a real device, real headphones (test both wired and Bluetooth if
   available), start monitoring.
2. Speak a short phrase, note subjectively whether the echo feels
   immediate or delayed.
3. If possible, record externally (e.g. a second phone's camera capturing
   both mouth movement and headphone audio, or a clap test) to get an
   approximate measured round-trip number.
4. Report the actual result — device model, headphone type, and
   subjective + measured latency — in the final report. "It compiled" is
   not a result.
