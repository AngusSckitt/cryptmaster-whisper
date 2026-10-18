# What may be published, and where

The mod is GPL-3.0. Before anything goes into the public repository or a release package, check it here.

| Item | Licence | Repository | Release package |
|---|---|---|---|
| This mod's code, texts, docs, tools | GPL-3.0 | yes | yes |
| BepInEx 5 (for a standalone package) | LGPL-2.1 | no | yes, with its licence file |
| The game's files: `libwhisper.dll`, `com.whisper.unity.dll`, the models in `StreamingAssets\Whisper`, language files | the game's | **no** | **no** (the mod uses them from the player's install) |
| whisper.cpp builds (`whisper.dll`, `ggml*.dll`) | MIT | no (binaries) | yes, with the MIT notice |
| OpenAI Whisper models, incl. ggml conversions (`ggml-base-q5_1.bin`...) | MIT | no (size: GitHub's limit is 100 MB per file) | yes, with the MIT notice, or as a separate download |
| Community fine-tuned models (per language) | varies per model: check each | no | only if its licence allows redistribution |
| NVIDIA CUDA runtime (`cudart`, `cublas`, `cublasLt`, `nvrtc`) | NVIDIA CUDA EULA (proprietary; redistribution of these runtime files allowed under its conditions; read before shipping) | no | only as an optional, separate GPU download with NVIDIA's notice |
| Vulkan builds of whisper.cpp | MIT (the Vulkan loader comes with the GPU driver) | no | yes |
| Test recordings | the people recorded | **never** | **never** |

Notes:

- A standalone package (mod + BepInEx + optional models) is fine, as long as each component ships with its
  licence and the game's own files are never included.
- GPL and proprietary libraries: the mod doesn't link to CUDA; it would load whisper.cpp (MIT), which loads its
  GPU backend. Keeping the CUDA files in a separate optional download keeps the main package clean. Vulkan
  avoids the question entirely, and works on AMD, Intel and NVIDIA.
- If CUDA is ever offered: an installer could download NVIDIA's own component archives
  (`developer.download.nvidia.com/compute/cuda/redist/`, listed with SHA-256 in `redistrib_<version>.json`)
  on the player's machine, after showing NVIDIA's licence. The mod's packages then never contain NVIDIA
  files. Costs: about 470 MB download, a dependency on NVIDIA's URLs (pin versions and checksums), and an
  installer to maintain. Since the Vulkan build is faster on the one NVIDIA card tested, CUDA isn't planned.
- Recordings stay in `BepInEx\plugins\CryptmasterWhisper\recordings\` on the tester's computer and are
  git-ignored here.
