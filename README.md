# Cryptmaster - Whisper

## How this mod was made · Cómo se hizo · Como foi feito

**English**

This mod was entirely vibecoded: it was written by an "AI" (a large language model - LLM). So it may
contain artifacts of the model's coding training material, its behaviour, design flaws and biases.

The model was explicitly instructed, as a hard rule, not to generate any imitation of human content other than
structured code, text, small pieces of replicated interface and machine translation; the replicated
interface and the translations were curated, reviewed and adjusted by the human behind the mod, who also set its direction and rules, made the design decisions and tested it in the game.

### In practice: no AI-generated voices were made or used at any point in developing this mod.

The accuracy tests used recordings of real people who agreed to it: Google's Speech Commands dataset (CC BY 4.0).

There's no way to know whether the model reproduced a piece of code from its training material. If you recognise code here that should be credited or that conflicts with the GPL-3 licence, or you find any other problem, please open an issue: https://github.com/AngusSckitt/cryptmaster-whisper/issues

**Español**

Este mod se hizo por completo con "vibecoding": lo escribió una "IA" (un modelo de lenguaje grande - LLM).
Por eso puede contener artefactos del material de entrenamiento de programación del modelo, de su
comportamiento, de fallos de diseño y de sesgos.

Al modelo se le indicó explícitamente, como regla estricta, que no generara ninguna imitación de contenido
humano aparte de código estructurado, texto, pequeñas piezas de interfaz replicada y traducción automática;
la interfaz replicada y las traducciones fueron seleccionadas, revisadas y ajustadas por la persona detrás del mod, que además marcó su rumbo y sus reglas, tomó las decisiones de diseño y lo probó en el juego.

### En la práctica: no se creó ni se usó ninguna voz generada por IA en ningún momento del desarrollo de este mod.

Las pruebas de precisión usaron grabaciones de personas reales que dieron su consentimiento: el conjunto de datos Speech Commands de Google (CC BY 4.0).

No hay forma de saber si el modelo reprodujo algún fragmento de código de su material de entrenamiento. Si reconoces aquí código que debería tener crédito o que entra en conflicto con la licencia GPL-3, o encuentras cualquier otro problema, abre una incidencia (issue): https://github.com/AngusSckitt/cryptmaster-whisper/issues

**Português**

Este mod foi inteiramente "vibecodado": quem o escreveu foi uma "IA" (um modelo de linguagem grande - LLM).
Por isso, ele pode conter artefatos do material de treinamento de programação do modelo, do comportamento
dele, de falhas de design e de vieses.

O modelo foi instruído explicitamente, como regra rígida, a não gerar nenhuma imitação de conteúdo humano
além de código estruturado, texto, pequenos trechos de interface replicada e tradução automática; a interface
replicada e as traduções foram selecionadas, revisadas e ajustadas pelo humano por trás do mod, que também definiu o rumo e as regras, tomou as decisões de design e testou no jogo.

### Na prática: nenhuma voz gerada por IA foi feita ou usada em nenhum momento do desenvolvimento deste mod.

Os testes de precisão usaram gravações de pessoas reais que consentiram: o conjunto de dados Speech Commands do Google (CC BY 4.0).

Não há como saber se o modelo reproduziu algum trecho de código do material de treinamento. Se você reconhecer aqui um código que deveria ser creditado ou que conflita com a licença GPL-3, ou encontrar qualquer outro problema, abra uma issue: https://github.com/AngusSckitt/cryptmaster-whisper/issues

## What it is

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
