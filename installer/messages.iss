; Installer texts in every language (English, Spanish, Brazilian Portuguese). %1, %2... are filled in by the
; code; %n is a line break. Tone: Whisper is an alternative/attempt, never promised to beat Windows Speech
; Recognition; the CUDA page is sarcastic on purpose (sample size n = 1).

[Messages]
english.SelectDirLabel3=Setup will install Cryptmaster Whisper into your Cryptmaster game folder (the folder with CryptMaster.exe).
spanish.SelectDirLabel3=El instalador pondrá Cryptmaster Whisper en la carpeta del juego Cryptmaster (la que contiene CryptMaster.exe).
brazilianportuguese.SelectDirLabel3=O instalador vai colocar o Cryptmaster Whisper na pasta do jogo Cryptmaster (a que contém o CryptMaster.exe).

[CustomMessages]
; ---- Components ----
english.CompMain=Cryptmaster Whisper, with the Vulkan whisper.cpp (GPU: AMD, Intel or NVIDIA; CPU otherwise)
spanish.CompMain=Cryptmaster Whisper, con whisper.cpp para Vulkan (GPU: AMD, Intel o NVIDIA; si no, CPU)
brazilianportuguese.CompMain=Cryptmaster Whisper, com o whisper.cpp para Vulkan (GPU: AMD, Intel ou NVIDIA; senão, CPU)
english.CompModels=Extra Whisper models (downloaded; the game's own tiny models are always available). Recommended ones are ticked from the test of your PC.
spanish.CompModels=Modelos de Whisper adicionales (se descargan; los modelos tiny del propio juego siempre están disponibles). Los recomendados vienen marcados según la prueba de tu ordenador.
brazilianportuguese.CompModels=Modelos do Whisper adicionais (baixados; os modelos tiny do próprio jogo estão sempre disponíveis). Os recomendados já vêm marcados pelo teste do seu computador.
english.CompBase=base: 57 MB
spanish.CompBase=base: 57 MB
brazilianportuguese.CompBase=base: 57 MB
english.CompSmall=small: 181 MB
spanish.CompSmall=small: 181 MB
brazilianportuguese.CompSmall=small: 181 MB
english.CompTurbo=large-v3-turbo: 547 MB, the most accurate
spanish.CompTurbo=large-v3-turbo: 547 MB, el más preciso
brazilianportuguese.CompTurbo=large-v3-turbo: 547 MB, o mais preciso
english.CompCuda=NVIDIA CUDA backend: about 650 MB download, 1.3 GB unpacked on disk, then tested against Vulkan
spanish.CompCuda=Motor NVIDIA CUDA: unos 650 MB de descarga, 1,3 GB descomprimido en disco, y luego se compara con Vulkan
brazilianportuguese.CompCuda=Motor NVIDIA CUDA: cerca de 650 MB de download, 1,3 GB descompactado no disco, depois testado contra o Vulkan
english.CudaNoteLabel=CUDA selected: additional information on the next page.
spanish.CudaNoteLabel=CUDA seleccionado: más información en la página siguiente.
brazilianportuguese.CudaNoteLabel=CUDA selecionado: mais informações na próxima página.

; ---- Folder ----
english.NotGameDir=CryptMaster.exe was not found in this folder. Please choose your Cryptmaster game folder.
spanish.NotGameDir=No se ha encontrado CryptMaster.exe en esta carpeta. Elige la carpeta del juego Cryptmaster.
brazilianportuguese.NotGameDir=O CryptMaster.exe não foi encontrado nesta pasta. Escolha a pasta do jogo Cryptmaster.

; ---- PC test ----
english.ModelTiny=tiny (the game's)
spanish.ModelTiny=tiny (el del juego)
brazilianportuguese.ModelTiny=tiny (o do jogo)
english.BenchProgressTitle=Testing your PC
spanish.BenchProgressTitle=Probando tu ordenador
brazilianportuguese.BenchProgressTitle=Testando o seu computador
english.BenchProgressText=Timing Whisper on your graphics card and on your processor. This takes a few seconds.
spanish.BenchProgressText=Midiendo Whisper en tu tarjeta gráfica y en tu procesador. Tarda unos segundos.
brazilianportuguese.BenchProgressText=Medindo o Whisper na sua placa de vídeo e no seu processador. Leva alguns segundos.
english.BenchPageDesc=Which Whisper models suit this computer.
spanish.BenchPageDesc=Qué modelos de Whisper le van bien a este ordenador.
brazilianportuguese.BenchPageDesc=Quais modelos do Whisper combinam com este computador.
english.BenchPageCaption=Results:
spanish.BenchPageCaption=Resultados:
brazilianportuguese.BenchPageCaption=Resultados:
english.RepGpu=Graphics card: %1 (%2 MB free)
spanish.RepGpu=Tarjeta gráfica: %1 (%2 MB libres)
brazilianportuguese.RepGpu=Placa de vídeo: %1 (%2 MB livres)
english.RepNoGpu=No graphics card usable by Whisper was found: recognition will run on the processor.
spanish.RepNoGpu=No se ha encontrado ninguna tarjeta gráfica que Whisper pueda usar: el reconocimiento funcionará en el procesador.
brazilianportuguese.RepNoGpu=Nenhuma placa de vídeo utilizável pelo Whisper foi encontrada: o reconhecimento vai rodar no processador.
english.RepEstimated=Estimated time to recognise one word:
spanish.RepEstimated=Tiempo estimado para reconocer una palabra:
brazilianportuguese.RepEstimated=Tempo estimado para reconhecer uma palavra:
english.RepColGpu=graphics card
spanish.RepColGpu=tarjeta gráfica
brazilianportuguese.RepColGpu=placa de vídeo
english.RepColCpu=processor
spanish.RepColCpu=procesador
brazilianportuguese.RepColCpu=processador
english.RepRecGpu=Recommended for the graphics card: %1.
spanish.RepRecGpu=Recomendado para la tarjeta gráfica: %1.
brazilianportuguese.RepRecGpu=Recomendado para a placa de vídeo: %1.
english.RepRecCpu=Recommended for the processor: %1, used whenever the graphics card isn't available.
spanish.RepRecCpu=Recomendado para el procesador: %1, que se usa cuando la tarjeta gráfica no está disponible.
brazilianportuguese.RepRecCpu=Recomendado para o processador: %1, usado sempre que a placa de vídeo não estiver disponível.
english.RepSameCpu=The same model also suits the processor, used whenever the graphics card isn't available.
spanish.RepSameCpu=El mismo modelo también le va bien al procesador, que se usa cuando la tarjeta gráfica no está disponible.
brazilianportuguese.RepSameCpu=O mesmo modelo também serve para o processador, usado sempre que a placa de vídeo não estiver disponível.
english.RepRecOnly=Recommended: %1.
spanish.RepRecOnly=Recomendado: %1.
brazilianportuguese.RepRecOnly=Recomendado: %1.
english.RepCudaPresent=A CUDA backend is already installed: it will be tested against Vulkan after installing.
spanish.RepCudaPresent=Ya hay un motor CUDA instalado: se comparará con Vulkan después de instalar.
brazilianportuguese.RepCudaPresent=Já existe um motor CUDA instalado: ele será testado contra o Vulkan depois da instalação.
english.RepFootnote=These are estimates from a quick test with the game's own tiny model (a model is recommended when it stays under %1 ms). The recommended models are ticked on the next page; you can change them. After downloading, the chosen models are timed for real and swapped for a smaller one if they are too slow.
spanish.RepFootnote=Son estimaciones de una prueba rápida con el modelo tiny del propio juego (se recomienda un modelo si se queda por debajo de %1 ms). Los modelos recomendados vienen marcados en la página siguiente; puedes cambiarlos. Después de descargarlos, los modelos elegidos se miden de verdad y se cambian por uno más pequeño si van demasiado lentos.
brazilianportuguese.RepFootnote=São estimativas de um teste rápido com o modelo tiny do próprio jogo (um modelo é recomendado quando fica abaixo de %1 ms). Os modelos recomendados já vêm marcados na próxima página; você pode mudá-los. Depois do download, os modelos escolhidos são medidos de verdade e trocados por um menor se estiverem lentos demais.

; ---- Things already there ----
english.FoundTitle=Already on this PC
spanish.FoundTitle=Ya está en este ordenador
brazilianportuguese.FoundTitle=Já está neste computador
english.FoundDesc=These were already in the mod's folder before this installation. Nothing here is touched unless you tick it.
spanish.FoundDesc=Esto ya estaba en la carpeta del mod antes de esta instalación. No se toca nada de aquí salvo que lo marques.
brazilianportuguese.FoundDesc=Isto já estava na pasta do mod antes desta instalação. Nada aqui é mexido, a menos que você marque.
english.Found2Title=Already on this PC (continued)
spanish.Found2Title=Ya está en este ordenador (continuación)
brazilianportuguese.Found2Title=Já está neste computador (continuação)
english.Found2Desc=More things that were already here. Same deal: nothing is touched unless ticked.
spanish.Found2Desc=Más cosas que ya estaban aquí. Lo mismo: no se toca nada salvo que lo marques.
brazilianportuguese.Found2Desc=Mais coisas que já estavam aqui. Mesmo esquema: nada é mexido, a menos que seja marcado.
english.FoundMaybe=Already here before this installation: maybe a previous install, maybe something else entirely.
spanish.FoundMaybe=Ya estaba aquí antes de esta instalación: quizá de una instalación anterior, quizá por otro motivo.
brazilianportuguese.FoundMaybe=Já estava aqui antes desta instalação: talvez de uma instalação anterior, talvez por outro motivo.
english.FoundSame=Same as the official download, so it won't be downloaded again.
spanish.FoundSame=Igual que la descarga oficial, así que no se volverá a descargar.
brazilianportuguese.FoundSame=Igual ao download oficial, então não será baixado de novo.
english.FoundDiffers=Differs from the official download; kept as it is unless deleted here.
spanish.FoundDiffers=Distinto de la descarga oficial; se queda como está salvo que lo borres aquí.
brazilianportuguese.FoundDiffers=Diferente do download oficial; fica como está, a menos que seja apagado aqui.
english.FoundForeign=Not one of this installer's downloads: maybe there on purpose.
spanish.FoundForeign=No es una de las descargas de este instalador: quizá esté ahí a propósito.
brazilianportuguese.FoundForeign=Não é um dos downloads deste instalador: talvez esteja aí de propósito.
english.FoundDelModel=Delete model %1 (%2 MB)
spanish.FoundDelModel=Borrar el modelo %1 (%2 MB)
brazilianportuguese.FoundDelModel=Apagar o modelo %1 (%2 MB)
english.FoundDelCuda=Delete the CUDA backend folder (native\cuda, %1 DLLs, about 1.3 GB)
spanish.FoundDelCuda=Borrar la carpeta del motor CUDA (native\cuda, %1 DLL, unos 1,3 GB)
brazilianportuguese.FoundDelCuda=Apagar a pasta do motor CUDA (native\cuda, %1 DLLs, cerca de 1,3 GB)
english.FoundCudaNote=If kept, it's tested against Vulkan and used only if faster.
spanish.FoundCudaNote=Si se queda, se compara con Vulkan y solo se usa si es más rápido.
brazilianportuguese.FoundCudaNote=Se ficar, é testado contra o Vulkan e só é usado se for mais rápido.
english.FoundDelRec=Delete the test recordings folder (recordings\)
spanish.FoundDelRec=Borrar la carpeta de grabaciones de prueba (recordings\)
brazilianportuguese.FoundDelRec=Apagar a pasta de gravações de teste (recordings\)
english.FoundRecNote=Real people's voices from test sessions: be sure before deleting.
spanish.FoundRecNote=Voces de personas reales de las sesiones de prueba: asegúrate antes de borrar.
brazilianportuguese.FoundRecNote=Vozes de pessoas reais das sessões de teste: tenha certeza antes de apagar.
english.FoundSettings=Replace my current Whisper settings with this installer's recommendations
spanish.FoundSettings=Sustituir mis ajustes actuales de Whisper por las recomendaciones de este instalador
brazilianportuguese.FoundSettings=Substituir minhas configurações atuais do Whisper pelas recomendações deste instalador
english.FoundSettingsNote=A settings file was already here. Unticked, every setting in it is kept as it is; only missing ones are added.
spanish.FoundSettingsNote=Ya había un archivo de ajustes. Sin marcar, todos sus ajustes se quedan como están; solo se añaden los que falten.
brazilianportuguese.FoundSettingsNote=Já havia um arquivo de configurações. Desmarcado, tudo o que está nele fica como está; só as que faltam são adicionadas.

; ---- CUDA ----
english.CudaTitle=About the CUDA backend
spanish.CudaTitle=Sobre el motor CUDA
brazilianportuguese.CudaTitle=Sobre o motor CUDA
english.CudaDesc=You almost certainly don't need this. Read before continuing.
spanish.CudaDesc=Casi seguro que no lo necesitas. Léelo antes de seguir.
brazilianportuguese.CudaDesc=Quase com certeza você não precisa disto. Leia antes de continuar.
english.CudaCaption=The CUDA backend is selected. Here is what that means:
spanish.CudaCaption=Has seleccionado el motor CUDA. Esto es lo que significa:
brazilianportuguese.CudaCaption=O motor CUDA está selecionado. Veja o que isso significa:
english.CudaBody=WHAT IT IS%nAn alternative GPU backend for NVIDIA cards, using NVIDIA CUDA. The standard Vulkan backend is installed anyway and already uses your NVIDIA GPU.%n%nHOW IT PERFORMED%nIn our rigorous, peer-reviewed test campaign of exactly one graphics card (an RTX 4070 SUPER, sample size n = 1), CUDA and Vulkan performed very similarly: both recognised a word in well under 0.1 seconds, with CUDA usually ahead by a few milliseconds (32 against 41 ms with the largest model). An earlier measurement that crowned Vulkan the clear winner turned out to be measuring CUDA's start-up instead. Neither difference is noticeable while playing; a blink takes about 100 times longer.%n%nHOW BIG IT IS%nPretty massive. About 650 MB to download and about 1.3 GB on disk, mostly NVIDIA's own libraries, to maybe save a few milliseconds you will never notice.%n%nWHAT HAPPENS NEXT%nAfter downloading, it's timed against Vulkan on your card. It's only used if it's actually faster, and if it isn't, you'll be offered to delete it straight away.%n%nWHERE IT COMES FROM%nThe official whisper.cpp release on GitHub (ggml-org/whisper.cpp, build b5454), checked against a fixed SHA-256 hash. It contains NVIDIA CUDA runtime files under NVIDIA's own licence (the CUDA Toolkit EULA). This installer doesn't contain any NVIDIA files; it downloads them onto your computer only if you keep this option.%n%nIf unsure, go back and untick it. You can switch backends later in the game's Options > Voice.
spanish.CudaBody=QUÉ ES%nUn motor de GPU alternativo para tarjetas NVIDIA, que usa NVIDIA CUDA. El motor estándar, Vulkan, se instala de todos modos y ya usa tu GPU NVIDIA.%n%nCÓMO HA IDO%nEn nuestra rigurosa campaña de pruebas, revisada por pares, con exactamente una tarjeta gráfica (una RTX 4070 SUPER, tamaño de muestra n = 1), CUDA y Vulkan dieron resultados muy parecidos: los dos reconocieron una palabra en bastante menos de 0,1 segundos, con CUDA normalmente unos milisegundos por delante (32 frente a 41 ms con el modelo más grande). Una medición anterior que coronó a Vulkan como claro ganador resultó estar midiendo el arranque de CUDA. Ninguna diferencia se nota al jugar; un parpadeo dura unas 100 veces más.%n%nCUÁNTO OCUPA%nUna barbaridad. Unos 650 MB de descarga y unos 1,3 GB en disco, casi todo bibliotecas de la propia NVIDIA, para quizá ahorrar unos milisegundos que nunca vas a notar.%n%nQUÉ PASA DESPUÉS%nTras la descarga, se compara con Vulkan en tu tarjeta. Solo se usa si de verdad es más rápido y, si no lo es, se te ofrecerá borrarlo en ese mismo momento.%n%nDE DÓNDE VIENE%nDe la versión oficial de whisper.cpp en GitHub (ggml-org/whisper.cpp, compilación b5454), comprobada con un hash SHA-256 fijo. Contiene archivos del entorno de ejecución de NVIDIA CUDA con la licencia propia de NVIDIA (el EULA del CUDA Toolkit). Este instalador no contiene ningún archivo de NVIDIA; solo los descarga en tu ordenador si mantienes esta opción.%n%nSi tienes dudas, vuelve atrás y desmárcalo. Puedes cambiar de motor más adelante en Opciones > Voz dentro del juego.
brazilianportuguese.CudaBody=O QUE É%nUm motor de GPU alternativo para placas NVIDIA, que usa o NVIDIA CUDA. O motor padrão, Vulkan, é instalado de qualquer jeito e já usa a sua GPU NVIDIA.%n%nCOMO SE SAIU%nNa nossa rigorosa campanha de testes, revisada por pares, com exatamente uma placa de vídeo (uma RTX 4070 SUPER, tamanho de amostra n = 1), CUDA e Vulkan tiveram desempenho muito parecido: os dois reconheceram uma palavra em bem menos de 0,1 segundo, com o CUDA normalmente alguns milissegundos à frente (32 contra 41 ms com o maior modelo). Uma medição anterior que coroou o Vulkan como vencedor absoluto, na verdade, estava medindo a inicialização do CUDA. Nenhuma diferença dá para perceber jogando; uma piscada dura umas 100 vezes mais.%n%nO TAMANHO%nUm trambolho. Cerca de 650 MB de download e cerca de 1,3 GB no disco, quase tudo bibliotecas da própria NVIDIA, para talvez economizar uns milissegundos que você nunca vai notar.%n%nO QUE ACONTECE DEPOIS%nDepois do download, ele é medido contra o Vulkan na sua placa. Só é usado se for mesmo mais rápido e, se não for, você vai poder apagá-lo na mesma hora.%n%nDE ONDE VEM%nDa versão oficial do whisper.cpp no GitHub (ggml-org/whisper.cpp, compilação b5454), conferida com um hash SHA-256 fixo. Contém arquivos do runtime do NVIDIA CUDA sob a licença da própria NVIDIA (o EULA do CUDA Toolkit). Este instalador não contém nenhum arquivo da NVIDIA; ele só os baixa no seu computador se você mantiver esta opção.%n%nNa dúvida, volte e desmarque. Dá para trocar de motor depois em Opções > Voz, dentro do jogo.

; ---- Downloads ----
english.DownloadDesc=Downloading the selected files...
spanish.DownloadDesc=Descargando los archivos seleccionados...
brazilianportuguese.DownloadDesc=Baixando os arquivos selecionados...

; ---- Finish ----
english.Finished=Cryptmaster Whisper is installed. Vanilla Cryptmaster uses Windows Speech Recognition, which stays the default: switch to Whisper in the game's Options > Voice.
spanish.Finished=Cryptmaster Whisper está instalado. Cryptmaster original usa el Reconocimiento de voz de Windows, que sigue siendo la opción predeterminada: cambia a Whisper en Opciones > Voz dentro del juego.
brazilianportuguese.Finished=O Cryptmaster Whisper está instalado. O Cryptmaster original usa o Reconhecimento de Fala do Windows, que continua sendo o padrão: troque para o Whisper em Opções > Voz, dentro do jogo.
english.FinishLangNote=
spanish.FinishLangNote=
brazilianportuguese.FinishLangNote=Lembrete: o Whisper reconhece português, mas o jogo em si não tem suporte a português. Para a experiência completa, instale também o mod "Cryptmaster - Localização PT-BR".
english.OpenLog=Open the installation log in a text editor
spanish.OpenLog=Abrir el registro de la instalación en un editor de texto
brazilianportuguese.OpenLog=Abrir o registro da instalação num editor de texto
english.PtModOffer=Download and open the latest installer of the "Cryptmaster - Localização PT-BR" mod
spanish.PtModOffer=Descargar y abrir el último instalador del mod "Cryptmaster - Localização PT-BR"
brazilianportuguese.PtModOffer=Baixar e abrir o instalador mais recente do mod "Cryptmaster - Localização PT-BR" (textos e comandos em português)
english.PtModFallback=No installer of the Portuguese localisation could be downloaded right now. Its releases page will open in your browser instead.
spanish.PtModFallback=Ahora mismo no se ha podido descargar el instalador de la localización portuguesa. En su lugar se abrirá su página de versiones en el navegador.
brazilianportuguese.PtModFallback=Não foi possível baixar agora o instalador da Localização PT-BR. A página de versões dele vai abrir no navegador.
english.SumGpu=Graphics card (%1): %2, %3 ms per word with Vulkan.
spanish.SumGpu=Tarjeta gráfica (%1): %2, %3 ms por palabra con Vulkan.
brazilianportuguese.SumGpu=Placa de vídeo (%1): %2, %3 ms por palavra com Vulkan.
english.SumCpuFallback=Processor (fallback): %1, %2 ms per word.
spanish.SumCpuFallback=Procesador (alternativa): %1, %2 ms por palabra.
brazilianportuguese.SumCpuFallback=Processador (alternativa): %1, %2 ms por palavra.
english.SumCpuOnly=Processor: %1, %2 ms per word.
spanish.SumCpuOnly=Procesador: %1, %2 ms por palabra.
brazilianportuguese.SumCpuOnly=Processador: %1, %2 ms por palavra.
english.SumCudaFail=CUDA: didn't work on this PC, so Vulkan stays.
spanish.SumCudaFail=CUDA: no ha funcionado en este ordenador, así que se queda Vulkan.
brazilianportuguese.SumCudaFail=CUDA: não funcionou neste computador, então fica o Vulkan.
english.SumCudaTimes=CUDA: %1 ms per word, against %2 ms with Vulkan.
spanish.SumCudaTimes=CUDA: %1 ms por palabra, frente a %2 ms con Vulkan.
brazilianportuguese.SumCudaTimes=CUDA: %1 ms por palavra, contra %2 ms com Vulkan.
english.SumCudaFaster=CUDA is faster here, so Auto uses it. Congratulations on your extra milliseconds.
spanish.SumCudaFaster=CUDA es más rápido aquí, así que Auto lo usa. Enhorabuena por esos milisegundos extra.
brazilianportuguese.SumCudaFaster=O CUDA é mais rápido aqui, então o Auto vai usá-lo. Parabéns pelos milissegundos a mais.
english.SumCudaNotFaster=CUDA isn't meaningfully faster, so Auto uses Vulkan.
spanish.SumCudaNotFaster=CUDA no es apreciablemente más rápido, así que Auto usa Vulkan.
brazilianportuguese.SumCudaNotFaster=O CUDA não é mais rápido de forma significativa, então o Auto usa o Vulkan.
english.SumCudaDeleted=The CUDA files were deleted.
spanish.SumCudaDeleted=Se han borrado los archivos de CUDA.
brazilianportuguese.SumCudaDeleted=Os arquivos do CUDA foram apagados.
english.AskDeleteCuda=CUDA wasn't meaningfully faster than Vulkan on your card (%1 ms against %2 ms per word). Delete the CUDA files it just downloaded (about 1.3 GB)?
spanish.AskDeleteCuda=CUDA no ha sido apreciablemente más rápido que Vulkan en tu tarjeta (%1 ms frente a %2 ms por palabra). ¿Borrar los archivos de CUDA que se acaban de descargar (unos 1,3 GB)?
brazilianportuguese.AskDeleteCuda=O CUDA não foi mais rápido de forma significativa que o Vulkan na sua placa (%1 ms contra %2 ms por palavra). Apagar os arquivos do CUDA que acabaram de ser baixados (cerca de 1,3 GB)?
