# Cryptmaster - Whisper

A BepInEx 5 mod that lets Cryptmaster's voice input use Whisper, a speech recogniser that ships with the
game but was never used, as an alternative to Windows Speech Recognition. Windows Speech Recognition stays
the default.

Status: early. Recognition runs, but it hasn't been tested with real speech yet, and the Options menu toggle
is still to come (switch with the config for now).

## Install

**Installer** (`CryptmasterWhisper-Setup-<version>.exe`): finds the game through Steam and installs BepInEx
if needed. It tests your graphics card and your processor, recommends a model for each (the processor's is
the fallback when the graphics card isn't available) and downloads them. It double-checks them after
downloading. On NVIDIA PCs it also offers an optional CUDA backend. Everything comes from official sources.

**Manual** (`CryptmasterWhisper-<version>.zip`): with BepInEx 5 (x64) installed, unzip into the game folder.

Then set `Engine = Whisper` in `BepInEx\config\cryptmaster.whisper.cfg`, turn Voice Input on in Options,
and press the Ear button (Ctrl) in game to speak.

Recognition runs on the GPU when there is one (Vulkan: AMD, Intel or NVIDIA), otherwise on the CPU.
`Performance.Backend` chooses: Auto, Vulkan, CUDA, CPU, or Game (the game's own 2023 library).

Building releases: `tools\build-whisper-vulkan.ps1`, then `tools\package.ps1` (needs Inno Setup 6).

The mod uses the models the game already ships (`CryptMaster_Data\StreamingAssets\Whisper`). Other
whisper.cpp models (e.g. `ggml-base.bin`) can go in the plugin's `models` folder and be selected in the
config. Larger models are slower.

The game's language decides Whisper's language, so the mod works with the game's own languages and with
localisation mods. `Model.PerLanguage` can pick a different model per language.

Listening (`Listening.Mode`): **Automatic** (press the Ear button and speak; the end of speech is detected) or
**PushToTalk** (hold the Ear button while speaking; nothing is heard otherwise, good for noisy rooms).

If Whisper misbehaves, set the recogniser back to **Windows** (default; vanilla), the game's own.

Testing: `tests\TEST_SCRIPT.md` with `Testing.RecordSessions = true`, then `tools\replay`.
Publishing: see [docs/LICENSING.md](docs/LICENSING.md) for what may go in the repository and in packages.

## How it works and what was changed

See [docs/FINDINGS.md](docs/FINDINGS.md): how the game's voice input works, why its Whisper integration was
probably left out, measurements, and what this mod does differently.

Every recognised utterance is logged in `BepInEx\LogOutput.log` (`[voice]` lines) for both recognisers,
with timings, so you can compare them on your machine.

## Wording rule

Whisper mode is presented as an alternative, and as an attempt to implement a feature the original game
shipped but never used. It never promises better performance than Windows Speech Recognition.

Licence: GPL-3.0 (see LICENSE).
