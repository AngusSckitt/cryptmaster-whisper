# Whisper in Cryptmaster: what the game ships, and why it was likely left out

Investigated on game version 1.118 (decompiled `Assembly-CSharp.dll` and `com.whisper.unity.dll`, plus tests
of the shipped native library). Facts are marked as such; reasons the developers dropped it are
inferences, since nothing in the game states them.

## What ships (facts)

- `CryptMaster_Data\Managed\com.whisper.unity.dll`: the open-source whisper.unity binding (Macoron), with
  a slightly modified `WhisperManager` (extra `talkingSource` fields).
- `CryptMaster_Data\Plugins\x86_64\libwhisper.dll`: whisper.cpp about v1.5.4 (has ggml-backend and grammar
  parameters), built by the developers in Release from their own Visual Studio project
  (`E:\_R_And_D\whisper\...`). It reports `AVX = 1 | AVX2 = 1 | FMA = 1 | F16C = 1 | BLAS = 0 | CUDA = 0`:
  CPU-only, but with the fast instruction sets enabled.
- `CryptMaster_Data\StreamingAssets\Whisper\`: three models. `ggml-tiny.bin` (74 MB, multilingual, f16),
  `ggml-model-whisper-tiny-q5_1.bin` (31 MB, multilingual) and `ggml-model-whisper-tiny.en-q8_0.bin`
  (42 MB, English only).

## How the game uses it (facts)

- The boot scene contains a `WhisperManager` (model `Whisper/ggml-tiny.bin`). `BootStrap.Start()` destroys it
  straight away: `Object.Destroy(Object.FindObjectOfType<WhisperManager>().gameObject)`. Nothing else in
  the game references Whisper.
- Voice input uses `UnityEngine.Windows.Speech.DictationRecognizer` (Windows Speech Recognition, online
  speech must be enabled in Windows) in `SaveManager.StartDictationEngine`. Hypotheses and results go to
  `SaveManager.TranslateSpeechText(text, isFinal)`. That function maps known mishearings
  (`[SPEECHLOOKUP]` lines) and calls `TextManager.UpdateSpeechPrediction`, which types the letters and
  submits. Twitch chat uses the same entry point (`_isTwitch: true`).
- The Ear button (Rewired action `hear`) toggles a session. Sessions use 1.2 s silence timeouts.
- There is also an unused "chatbot" experiment: the `chatbot` event calls `MiniGameManager.StartChatbot`,
  which opens the microphone (`AudioManager.SetupMic`). Holding Space records and plays the clip back, and
  the Cryptmaster's mouth follows the volume. That's likely what the `talkingSource` fields in the modified
  `WhisperManager` were for.
- Consoles show `speechwarningconsole` ("press the Ear button"), but the PC build only contains the Windows
  recogniser.

## Measurements (facts, 4-core i5-6600K, CPU only, the game's own DLL, 4 threads)

| Model | Load | 30 s window (default) | 768 | 256 (~5 s) | 160 (~3 s) |
|---|---|---|---|---|---|
| tiny q5_1 (multilingual) | 91 ms | 862 ms | 325 ms | 103 ms | 68 ms |
| tiny f16 (multilingual) | 134 ms | 867 ms | 304 ms | 101 ms | 73 ms |
| tiny.en q8 | 102 ms | 733 ms | 252 ms | 91 ms | 62 ms |

Time to recognise a 2 s utterance, by encoder window (`audio_ctx`, 50 per second). The input was noise:
timing only. The game was not running, so in-game times will be higher. Reproduce with `tools\bench`.

## Why it was likely dropped (inferences)

1. **Latency with the binding's defaults.** `WhisperManager` uses Whisper's fixed 30 s window, so each
   recognition takes about 0.9 s on a mid-range CPU while the game is also rendering. Its streaming mode
   only processes every 3 s (`stepSec = 3`). Windows Speech Recognition gives live hypotheses within a
   fraction of a second, and the game relies on that for its typed-letter preview.
2. **Accuracy of the tiny models on isolated invented words.** The game is played with single words, many of
   them invented (Joro, akupara, paradiddle). Tiny models do poorly on those and "hear" phrases like
   "Thank you." in silence. The game's `[SPEECHLOOKUP]` list was tuned for Windows' mishearings.
3. **CPU budget and platforms.** Whisper competes with the game for the CPU on every utterance, and the
   game also ships on consoles, where the encoder would be much slower.
4. **It was never wired in.** No code path from the Ear button reaches Whisper. It looks like an experiment
   (possibly together with the chatbot) that was switched off rather than finished.

## What this mod adjusts

- **Encoder window sized to the utterance** (at least `Advanced.MinAudioContext`, default 256): about 0.1 s
  per recognition instead of about 0.9 s.
- **Utterance detection**: the mod records from the Ear button, waits for speech (energy against an
  adaptive noise floor, with 0.25 s of pre-roll) and ends the utterance after 0.6 s of silence, at most 6 s.
  Provisional results every 0.4 s feed the game's live preview, like Windows' hypotheses.
- **Short outputs**: one segment, no timestamps, at most 24 tokens. Previews skip temperature fallback.
- **Vocabulary prompt**: the party's current skill words are passed to Whisper as UTF-8. The binding
  marshals prompts as ANSI, which breaks accented words.
- **Hallucination filter**: drops silence phrases ("thank you", "obrigado"...) unless the game knows the word.
- **Language** from the game's language code (ENG→en with the English-only model; SPA→es, POR→pt and others
  with the multilingual model), so it works with any localisation mod without depending on it.
- **WSR availability**: in Whisper mode voice input is offered wherever there is a microphone, even when
  Windows' online speech is off.

- **Listening modes** (`Listening.Mode`, Whisper only; also Options > Voice > Whisper Listening):
  - *Tap to Toggle* (`Automatic`, the default, like the original game, where Ctrl turns WSR on for a few
    seconds): press the Ear button and speak; the session ends when speech stops.
  - *Push to Talk*: the utterance is exactly what's said while the Ear button is held. Nothing is heard
    otherwise, so noise can't trigger it.
  - *Voice Activation*: always listening while playing (in game, window focused, no menu open, Voice Input
    on), no button. Each detected utterance is recognised on its own. Whisper only runs on speech, so idle
    cost is just reading the microphone, but the Windows microphone indicator stays on. Risks: the game's
    own voice through speakers, other people, noise. Mitigations: the microphone is ignored while the game's
    voice plays (`AudioManager.talkingSource`) and for 0.5 s after; utterances shorter than 0.3 s are
    dropped; previews only after 0.5 s of speech; results with a high no-speech probability or under two
    letters are ignored; headphones recommended in the fine print. Pressing Ear still starts a normal session.
- **Per-language models** (`Model.PerLanguage`, by game language code, e.g. `POR=ggml-small-q5_1.bin`),
  for the game's own languages and any localisation mod's code.
- **Test recording** (`Testing.RecordSessions`): every session as a WAV plus what was recognised, also in
  Windows mode (recorded alongside WSR), replayed offline by `tools\replay` against `tests\TEST_SCRIPT.md`.

## Bigger models and GPUs (facts; same PC with an RTX 4070 SUPER; 2 s noise, greedy, window 256)

| Model (size) | Game's DLL, CPU | whisper.cpp b5454, CPU | whisper.cpp b5454, CUDA |
|---|---|---|---|
| tiny (74 MB, the game's) | ~100 ms | 127 ms | 180 ms |
| base q5_1 (57 MB) | 241 ms | 249 ms | 190 ms |
| small q5_1 (181 MB) | 857 ms | 814 ms | 249 ms |
| large-v3-turbo q5_0 (547 MB) | 4157 ms | 3560 ms | 169 ms |

The b5454 timings are whole command-line runs minus model load, so each includes CUDA start-up; a loaded
model in the mod would be faster. Large-v3-turbo is OpenAI's most recent model; on a GPU it costs about
what tiny costs on a CPU.

- The only language-specific model shipped is `tiny.en` (English). Officially, Whisper's language-specific
  models are English-only (`.en`, up to medium). Spanish and Portuguese only exist in the multilingual
  models, where they are among Whisper's best-supported languages. Community fine-tunes for Portuguese
  and Spanish exist (mostly Hugging Face format, convertible to ggml). They are tuned for general
  dictation, not single invented words, and each has its own licence.
- Expected order of benefit (to be confirmed by replaying recordings): a bigger multilingual model (base on
  CPU, turbo on GPU) first, then matching to accepted words, then fine-tunes.
- Using a GPU requires replacing the game's 2023 library with a current whisper.cpp build plus a new binding
  (its C structs changed). CUDA covers NVIDIA only and its runtime is proprietary (see LICENSING.md).
  Vulkan covers AMD, Intel and NVIDIA with MIT-only files. It has no official Windows build, so
  `tools\build-whisper-vulkan.ps1` builds one (v1.9.5).

The table above measures whole command-line runs, so every GPU figure includes the backend's start-up.
Measured properly (the mod's way: one process, model loaded once, warm, median of 5, `tools\bench --native`):

| Model | Vulkan (our build) | CUDA (official b5454 + our shim) | CPU (our build) |
|---|---|---|---|
| tiny | 53 ms | 63 ms | 148 ms |
| base q5_1 | 63 ms | 27 ms | 189 ms |
| small q5_1 | 47 ms | 21 ms | 648 ms |
| large-v3-turbo q5_0 | 30 ms | 26–33 ms | 3146 ms |

Vulkan and CUDA are about even (an earlier conclusion that Vulkan was clearly faster came from counting
CUDA's start-up). Both are far below what a player notices. Vulkan is the default GPU path: one 43 MB
backend (`ggml-vulkan.dll`) for AMD, Intel and NVIDIA, MIT-only. CUDA is an installer option for NVIDIA
cards (545 MB `ggml-cuda.dll` plus about 470 MB of NVIDIA runtime). Untested on AMD so far; an AMD
tester should run the S1 session with it.

In game: the Vulkan build loads in the game's own process alongside its rendering. large-v3-turbo loaded
in 1.8 s on the RTX 4070 SUPER, and a silent session ended with "no speech heard", with no invented text.

## Model benchmark in the installer

Models can't be timed before they're downloaded (large-v3-turbo is 547 MB), so the installer estimates them.
`native\cmwbench.exe` times the game's own tiny model, encoder only (the same cost whatever the audio says;
decoding noise varies per model). It runs at two window sizes (256 and 1500) on the GPU, if there is one,
and **always on the CPU as well**. The difference between the two sizes is compute; the rest of the short
window's time is fixed overhead. Bigger models are the same architecture with more compute, so:

`estimate = overhead + compute × ratio` (ratio to tiny: base 2.7, small 10.3, turbo 52.7, measured as CPU
encoder ratios), × 1.1, + 20 ms for decoding a word.

Checked on this PC (estimate / real, per word): GPU base 26/33 ms, small 28/18 ms, turbo 34–42/41–42 ms;
CPU base 244/250 ms, small 876/802 ms, turbo 4.4/4.0 s. That's close enough to choose a tier.

The installer recommends the largest model under 300 ms for each device (and GPU memory permitting). The
CPU gets its own recommendation, used as the fallback whenever the GPU isn't available
(`Model.EnglishCpu` / `Model.MultilingualCpu`). Both are ticked for download. After downloading, each chosen
model is timed for real on its device, and swapped for the next smaller available model above 500 ms.

With CUDA present (already there, or downloaded on request), the installer times the GPU model on both
backends with a full word-level run, and uses CUDA only if it's more than 10% faster. On the RTX 4070
SUPER, large-v3-turbo took 32 ms with CUDA against 41 ms with Vulkan, so the installer picked CUDA.
That's a real but unnoticeable difference, and it's why every PC gets tested rather than trusting n = 1.

Anything already in the mod's folder (model files, a CUDA folder, test recordings) and an existing settings
file are listed on their own page, each with an unticked delete box and a red warning that it may be from
a previous install or there for some other reason. Unticked, nothing is overwritten or deleted: identical
models aren't downloaded again, and existing settings are kept (only missing ones are added). The
uninstaller removes only what the installer added (`added-by-installer.txt`) plus its own files.

Note: Inno Setup merges uninstall records across reinstalls with the same AppId. An early test build had a
"delete the whole plugin folder" rule; it never shipped, but a test folder installed with it keeps that rule.

## First real-speech test (2026-10-20)

Recordings of real people from Google's Speech Commands test set (CC BY 4.0, single words: yes, no, up,
down, left, right, on, off, stop, go), fed through `Testing.FakeMicrophone` (the mod's test-only stand-in
for the microphone: everything from speech detection onwards is the real path) inside the running game,
on the RTX 4070 SUPER with large-v3-turbo (Vulkan), language forced to English, vocabulary prompt off.
50 clips: 4 per word from different speakers, plus 10 background-noise clips that should produce nothing.

| Mode | Correct (of 40) | Missed | False activations (of 10 noise clips) | Time per word |
|---|---|---|---|---|
| Voice Activation, before the fix below | 0 | 4 | 0 | ~110–170 ms |
| Voice Activation | 31 | 0 | 1 | ~100–150 ms |
| Tap to Toggle | 32 | 0 | 1 | similar |
| Push to Talk | 32 | 0 | 2 (button held through noise) | similar |

- **Whisper repeats short words** until it runs out of tokens ("Right. Right. Right..."): every result was
  wrong before the fix. Fixed by collapsing repeats (`Vocabulary.CollapseRepeats`) and capping output at
  12 tokens.
- The remaining errors are mostly near-misses on short, noisy crowd-sourced clips: up → cup/ab/tab, on →
  an/honour, left → let/last, off → "ass", no → gnome. Matching to the words the game accepts would fix
  most of them.
- Whisper invents stock phrases in noise ("I'm going to go to the church / the next one"). Results with
  more than 18 letters per second of audio are now dropped; Voice Activation also shows no provisional
  previews, so a made-up phrase can't be typed while it's being recognised.
- The in-game menu rows (recogniser, hardware with measured times, listening mode, fine print for each)
  were checked on screen in Portuguese: the Whisper rows hide and reappear when the recogniser changes,
  and the fine print follows the selection.

## Silero speech detection (2026-10-21)

`Listening.SpeechDetector = Silero` (default when the native build is present): Silero VAD v6.2.0 (MIT,
885 KB, `vad\`), run on the CPU through whisper.cpp's streaming VAD API, in 32 ms windows. It replaces the
loudness detector for when speech starts and stops (start at probability 0.5, continue above 0.35), and a
**speech gate** never sends Whisper audio with less than 0.15 s of detected speech. Final recognition also
gets only the detected speech plus 0.25 s either side (`SpeechOnly`), not the trailing silence.

Hard test set: real recordings only. 18 noise-only clips (2 s each from Speech Commands'
`_background_noise_`: dishes, running tap, exercise bike, white and pink noise, and a man meowing), and 30
speech clips mixed with those noises at about 5 dB signal-to-noise. Voice Activation, turbo on Vulkan:

| Detector | Hard set: correct / wrong / missed (of 30) | Hard set: false activations (of 18) | Clean set: correct (of 40) | Clean set: false activations (of 10) |
|---|---|---|---|---|
| Loudness | 21 / 5 / 4 and 19 / 7 / 4 (two runs) | 3 and 4 | 31 | 1 |
| Silero | 17 / 9 / 4 and 18 / 8 / 4 | **0 and 0** | **32** | **0** |

False activations are the clear win (most came from the man meowing, which loudness takes for speech and
Silero doesn't). Accuracy differences of ±2 are within run-to-run noise (temperature fallback makes
recognition slightly random). The game's own 2023 library has no VAD, so loudness remains its fallback.

## Open questions (to test with real speech)

- How accurate tiny is on the game's words in each language, compared with Windows (the `[voice]` lines in
  `BepInEx\LogOutput.log` log both).
- Whether `MinAudioContext` 256 costs accuracy compared with 768 or 1500.
- Whether `ggml-base.bin` (placed in `models\`) is worth its extra latency.
- Matching recognised text to the closest word the game currently accepts (fuzzy or phonetic), on top of
  the prompt.
