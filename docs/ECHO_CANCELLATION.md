# Echo cancellation: evaluation

**Problem.** With speakers, the microphone hears the game: the Cryptmaster's voice lines, music and
effects. In Voice Activation that can trigger recognition by itself, and in every mode loud game audio
makes the player's words harder to recognise. Today the mod only ignores the microphone while the game's
voice lines play (`AudioManager.talkingSource`) and for 0.5 s after, and recommends headphones.

**The idea.** Echo cancellation subtracts a known signal (what's being played) from the microphone signal.
The canceller learns how the room and speakers change the sound on its way to the microphone (the "echo
path": delay, filtering) and removes that estimate, leaving the player's voice.

## What we have to work with

- **The reference signal is available in-process.** Cryptmaster plays everything through Unity's own audio
  (AudioSources such as `talkingSource`). A component on the AudioListener gets `OnAudioFilterRead`: the
  final mix the game sends to the speakers, on the audio thread, as float samples. No loopback driver is
  needed. It doesn't include other programs (Discord, music players).
- **Delay.** The game's output buffer, the Windows mixer, the device, the air and the microphone's own
  buffer add up to roughly 50–250 ms, and it varies per PC. The canceller has to estimate it.
- **Clock drift.** Speakers and microphone are often different devices with slightly different clocks, so
  the delay slowly drifts. Good cancellers track it; simple ones fall apart within minutes.
- **Speaker distortion** (cheap or loud speakers) is non-linear, and only the better cancellers cope.
- **Double talk:** the player speaking while the game is talking is exactly the case that matters (talking
  over the Cryptmaster). Simple cancellers then cancel the player too.

## Options

| Option | Licence | Quality | Effort | Notes |
|---|---|---|---|---|
| **WebRTC AEC3** (via `webrtc-audio-processing`) | BSD-3 | Best available open source: delay estimation, drift tracking, double-talk handling | Medium–high | What browsers use for video calls. Builds with Meson + MSVC into our shim; ~1–2 MB. Also brings noise suppression, high-pass filter and gain control. |
| **SpeexDSP** echo canceller | BSD-3 | Fair; needs a fairly accurate delay, weak with drift and distortion | Low–medium | Tiny, plain C, easy to build. |
| **Windows Voice Capture DSP** (the OS's own AEC) | part of Windows | Good; cancels *everything* the PC plays, other programs included | Medium | Means capturing the microphone ourselves through Windows (COM, WASAPI) instead of Unity's `Microphone`. No extra files. Windows only (as the game's voice input already is). |
| **Smarter gating** (no cancellation) | ours | Doesn't remove echo; only avoids reacting to it | Low | Use the game's output level (from `OnAudioFilterRead`) to raise the bar while it's loud: speech must be clearly louder than the expected echo. |

## Cost

- AEC3 at 16 kHz: a few percent of one CPU core, on its own thread. The reference has to be downmixed to
  mono and resampled to 16 kHz (cheap).
- Windows' DSP: similar, done by Windows.
- Gating: negligible.

## Recommendation

1. **Now, cheap: smarter gating.** Read the game's output level in `OnAudioFilterRead` and, while the game
   is loud (music, effects, voice), require Silero's speech probability *and* microphone loudness clearly
   above the level the game alone would produce. It extends today's "ignore while the Cryptmaster talks" to
   all game audio, without removing anything.
2. **Next, the real fix: WebRTC AEC3** in the shim, fed with the game's own output as the reference. It's
   the best quality, it's BSD (fine with GPL-3), and it brings noise suppression too, which we can compare
   with RNNoise using the same tests. The cleaned audio then goes to Silero and Whisper as now.
3. **Keep Windows' Voice Capture DSP as the fallback plan** if building AEC3 on Windows proves painful: it
   also covers other programs' sound, at the price of our own microphone capture path.

## Step 1, done (2026-10-22): the echo gate

`GameOutputMonitor` sits on the AudioListener and reads the game's final mix (`OnAudioFilterRead`): a
loudness envelope that rises at once and falls over ~0.3 s (to cover the speaker-to-microphone delay). While
the player isn't speaking (Silero below 0.3), the session learns the **echo ratio**: microphone loudness per
unit of game output. While the game is loud, speech may only *start* if the microphone is at least
`Advanced.EchoMargin` (2×) louder than ratio × output. Once speech has started it isn't cut off, and Push to
Talk isn't gated. With headphones the ratio stays near zero and nothing changes.

Test (clean set; the game's real output mixed into the fake microphone at gain 0.5 with 120 ms delay,
`Testing.FakeEcho`; Voice Activation, Silero, turbo on Vulkan):

| | Correct (of 40) | Missed | False activations (of 10) |
|---|---|---|---|
| No echo | 32 | 0 | 0 |
| Echo, gate off | 24 | 3 | 4 |
| Echo, gate on | 28 | 1 | 0 |

The learnt ratio was 0.34–0.58 (true 0.5). The gate removes the game's sound as a trigger; the remaining
loss (28 against 32) is echo mixed into the player's words, which only real cancellation (step 2) removes.

## How we'd test it

The test harness can simulate echo with real recordings only: capture the game's own output (its voice
lines and music, through `OnAudioFilterRead`), then mix it into the speech clips with a delay and some
filtering, as a room would. Run every mode with and without cancellation, as with the noise tests. A final
check needs real speakers and a real voice, in a quiet and a loud room.
