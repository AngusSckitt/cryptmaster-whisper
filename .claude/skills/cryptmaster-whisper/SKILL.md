---
name: cryptmaster-whisper
description: Use when working on the Cryptmaster Whisper mod (BepInEx plugin replacing Windows Speech Recognition with the game's shipped Whisper as an opt-in alternative) — voice input internals, latency/accuracy tuning, the recogniser option, its texts in every language, and the project's policies.
---

# Cryptmaster Whisper

Read `docs\FINDINGS.md` first: what the game ships, how its voice input works, measurements, and why
Whisper was probably left out.

## Policies (never break)

1. No AI-generated or synthesised voices, not even as recogniser test input: accuracy tests use real
   people's recordings (with consent); timing tests use noise or silence.
2. Windows Speech Recognition (WSR) is the default. Whisper is opt-in.
3. Wording never promises better performance than WSR. It is a disclaimer, not a design limit: build Whisper
   mode as well as possible, then keep the wording accurate.
4. Separate from localisation mods. They never mention Whisper; this mod's texts (`textos\<CODE>.txt`, game
   line format) exist for every language it supports. The project owner reviews them pair by pair.
5. The game survives removal: the recogniser choice lives in `BepInEx\config\cryptmaster.whisper.cfg`.

## Code map

`src\Plugin.cs` (config) · `SpeechPatches.cs` (StartDictationEngine/CloseDictationEngine routing,
`doesSystemSupportSpeech`, WSR comparison log) · `VoiceSession.cs` (microphone, voice activity detection,
previews and final, Ear bar) · `WhisperEngine.cs` (models, `audio_ctx` sizing, publicized native params,
UTF-8 prompt) · `Vocabulary.cs` (prompt words, hallucination filter) · `GameLanguages.cs` (game code →
Whisper code) · `Texts.cs` (injects `textos\` into `allSentenceLookup`/`allOptionsLookup` after
`LoadExternalLang`; replaces existing texts only when that language's file exists).

## Working notes

- Build: `dotnet build` deploys to `BepInEx\plugins\CryptmasterWhisper` (with `textos\` and an empty
  `models\` for user-supplied models). `com.whisper.unity` is publicized: `WhisperParams._param` gives
  `no_timestamps`, `max_tokens`, `temperature_inc` and `initial_prompt`.
- Game entry point for recognised text: `SaveManager.TranslateSpeechText(text, isFinal)`. Ear bar fields:
  `isHighlightingEar`, `startCurrTimeBegin`, `speechLastEndTime`, `speechCurrTime`,
  `MenuManager.speechBarColor` (0.5 idle, 1 pulse).
- Every utterance is logged as `[voice] Whisper ...` or `[voice] Windows ...` in `BepInEx\LogOutput.log`,
  for comparing the two on the player's machine.
- `tools\bench`: timing of the game's DLL and models (noise input). `tools\replay`: scores recorded test
  sessions (`tests\TEST_SCRIPT.md`, `Testing.RecordSessions`) per recogniser/model; recordings never in git.
- Push to talk: `Listening.Mode = PushToTalk`; held state is `rewiredControl.GetButton("hear")` (fallback
  Ctrl). Windows recogniser is labelled "default; vanilla" in every language.
- Before publishing anything, check `docs\LICENSING.md` (never the game's files; CUDA only as an optional
  separate download; models/binaries not in git).
- Native backends: `native\cmwhisper.cpp` (our C shim, built with whisper.cpp by
  `tools\build-whisper-vulkan.ps1`; uses a `subst` drive for the 260-char path limit) → `src\NativeBackend.cs`
  loads `plugin\native\<vulkan|cuda>\cmwhisper.dll` by full path; the shim pre-loads CUDA runtimes from its
  own folder (the game's exe is elsewhere). `Performance.Backend` = Auto/Vulkan/CUDA/CPU/Game; the game's
  library is the fallback. Measure fairly with `tools\bench --native <folder>` (in-process, warm).
- Releases: `tools\package.ps1` → `dist\` installer (Inno Setup, `installer\CryptmasterWhisper.iss`) + zip.
  Downloads (models, CUDA, VC++ runtime) are pinned by URL + SHA-256; CUDA only offered on NVIDIA PCs.
- Installer benchmark: `native\cmwbench.cpp` (encoder-only timing, two window sizes, GPU and always CPU);
  estimates and thresholds in `[Code]` of the .iss (see FINDINGS "Model benchmark"). Every device gets its
  own model: `Model.English/Multilingual` (GPU) and `Model.EnglishCpu/MultilingualCpu` (CPU fallback);
  `WhisperEngine.ModelFor` picks by `OnGpu`, per utterance.
- To do: the Options > Voice row `[SPEECHENGINE]` (clone the `[SPEECHON]` GameOption; labels already in
  `textos\`), fuzzy matching to accepted words, real-speech accuracy tests.
