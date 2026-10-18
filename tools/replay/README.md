# replay

Runs recorded test sessions through Whisper models and scores them, together with what was recognised
live, against `tests\TEST_SCRIPT.md`.

1. Record a session in game with `Testing.RecordSessions = true` (one game run per session).
2. Run, from this folder:

```
dotnet run -c Release -- "<game>\BepInEx\plugins\CryptmasterWhisper\recordings\<run folder>" S1 --models "<model1.bin>,<model2.bin>"
```

Options:

- `--models`: comma-separated model files (default: the game's `ggml-tiny.bin`). They run through the game's own
  `libwhisper.dll` (CPU) with the same parameters as the mod.
- `--cli <whisper-cli.exe>`: use a newer whisper.cpp build instead (e.g. a CUDA or Vulkan build).
- `--audio-ctx <n>`: smallest encoder window, as the mod's `Advanced.MinAudioContext` (default 256).

The report is printed and saved as `replay-<session>.md` in the recordings folder: overall results per
recogniser (correct, wrong word, missed, false activations, time) and every recording with what each one
heard. Recordings are aligned to script lines in order, so skipped lines and retakes are fine.

Comparison is as the game compares: lower case, letters and digits only, accents ignored.
