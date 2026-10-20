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

## Open questions (to test with real speech)

- How accurate tiny is on the game's words in each language, compared with Windows (the `[voice]` lines in
  `BepInEx\LogOutput.log` log both).
- Whether `MinAudioContext` 256 costs accuracy compared with 768 or 1500.
- Whether `ggml-base.bin` (placed in `models\`) is worth its extra latency.
- Matching recognised text to the closest word the game currently accepts (fuzzy or phonetic), on top of
  the prompt.
