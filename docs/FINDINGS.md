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

- **Push to talk** (`Listening.Mode = PushToTalk`, Whisper only): the utterance is exactly what's said while
  the Ear button is held. Nothing is heard otherwise, so noise can't trigger it.
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

Vulkan build (v1.9.5, same PC, same test): tiny 90 ms, base 112 ms, small 139 ms, large-v3-turbo 134 ms,
all on the RTX 4070 SUPER. That's faster than CUDA here, from a 43 MB GPU backend (`ggml-vulkan.dll`)
against 545 MB for `ggml-cuda.dll` plus about 470 MB of NVIDIA runtime. Vulkan is the GPU path. It is
untested on AMD so far; an AMD tester should run the S1 session with it.

## Open questions (to test with real speech)

- How accurate tiny is on the game's words in each language, compared with Windows (the `[voice]` lines in
  `BepInEx\LogOutput.log` log both).
- Whether `MinAudioContext` 256 costs accuracy compared with 768 or 1500.
- Whether `ggml-base.bin` (placed in `models\`) is worth its extra latency.
- Matching recognised text to the closest word the game currently accepts (fuzzy or phonetic), on top of
  the prompt.
