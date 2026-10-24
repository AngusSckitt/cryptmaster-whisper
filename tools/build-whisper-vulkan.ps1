# Builds whisper.cpp with the Vulkan GPU backend (AMD, Intel and NVIDIA; MIT-licensed files only) for the
# mod's release package. CPU code is built for every x64 variant and picked at runtime, so the DLLs run on
# any 64-bit CPU, with or without a Vulkan GPU.
#
# Needs: Visual Studio 2022 C++ build tools, CMake, the Vulkan SDK (winget: Microsoft.VisualStudio.2022.BuildTools,
# Kitware.CMake, KhronosGroup.VulkanSDK), Git.
# Usage: powershell -File tools\build-whisper-vulkan.ps1 [-Version v1.9.5 [-Commit <sha>]] [-Work C:\path\to\workdir]
# The source is pinned by commit (a tag can be moved; a commit ID is a hash of the whole tree): another
# version needs its -Commit, or an entry in $pinned.
# Output: <Work>\out\ (cmwhisper.dll, the mod's shim; whisper.dll, ggml*.dll, LICENSE). The work folder is mapped to a drive letter while
# building, because the shader generator's nested build fails past Windows' 260-character path limit.
param([string]$Version = 'v1.9.5', [string]$Commit = '', [string]$Work = "$env:TEMP\cryptmaster-whisper-build")
$ErrorActionPreference = 'Stop'
$pinned = @{ 'v1.9.5' = 'd1be6fde11ac6e0407606b4e42fe72d34add8037' }
if (-not $Commit) { $Commit = $pinned[$Version] }
if (-not $Commit) { throw "No pinned commit for ${Version}: pass -Commit (git ls-remote https://github.com/ggml-org/whisper.cpp.git refs/tags/$Version^{})." }
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $env:VULKAN_SDK) { $env:VULKAN_SDK = [Environment]::GetEnvironmentVariable('VULKAN_SDK', 'Machine') }
if (-not $env:VULKAN_SDK) { throw 'Vulkan SDK not found (VULKAN_SDK is not set).' }
New-Item -ItemType Directory -Force $Work | Out-Null
$drive = (68..90 | ForEach-Object { [char]$_ + ':' } | Where-Object { -not (Test-Path "$_\") } | Select-Object -Last 1)
subst $drive $Work
try {
    $src = "$drive\src"; $build = "$drive\build"; $out = "$drive\out"
    if (-not (Test-Path $src)) { git clone --depth 1 --branch $Version https://github.com/ggml-org/whisper.cpp.git $src }
    # Also catches a work folder left from another version.
    $head = git -C $src rev-parse HEAD
    if ($head -ne $Commit) { throw "whisper.cpp source is at $head, not the pinned $Commit ($Version). Delete $Work\src to clone again." }
    if (git -C $src status --porcelain --untracked-files=no) { throw "whisper.cpp source in $Work\src has local changes." }
    # The mod's sources are compiled from the work drive too, so source paths baked into the DLLs (error
    # messages) read X:\native\..., not this computer's folders.
    $native = "$drive\native"
    if (Test-Path $native) { Remove-Item -Recurse -Force $native }
    Copy-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'native') $native -Recurse
    if ((Test-Path "$build\CMakeCache.txt") -and -not (Select-String -Path "$build\CMakeCache.txt" -SimpleMatch "CMAKE_HOME_DIRECTORY:INTERNAL=$($native -replace '\\', '/')" -Quiet)) {
        Remove-Item -Recurse -Force $build # configured from another source folder
    }
    cmake -S $native -B $build -DWHISPER_SRC="$src" -G 'Visual Studio 17 2022' -A x64 -DGGML_VULKAN=ON -DGGML_NATIVE=OFF -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON `
        -DBUILD_SHARED_LIBS=ON -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON
    if ($LASTEXITCODE) { throw 'cmake configure failed' }
    cmake --build $build --config Release -j ([Environment]::ProcessorCount)
    if ($LASTEXITCODE) { throw 'cmake build failed' }
    New-Item -ItemType Directory -Force $out | Out-Null
    Copy-Item "$build\bin\Release\*.dll", "$build\bin\Release\whisper-cli.exe", "$build\bin\Release\cmwbench.exe" $out -Force
    Copy-Item "$src\LICENSE" "$out\LICENSE-whisper.cpp.txt" -Force
    # Silero speech detection (MIT, Silero Team): whisper.cpp's repository carries the same file as ggml-org/whisper-vad.
    Copy-Item "$src\models\for-tests-silero-v6.2.0-ggml.bin" "$out\ggml-silero-v6.2.0.bin" -Force
    Get-ChildItem $out | ForEach-Object { '{0,-36} {1,8:N1} MB' -f $_.Name, ($_.Length / 1MB) }
    "Built whisper.cpp $Version (Vulkan) in $Work\out"
}
finally {
    subst $drive /D
}
