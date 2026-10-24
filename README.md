# Cryptmaster - Whisper

## How this mod was made · Cómo se hizo · Como foi feito

**English**

This mod was entirely vibecoded: it was written by an "AI" (a large language model - LLM). So it may
contain artifacts of the model's coding training material, its behaviour, design flaws and biases.

The model was explicitly instructed, as a hard rule, not to generate any imitation of human content other than
structured code, text, small pieces of replicated interface and machine translation; the replicated
interface and the translations were curated, reviewed and adjusted by the human behind the mod, who also set its direction and rules, made the design decisions and tested it in the game.

### In practice: no AI-generated voices were made or used at any point in developing this mod.

The accuracy tests used recordings of real people who agreed to it: Google's Speech Commands dataset (CC BY 4.0). Kudos to the Meowing Dude. If you know, you know.

There's no way to know whether the model reproduced a piece of code from its training material. If you recognise code here that should be credited or that conflicts with the GPL-3 licence, or you find any other problem, please open an issue: https://github.com/AngusSckitt/cryptmaster-whisper/issues

**Español**

Este mod se hizo por completo con "vibecoding": lo escribió una "IA" (un modelo de lenguaje grande - LLM).
Por eso puede contener artefactos del material de entrenamiento de programación del modelo, de su
comportamiento, de fallos de diseño y de sesgos.

Al modelo se le indicó explícitamente, como regla estricta, que no generara ninguna imitación de contenido
humano aparte de código estructurado, texto, pequeñas piezas de interfaz replicada y traducción automática;
la interfaz replicada y las traducciones fueron seleccionadas, revisadas y ajustadas por la persona detrás del mod, que además marcó su rumbo y sus reglas, tomó las decisiones de diseño y lo probó en el juego.

### En la práctica: no se creó ni se usó ninguna voz generada por IA en ningún momento del desarrollo de este mod.

Las pruebas de precisión usaron grabaciones de personas reales que dieron su consentimiento: el conjunto de datos Speech Commands de Google (CC BY 4.0). Un saludo al maullador. Si sabes, sabes.

No hay forma de saber si el modelo reprodujo algún fragmento de código de su material de entrenamiento. Si reconoces aquí código que debería tener crédito o que entra en conflicto con la licencia GPL-3, o encuentras cualquier otro problema, abre una incidencia (issue): https://github.com/AngusSckitt/cryptmaster-whisper/issues

**Português**

Este mod foi inteiramente "vibecodado": quem o escreveu foi uma "IA" (um modelo de linguagem grande - LLM).
Por isso, ele pode conter artefatos do material de treinamento de programação do modelo, do comportamento
dele, de falhas de design e de vieses.

O modelo foi instruído explicitamente, como regra rígida, a não gerar nenhuma imitação de conteúdo humano
além de código estruturado, texto, pequenos trechos de interface replicada e tradução automática; a interface
replicada e as traduções foram selecionadas, revisadas e ajustadas pelo humano por trás do mod, que também definiu o rumo e as regras, tomou as decisões de design e testou no jogo.

### Na prática: nenhuma voz gerada por IA foi feita ou usada em nenhum momento do desenvolvimento deste mod.

Os testes de precisão usaram gravações de pessoas reais que consentiram: o conjunto de dados Speech Commands do Google (CC BY 4.0). Um salve pro miador. Quem sabe, sabe.

Não há como saber se o modelo reproduziu algum trecho de código do material de treinamento. Se você reconhecer aqui um código que deveria ser creditado ou que conflita com a licença GPL-3, ou encontrar qualquer outro problema, abra uma issue: https://github.com/AngusSckitt/cryptmaster-whisper/issues

## What it is · Qué es · O que é

**English**

A BepInEx 5 mod that lets Cryptmaster's voice input use Whisper, a speech recogniser that ships with the
game but was never used, as an alternative to Windows Speech Recognition. Windows Speech Recognition stays
the default.

Status: early release. The Options > Voice menu rows (recogniser, hardware and listening mode) are in place.
Recognition has been tested with recordings of real people and will also be tested by the author playing the
game. Feedback is welcome.

**Español**

Un mod de BepInEx 5 que permite que la entrada de voz de Cryptmaster use Whisper, un reconocedor de voz que
viene con el juego pero que nunca se llegó a usar, como alternativa al Reconocimiento de voz de Windows. El
Reconocimiento de voz de Windows sigue siendo la opción predeterminada.

Estado: versión inicial. Las filas del menú Opciones > Voz (reconocedor, hardware y modo de escucha) ya están
listas. El reconocimiento se ha probado con grabaciones de personas reales y el autor también lo probará
jugando al juego. Se agradecen los comentarios.

**Português**

Um mod de BepInEx 5 que permite que a entrada de voz do Cryptmaster use o Whisper, um reconhecedor de fala
que vem com o jogo mas nunca foi usado, como alternativa ao Reconhecimento de Fala do Windows. O
Reconhecimento de Fala do Windows continua sendo o padrão.

Status: versão inicial. As linhas do menu Opções > Voz (reconhecedor, hardware e modo de escuta) já estão
prontas. O reconhecimento foi testado com gravações de pessoas reais e também vai ser testado pelo autor
jogando o jogo. Feedback é bem-vindo.

## For players · Para jugadores · Para jogadores

**English**

**Installer** (`CryptmasterWhisper-Setup-<version>.exe`): finds the game through Steam and installs BepInEx
if needed. It tests your graphics card and your processor, recommends a model for each (the processor's is
the fallback when the graphics card isn't available) and downloads them. It double-checks them after
downloading. On NVIDIA PCs it also offers an optional CUDA backend. Everything comes from official sources.

**Manual** (`CryptmasterWhisper-<version>.zip`): with BepInEx 5 (x64) installed, unzip into the game folder.

Then choose Whisper in Options > Voice (or set `Engine = Whisper` in `BepInEx\config\cryptmaster.whisper.cfg`),
turn Voice Input on in Options, and press the Ear button (Ctrl) in game to speak.

Recognition runs on the GPU when there is one (Vulkan: AMD, Intel or NVIDIA), otherwise on the CPU.
`Performance.Backend` chooses: Auto, Vulkan, CUDA, CPU, or Game (the game's own 2023 library).

The mod uses the models the game already ships (`CryptMaster_Data\StreamingAssets\Whisper`). Other
whisper.cpp models (e.g. `ggml-base.bin`) can go in the plugin's `models` folder and be selected in the
config. Larger models are slower.

The game's language decides Whisper's language, so the mod works with the game's own languages and with
localisation mods. `Model.PerLanguage` can pick a different model per language.

Listening (`Listening.Mode`): **Automatic** (press the Ear button and speak; the end of speech is detected) or
**PushToTalk** (hold the Ear button while speaking; nothing is heard otherwise, good for noisy rooms).

If Whisper misbehaves, set the recogniser back to **Windows** (default; vanilla), the game's own.

**Español**

**Instalador** (`CryptmasterWhisper-Setup-<version>.exe`): encuentra el juego a través de Steam e instala
BepInEx si hace falta. Prueba tu tarjeta gráfica y tu procesador, recomienda un modelo para cada uno (el del
procesador es el de reserva cuando la tarjeta gráfica no está disponible) y los descarga. Después de
descargarlos, los vuelve a comprobar. En ordenadores con NVIDIA también ofrece un backend CUDA opcional. Todo
viene de fuentes oficiales.

**Manual** (`CryptmasterWhisper-<version>.zip`): con BepInEx 5 (x64) instalado, descomprímelo en la carpeta
del juego.

Después, elige Whisper en Opciones > Voz (o pon `Engine = Whisper` en `BepInEx\config\cryptmaster.whisper.cfg`),
activa la entrada de voz en Opciones y pulsa el botón de la oreja (Ctrl) en el juego para hablar.

El reconocimiento se ejecuta en la GPU si hay una (Vulkan: AMD, Intel o NVIDIA); si no, en la CPU.
`Performance.Backend` permite elegir: Auto, Vulkan, CUDA, CPU o Game (la propia biblioteca del juego, de 2023).

El mod usa los modelos que el juego ya incluye (`CryptMaster_Data\StreamingAssets\Whisper`). Otros modelos
de whisper.cpp (p. ej., `ggml-base.bin`) se pueden poner en la carpeta `models` del plugin y seleccionar en
la configuración. Los modelos más grandes son más lentos.

El idioma del juego determina el idioma de Whisper, así que el mod funciona con los idiomas propios del juego
y con mods de localización. `Model.PerLanguage` permite elegir un modelo distinto para cada idioma.

Escucha (`Listening.Mode`): **Automatic** (pulsa el botón de la oreja y habla; se detecta el final del habla)
o **PushToTalk** (mantén pulsado el botón de la oreja mientras hablas; si no, no se oye nada; útil en
habitaciones ruidosas).

Si Whisper da problemas, vuelve a poner el reconocedor en **Windows** (predeterminado; el original), el
propio del juego.

**Português**

**Instalador** (`CryptmasterWhisper-Setup-<version>.exe`): encontra o jogo pela Steam e instala o BepInEx se
for preciso. Ele testa sua placa de vídeo e seu processador, recomenda um modelo para cada um (o do
processador é o reserva quando a placa de vídeo não está disponível) e baixa os dois. Depois de baixar, ele
confere os arquivos de novo. Em computadores com NVIDIA, também oferece um backend CUDA opcional. Tudo vem de
fontes oficiais.

**Manual** (`CryptmasterWhisper-<version>.zip`): com o BepInEx 5 (x64) instalado, descompacte na pasta do
jogo.

Depois, escolha o Whisper em Opções > Voz (ou defina `Engine = Whisper` em `BepInEx\config\cryptmaster.whisper.cfg`),
ative a entrada de voz em Opções e aperte o botão da Orelha (Ctrl) no jogo para falar.

O reconhecimento roda na GPU quando há uma (Vulkan: AMD, Intel ou NVIDIA); caso contrário, na CPU.
`Performance.Backend` escolhe: Auto, Vulkan, CUDA, CPU ou Game (a biblioteca do próprio jogo, de 2023).

O mod usa os modelos que já vêm com o jogo (`CryptMaster_Data\StreamingAssets\Whisper`). Outros modelos do
whisper.cpp (por exemplo, `ggml-base.bin`) podem ir na pasta `models` do plugin e ser selecionados na
configuração. Modelos maiores são mais lentos.

O idioma do jogo define o idioma do Whisper, então o mod funciona com os idiomas do próprio jogo e com mods
de localização. `Model.PerLanguage` permite escolher um modelo diferente para cada idioma.

Escuta (`Listening.Mode`): **Automatic** (aperte o botão da Orelha e fale; o fim da fala é detectado) ou
**PushToTalk** (segure o botão da Orelha enquanto fala; fora isso, nada é ouvido; bom para ambientes
barulhentos).

Se o Whisper der problema, volte o reconhecedor para **Windows** (padrão; o original), o do próprio jogo.

## How it works and what was changed · Cómo funciona y qué se cambió · Como funciona e o que foi mudado

**English**

See [docs/FINDINGS.md](docs/FINDINGS.md): how the game's voice input works, why its Whisper integration was
probably left out, measurements, and what this mod does differently.

Every recognised utterance is logged in `BepInEx\LogOutput.log` (`[voice]` lines) for both recognisers,
with timings, so you can compare them on your machine.

**Español**

Consulta [docs/FINDINGS.md](docs/FINDINGS.md): cómo funciona la entrada de voz del juego, por qué
probablemente se dejó fuera su integración con Whisper, mediciones y qué hace este mod de forma distinta.

Cada frase reconocida se registra en `BepInEx\LogOutput.log` (líneas `[voice]`) con ambos reconocedores, con
tiempos, para que puedas compararlos en tu ordenador.

**Português**

Veja [docs/FINDINGS.md](docs/FINDINGS.md): como funciona a entrada de voz do jogo, por que a integração dele
com o Whisper provavelmente ficou de fora, medições e o que este mod faz de diferente.

Cada fala reconhecida é registrada em `BepInEx\LogOutput.log` (linhas `[voice]`) nos dois reconhecedores, com
os tempos, para você poder compará-los no seu computador.

## For developers · Para desarrolladores · Para desenvolvedores

**English**

Building releases: `tools\build-whisper-vulkan.ps1`, then `tools\package.ps1` (needs Inno Setup 6).

Testing: `tests\TEST_SCRIPT.md` with `Testing.RecordSessions = true`, then `tools\replay`.
Publishing: see [docs/LICENSING.md](docs/LICENSING.md) for what may go in the repository and in packages.

**Español**

Compilar versiones: `tools\build-whisper-vulkan.ps1` y luego `tools\package.ps1` (requiere Inno Setup 6).

Pruebas: `tests\TEST_SCRIPT.md` con `Testing.RecordSessions = true` y luego `tools\replay`.
Publicación: consulta [docs/LICENSING.md](docs/LICENSING.md) para saber qué puede ir en el repositorio y en
los paquetes.

**Português**

Gerar versões: `tools\build-whisper-vulkan.ps1` e depois `tools\package.ps1` (precisa do Inno Setup 6).

Testes: `tests\TEST_SCRIPT.md` com `Testing.RecordSessions = true` e depois `tools\replay`.
Publicação: veja [docs/LICENSING.md](docs/LICENSING.md) para saber o que pode ir no repositório e nos pacotes.

## Licence · Licencia · Licença

**English**

GPL-3.0 (see LICENSE).

**Español**

GPL-3.0 (consulta LICENSE).

**Português**

GPL-3.0 (veja LICENSE).

## Support · Apoyo · Apoio

> ☕ **Enjoying it?** It's free and always will be. If you'd like to say thanks with something more than
> words, you can [buy me a coffee](https://buymeacoffee.com/angussckitt).
>
> **¿Te gusta?** Es gratis y siempre lo será. Si quieres dar las gracias con algo más que palabras, puedes
> [invitarme a un café](https://buymeacoffee.com/angussckitt).
>
> **Curtiu?** É de graça e sempre vai ser. Se quiser agradecer com algo além de palavras, você pode
> [me pagar um café](https://buymeacoffee.com/angussckitt).
>
> [![Buy Me a Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-support-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/angussckitt)
>
> **Binance Pay:** *coming soon · próximamente · em breve* <!-- TODO: Binance Pay ID / link -->
