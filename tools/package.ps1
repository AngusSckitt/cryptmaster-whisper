# Builds the release files into dist\:
#   CryptmasterWhisper-Setup-<version>.exe  installer (mod, Vulkan whisper.cpp, BepInEx; optional downloads)
#   CryptmasterWhisper-<version>.zip        manual install: unzip into the game folder (BepInEx 5 needed)
# Only redistributable files go in (docs\LICENSING.md). Run tools\build-whisper-vulkan.ps1 first.
# Usage: powershell -File tools\package.ps1 [-Version 0.1.0] [-NativeDir <build-whisper-vulkan output>]
# Keep this script ASCII-only (Windows PowerShell 5.1 reads BOM-less scripts as ANSI).
param([string]$Version = '0.1.0', [string]$NativeDir = "$env:TEMP\cryptmaster-whisper-build\out")
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'stage'
if (-not (Test-Path "$NativeDir\cmwhisper.dll")) { throw "No Vulkan build in $NativeDir; run tools\build-whisper-vulkan.ps1 first." }
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
$plugin = Join-Path $stage 'plugin'
New-Item -ItemType Directory -Force "$plugin\textos", "$plugin\native\vulkan", "$plugin\models", "$stage\bepinex" | Out-Null

# The mod (built without deploying to the game).
dotnet build "$root\Cryptmaster - Whisper.csproj" -c Release --nologo -v q -p:Version=$Version -p:NativeVulkanDir=$NativeDir | Out-Null
if ($LASTEXITCODE) { throw 'dotnet build failed' }
Copy-Item "$root\bin\Release\netstandard2.1\CryptmasterWhisper.dll" $plugin
Copy-Item "$root\textos\*.txt" "$plugin\textos"
Copy-Item "$root\LICENSE", "$root\THIRD-PARTY-NOTICES.txt", "$root\README.md" $plugin
Get-ChildItem $NativeDir -Filter *.dll | Where-Object Name -ne 'parakeet.dll' | Copy-Item -Destination "$plugin\native\vulkan"
Copy-Item "$NativeDir\LICENSE-whisper.cpp.txt" "$plugin\native\vulkan"
Set-Content "$plugin\models\README.txt" 'Optional extra Whisper models (ggml .bin files). Select them in BepInEx\config\cryptmaster.whisper.cfg (Model section).' -Encoding ASCII

# BepInEx 5, pinned.
$bepinex = 'https://github.com/BepInEx/BepInEx/releases/download/v5.4.23.2/BepInEx_win_x64_5.4.23.2.zip'
Invoke-WebRequest $bepinex -OutFile "$stage\bepinex\BepInEx.zip" -UseBasicParsing

# Manual-install zip: the game-folder layout.
$zipRoot = Join-Path $dist 'zip'
if (Test-Path $zipRoot) { Remove-Item -Recurse -Force $zipRoot }
New-Item -ItemType Directory -Force "$zipRoot\BepInEx\plugins" | Out-Null
Copy-Item $plugin "$zipRoot\BepInEx\plugins\CryptmasterWhisper" -Recurse
$zip = Join-Path $dist "CryptmasterWhisper-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive "$zipRoot\*" $zip
Remove-Item -Recurse -Force $zipRoot

# Installer.
$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 not found (winget install JRSoftware.InnoSetup).' }
& $iscc /Q "/DAppVersion=$Version" "$root\installer\CryptmasterWhisper.iss"
if ($LASTEXITCODE) { throw 'Inno Setup failed' }
Get-ChildItem $dist -File | ForEach-Object { '{0,-44} {1,8:N1} MB' -f $_.Name, ($_.Length / 1MB) }
