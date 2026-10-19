; Installer for Cryptmaster Whisper. Built by tools\package.ps1 (which stages the files in dist\stage).
; Ships only what may be redistributed (docs\LICENSING.md): the mod, the Vulkan whisper.cpp build, BepInEx.
; Larger Whisper models and the optional CUDA build are downloaded from their official sources on the
; player's computer, checked against pinned SHA-256 hashes, and never packed in here.
;
; Model benchmark: before choosing models, the installer times the game's own tiny model on the GPU (if any)
; and on the CPU, each with a short and a full encoder window. That separates fixed overhead from compute
; speed, from which the bigger models (same architecture, more compute) are estimated. It recommends the
; largest model that fits the time budget for each device: one for the GPU, and one for the CPU, which the
; mod falls back to whenever the GPU isn't available. After downloading, the chosen models are timed for
; real, and swapped for a smaller one if they turn out too slow.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#define Stage "..\dist\stage"
#define HfRev "5359861c739e955e79d9a303bcbc70fb988958b1"
#define HfBase "https://huggingface.co/ggerganov/whisper.cpp/resolve/" + HfRev + "/"
#define CudaUrl "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-bin-win-cuda-12.4.0-x64.zip"
#define CudaSha "afef0b881c500958921c3f5523b50e59ee2ec9b6f5cbd25b324c51ed308a957a"
#define PluginSub "BepInEx\plugins\CryptmasterWhisper"

[Setup]
AppId={{6F1B2C3D-8E4A-4C7B-9D2E-5A1F0C9B7E21}
AppName=Cryptmaster Whisper
AppVersion={#AppVersion}
AppPublisher=Cryptmaster Whisper contributors
AppComments=Optional Whisper voice recognition for Cryptmaster. Windows Speech Recognition stays the default.
DefaultDirName={code:GetGameDir}
AppendDefaultDirName=no
DirExistsWarning=no
UsePreviousAppDir=yes
DisableProgramGroupPage=yes
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
OutputDir=..\dist
OutputBaseFilename=CryptmasterWhisper-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
LicenseFile=..\LICENSE
InfoBeforeFile=installer-info.txt
UninstallDisplayName=Cryptmaster Whisper

[Messages]
SelectDirLabel3=Setup will install Cryptmaster Whisper into your Cryptmaster game folder (the folder with CryptMaster.exe).

[Types]
Name: "custom"; Description: "Custom"; Flags: iscustom

[Components]
Name: "main"; Description: "Cryptmaster Whisper, with the Vulkan whisper.cpp (GPU: AMD, Intel or NVIDIA; CPU otherwise)"; Types: custom; Flags: fixed
Name: "models"; Description: "Extra Whisper models (downloaded; the game's own tiny models are always available). Recommended ones are ticked from the test of your PC."
Name: "models\base"; Description: "base: 57 MB"; ExtraDiskSpaceRequired: 59707625
Name: "models\small"; Description: "small: 181 MB"; ExtraDiskSpaceRequired: 190085487
Name: "models\turbo"; Description: "large-v3-turbo: 547 MB, the most accurate"; ExtraDiskSpaceRequired: 574041195
Name: "cuda"; Description: "NVIDIA CUDA backend (optional, about 650 MB download; read the next page)"; ExtraDiskSpaceRequired: 1400000000; Check: HasNvidiaGpu

[Files]
Source: "{#Stage}\plugin\*"; DestDir: "{app}\{#PluginSub}"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: main
Source: "{#Stage}\bepinex\BepInEx.zip"; DestDir: "{tmp}"; Flags: deleteafterinstall; Components: main; Check: not BepInExInstalled
; The benchmark (whisper.cpp Vulkan build + cmwbench.exe), extracted to {tmp}\bench while setup runs.
; Same source files as native\vulkan above, so the installer stores them once.
Source: "{#Stage}\plugin\native\vulkan\*.dll"; DestDir: "{tmp}\bench"; Flags: dontcopy
Source: "{#Stage}\bench\cmwbench.exe"; DestDir: "{tmp}\bench"; Flags: dontcopy

[UninstallDelete]
Type: filesandordirs; Name: "{app}\{#PluginSub}"

[Code]
const
  BudgetMs = 300;    // per-word time a model may take to be recommended
  VerifyMaxMs = 500; // after download: slower than this, use the next smaller model
  ModelCount = 4;

var
  CudaPage: TOutputMsgMemoWizardPage;
  BenchPage: TOutputMsgMemoWizardPage;
  DownloadPage: TDownloadWizardPage;
  Benchmarked: Boolean;
  GpuName: String;
  GpuFreeMb: Integer;
  // Per device (0 = GPU, 1 = CPU): estimated per-word ms for each model; -1 = can't run there.
  Estimate: array[0..1] of array[0..3] of Integer;
  GpuPick, CpuPick: Integer;

// ---- Models: 0 tiny (the game's), 1 base, 2 small, 3 turbo ----

function ModelFile(I: Integer): String;
begin
  case I of
    0: Result := 'ggml-tiny.bin';
    1: Result := 'ggml-base-q5_1.bin';
    2: Result := 'ggml-small-q5_1.bin';
  else Result := 'ggml-large-v3-turbo-q5_0.bin';
  end;
end;

function ModelLabel(I: Integer): String;
begin
  case I of
    0: Result := 'tiny (the game''s)';
    1: Result := 'base';
    2: Result := 'small';
  else Result := 'large-v3-turbo';
  end;
end;

function ModelComponent(I: Integer): String;
begin
  case I of
    1: Result := 'models\base';
    2: Result := 'models\small';
    3: Result := 'models\turbo';
  else Result := '';
  end;
end;

// Compute relative to tiny (x100), measured as encoder time ratios on the CPU (where compute dominates).
function ComputeRatio(I: Integer): Integer;
begin
  case I of
    0: Result := 100;
    1: Result := 270;
    2: Result := 1030;
  else Result := 5270;
  end;
end;

// GPU memory a model needs (MB, weights plus working buffers, with margin).
function VramNeedMb(I: Integer): Integer;
begin
  case I of
    0: Result := 200;
    1: Result := 400;
    2: Result := 900;
  else Result := 1600;
  end;
end;

// ---- Finding the game ----

function ExtractQuoted(Line: String; Index: Integer): String;
var
  I, Count, Start: Integer;
begin
  Result := '';
  Count := 0;
  Start := 0;
  for I := 1 to Length(Line) do
    if Line[I] = '"' then
    begin
      Count := Count + 1;
      if Count = Index * 2 - 1 then Start := I + 1
      else if Count = Index * 2 then
      begin
        Result := Copy(Line, Start, I - Start);
        Exit;
      end;
    end;
end;

function IsGameDir(Dir: String): Boolean;
begin
  Result := FileExists(AddBackslash(Dir) + 'CryptMaster.exe');
end;

function GetGameDir(Param: String): String;
var
  Steam, Lib, Candidate: String;
  Lines: TArrayOfString;
  I: Integer;
begin
  Result := ExpandConstant('{commonpf32}\Steam\steamapps\common\Cryptmaster');
  if not RegQueryStringValue(HKCU, 'Software\Valve\Steam', 'SteamPath', Steam) then
    if not RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath', Steam) then Exit;
  StringChangeEx(Steam, '/', '\', True);
  Candidate := AddBackslash(Steam) + 'steamapps\common\Cryptmaster';
  if IsGameDir(Candidate) then begin Result := Candidate; Exit; end;
  // Other Steam library folders.
  if LoadStringsFromFile(AddBackslash(Steam) + 'steamapps\libraryfolders.vdf', Lines) then
    for I := 0 to GetArrayLength(Lines) - 1 do
      if Pos('"path"', Lines[I]) > 0 then
      begin
        Lib := ExtractQuoted(Lines[I], 2);
        StringChangeEx(Lib, '\\', '\', True);
        Candidate := AddBackslash(Lib) + 'steamapps\common\Cryptmaster';
        if IsGameDir(Candidate) then begin Result := Candidate; Exit; end;
      end;
end;

function BepInExInstalled: Boolean;
begin
  Result := FileExists(ExpandConstant('{app}\BepInEx\core\BepInEx.dll'));
end;

// ---- Hardware ----

function HasNvidiaGpu: Boolean;
var
  Locator, Service, Items, Item: Variant;
  Name: String;
  I: Integer;
begin
  Result := False;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Service := Locator.ConnectServer('.', 'root\CIMV2');
    Items := Service.ExecQuery('SELECT Name FROM Win32_VideoController');
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items.ItemIndex(I);
      Name := Item.Name;
      if Pos('NVIDIA', Uppercase(Name)) > 0 then Result := True;
    end;
  except
    Result := False;
  end;
end;

function NeedsVcRuntime: Boolean;
begin
  // whisper.cpp needs the Microsoft Visual C++ 2015-2022 runtime (vcomp140 is its OpenMP part).
  Result := not FileExists(ExpandConstant('{sys}\vcomp140.dll')) or not FileExists(ExpandConstant('{sys}\msvcp140.dll'));
end;

// ---- Benchmark ----

function BenchValue(Lines: TArrayOfString; Key: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(Lines) - 1 do
    if Pos(Key + '=', Lines[I]) = 1 then
    begin
      Result := Copy(Lines[I], Length(Key) + 2, Length(Lines[I]));
      Exit;
    end;
end;

// Runs cmwbench on a model; returns the output lines (empty on failure).
function RunBench(Model, Args: String; var Lines: TArrayOfString): Boolean;
var
  Code: Integer;
  OutFile: String;
begin
  OutFile := ExpandConstant('{tmp}\bench\result.txt');
  DeleteFile(OutFile);
  Result := Exec(ExpandConstant('{cmd}'), '/C ""' + ExpandConstant('{tmp}\bench\cmwbench.exe') + '" "' + Model + '" ' + Args + ' > "' + OutFile + '""',
    ExpandConstant('{tmp}\bench'), SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0) and LoadStringsFromFile(OutFile, Lines);
  if Result then Log('cmwbench ' + Args + ': ' + BenchValue(Lines, 'device') + ', median ' + BenchValue(Lines, 'median_ms') + ' ms, encode ' + BenchValue(Lines, 'encode_ms') + ' ms');
end;

// Estimates every model on one device (0 GPU, 1 CPU) from tiny timed with a short and a full window.
procedure EstimateDevice(Device: Integer; Tiny: String);
var
  Lines: TArrayOfString;
  Flag: String;
  Enc256, Enc1500, Compute, Overhead, Est, I: Integer;
begin
  for I := 0 to ModelCount - 1 do Estimate[Device][I] := -1;
  if Device = 1 then Flag := '--cpu ' else Flag := '';
  if not RunBench(Tiny, Flag + '--ctx 256 --runs 3', Lines) then Exit;
  if Device = 0 then
  begin
    GpuName := BenchValue(Lines, 'device');
    GpuFreeMb := StrToIntDef(BenchValue(Lines, 'vram_free_mb'), 0);
    if GpuName = 'CPU' then begin GpuName := ''; Exit; end; // no usable GPU
  end;
  Enc256 := StrToIntDef(BenchValue(Lines, 'encode_us'), -1);
  if not RunBench(Tiny, Flag + '--ctx 1500 --runs 3', Lines) then Exit;
  Enc1500 := StrToIntDef(BenchValue(Lines, 'encode_us'), -1);
  if (Enc256 <= 0) or (Enc1500 <= 0) then Exit;
  // The part of the short window's time that grows with compute; the rest is fixed overhead.
  Compute := (Enc1500 - Enc256) * 256 div 1244;
  if Compute > Enc256 then Compute := Enc256;
  if Compute < 0 then Compute := 0;
  Overhead := Enc256 - Compute;
  for I := 0 to ModelCount - 1 do
  begin
    Est := Overhead + Compute * ComputeRatio(I) div 100;  // encoder, microseconds
    Estimate[Device][I] := (Est * 11 div 10) div 1000 + 20; // plus decoding a word, ms
    if (Device = 0) and (GpuFreeMb < VramNeedMb(I)) then Estimate[Device][I] := -1;
  end;
end;

function Pick(Device: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to ModelCount - 1 do
    if (Estimate[Device][I] >= 0) and (Estimate[Device][I] <= BudgetMs) then Result := I;
end;

function FormatMs(Ms: Integer): String;
begin
  if Ms < 0 then Result := '-'
  else if Ms < 1000 then Result := '~' + IntToStr(Ms) + ' ms'
  else Result := '~' + IntToStr(Ms div 1000) + '.' + IntToStr((Ms mod 1000) div 100) + ' s';
end;

function PadRight(S: String; N: Integer): String;
begin
  Result := S;
  while Length(Result) < N do Result := Result + ' ';
end;

procedure RunBenchmark(Interactive: Boolean);
var
  Tiny, Report: String;
  Progress: TOutputProgressWizardPage;
  I: Integer;
begin
  if Benchmarked then Exit;
  Benchmarked := True;
  GpuName := '';
  GpuPick := 0;
  CpuPick := 0;
  Tiny := AddBackslash(WizardDirValue) + 'CryptMaster_Data\StreamingAssets\Whisper\ggml-tiny.bin';
  ExtractTemporaryFiles('{tmp}\bench\*');
  if Interactive then
  begin
    Progress := CreateOutputProgressPage('Testing your PC', 'Timing Whisper on your graphics card and on your processor. This takes a few seconds.');
    Progress.Show;
    try
      Progress.SetProgress(1, 3);
      EstimateDevice(0, Tiny);
      Progress.SetProgress(2, 3);
      EstimateDevice(1, Tiny);
      Progress.SetProgress(3, 3);
    finally
      Progress.Hide;
    end;
  end
  else
  begin
    EstimateDevice(0, Tiny);
    EstimateDevice(1, Tiny);
  end;
  if GpuName <> '' then GpuPick := Pick(0);
  CpuPick := Pick(1);

  if GpuName <> '' then Report := 'Graphics card: ' + GpuName + ' (' + IntToStr(GpuFreeMb) + ' MB free)' + #13#10
  else Report := 'No graphics card usable by Whisper was found: recognition will run on the processor.' + #13#10;
  Report := Report + #13#10 + 'Estimated time to recognise one word:' + #13#10 + #13#10 +
    PadRight('', 20) + PadRight('graphics card', 16) + 'processor' + #13#10;
  for I := 0 to ModelCount - 1 do
    Report := Report + PadRight(ModelLabel(I), 20) + PadRight(FormatMs(Estimate[0][I]), 16) + FormatMs(Estimate[1][I]) + #13#10;
  Report := Report + #13#10;
  if GpuName <> '' then
  begin
    Report := Report + 'Recommended for the graphics card: ' + ModelLabel(GpuPick) + '.' + #13#10;
    if CpuPick <> GpuPick then
      Report := Report + 'Recommended for the processor: ' + ModelLabel(CpuPick) + ', used whenever the graphics card isn''t available.' + #13#10
    else
      Report := Report + 'The same model also suits the processor, used whenever the graphics card isn''t available.' + #13#10;
  end
  else
    Report := Report + 'Recommended: ' + ModelLabel(CpuPick) + '.' + #13#10;
  Report := Report + #13#10 + 'These are estimates from a quick test with the game''s own tiny model (a model is recommended when it ' +
    'stays under ' + IntToStr(BudgetMs) + ' ms). The recommended models are ticked on the next page; you can change them. ' +
    'After downloading, the chosen models are timed for real and swapped for a smaller one if they are too slow.';
  BenchPage.RichEditViewer.Text := Report;

  Log(Report);
  if not Interactive then Exit;
  // Tick the recommendations on the components page.
  for I := 1 to ModelCount - 1 do
    WizardSelectComponents('!' + ModelComponent(I));
  if (GpuName <> '') and (GpuPick > 0) then WizardSelectComponents(ModelComponent(GpuPick));
  if CpuPick > 0 then WizardSelectComponents(ModelComponent(CpuPick));
end;

// ---- Pages ----

procedure InitializeWizard;
begin
  BenchPage := CreateOutputMsgMemoPage(wpSelectDir, 'Testing your PC', 'Which Whisper models suit this computer.',
    'Results:', '');
  BenchPage.RichEditViewer.Font.Name := 'Consolas';
  CudaPage := CreateOutputMsgMemoPage(wpSelectComponents,
    'About the CUDA backend', 'You probably don''t need this. Read before continuing.',
    'The CUDA backend is selected. Here is what that means:',
    'WHAT IT IS' + #13#10 +
    'An alternative GPU backend for NVIDIA cards, using NVIDIA CUDA. The standard Vulkan backend is installed anyway and already uses your NVIDIA GPU.' + #13#10#13#10 +
    'HOW IT PERFORMED' + #13#10 +
    'In our extensive test set of exactly one graphics card (an RTX 4070 SUPER), CUDA and Vulkan were about equally fast: both recognised a word in well under 0.1 seconds, with CUDA slightly ahead on the mid-sized models and Vulkan level or ahead on the others. An earlier measurement that made Vulkan look clearly faster was flawed. Neither difference is noticeable while playing.' + #13#10#13#10 +
    'HOW BIG IT IS' + #13#10 +
    'Huge. About 650 MB to download and about 1.3 GB on disk, mostly NVIDIA''s own libraries.' + #13#10#13#10 +
    'WHERE IT COMES FROM' + #13#10 +
    'The official whisper.cpp release on GitHub (ggml-org/whisper.cpp, build b5454), checked against a fixed SHA-256 hash. It contains NVIDIA CUDA runtime files under NVIDIA''s own licence (the CUDA Toolkit EULA). This installer doesn''t contain any NVIDIA files; it downloads them onto your computer only if you keep this option.' + #13#10#13#10 +
    'If unsure, go back and untick it. You can always switch backends later in BepInEx\config\cryptmaster.whisper.cfg (Performance.Backend).');
  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing), 'Downloading the selected files...', nil);
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = BenchPage.ID then RunBenchmark(True);
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = CudaPage.ID) and not WizardIsComponentSelected('cuda');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  I: Integer;
begin
  Result := True;
  if (CurPageID = wpSelectDir) and not IsGameDir(WizardDirValue) then
  begin
    MsgBox('CryptMaster.exe was not found in this folder. Please choose your Cryptmaster game folder.', mbError, MB_OK);
    Result := False;
  end
  else if CurPageID = wpReady then
  begin
    DownloadPage.Clear;
    if WizardIsComponentSelected('models\base') then DownloadPage.Add('{#HfBase}ggml-base-q5_1.bin', 'ggml-base-q5_1.bin', '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898');
    if WizardIsComponentSelected('models\small') then DownloadPage.Add('{#HfBase}ggml-small-q5_1.bin', 'ggml-small-q5_1.bin', 'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb');
    if WizardIsComponentSelected('models\turbo') then DownloadPage.Add('{#HfBase}ggml-large-v3-turbo-q5_0.bin', 'ggml-large-v3-turbo-q5_0.bin', '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2');
    if WizardIsComponentSelected('cuda') then DownloadPage.Add('{#CudaUrl}', 'whisper-cuda.zip', '{#CudaSha}');
    if NeedsVcRuntime then DownloadPage.Add('https://aka.ms/vs/17/release/vc_redist.x64.exe', 'vc_redist.x64.exe', '');
    I := 0;
    if WizardIsComponentSelected('models\base') or WizardIsComponentSelected('models\small') or WizardIsComponentSelected('models\turbo')
      or WizardIsComponentSelected('cuda') or NeedsVcRuntime then
    begin
      DownloadPage.Show;
      try
        try
          DownloadPage.Download;
        except
          if DownloadPage.AbortedByUser then Log('Download aborted by user.')
          else SuppressibleMsgBox(AddPeriod(GetExceptionMessage), mbCriticalError, MB_OK, IDOK);
          Result := False;
        end;
      finally
        DownloadPage.Hide;
      end;
    end;
  end;
end;

// ---- Installing ----

procedure Unzip(Zip, Dest: String);
var
  Code: Integer;
begin
  ForceDirectories(Dest);
  Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath ''' + Zip + ''' -DestinationPath ''' + Dest + ''' -Force"',
    '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

procedure SetConfig(Section, Key, Value: String);
begin
  // BepInEx reads "Key = Value" and "Key=Value" alike; it adds the descriptions on its next start.
  ForceDirectories(ExpandConstant('{app}\BepInEx\config')); // BepInEx creates it only on its first run
  if not SetIniString(Section, Key, Value, ExpandConstant('{app}\BepInEx\config\cryptmaster.whisper.cfg')) then
    Log('Could not write the setting ' + Section + '.' + Key);
end;

function ModelPath(I: Integer): String;
begin
  if I = 0 then Result := ExpandConstant('{app}\CryptMaster_Data\StreamingAssets\Whisper\ggml-tiny.bin')
  else Result := ExpandConstant('{app}\{#PluginSub}\models\') + ModelFile(I);
end;

function Available(I: Integer): Boolean;
begin
  Result := FileExists(ModelPath(I));
end;

// The largest available model at or below Wanted.
function BestAvailable(Wanted: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Wanted do
    if Available(I) then Result := I;
end;

// Times a model for real on one device; returns the per-word ms (median), or -1.
function Verify(I, Device: Integer): Integer;
var
  Lines: TArrayOfString;
  Flag: String;
begin
  Result := -1;
  if Device = 1 then Flag := '--cpu ' else Flag := '';
  if RunBench(ModelPath(I), Flag + '--ctx 256 --runs 3', Lines) then
    Result := StrToIntDef(BenchValue(Lines, 'median_ms'), -1);
end;

// After downloads: the model for one device, checked for real; smaller if too slow.
function SettleModel(Wanted, Device: Integer): Integer;
var
  Ms: Integer;
begin
  Result := BestAvailable(Wanted);
  while Result > 0 do
  begin
    Ms := Verify(Result, Device);
    Log('Verified ' + ModelLabel(Result) + ' on device ' + IntToStr(Device) + ': ' + IntToStr(Ms) + ' ms');
    if (Ms >= 0) and (Ms <= VerifyMaxMs) then Exit;
    Result := BestAvailable(Result - 1);
  end;
end;

function EnglishFile(I: Integer): String;
begin
  // The game's English-only tiny model is better at English than its multilingual tiny.
  if I = 0 then Result := 'ggml-model-whisper-tiny.en-q8_0.bin' else Result := ModelFile(I);
end;

procedure ConfigureModels;
var
  Largest, I, Gpu, Cpu: Integer;
begin
  if not Benchmarked then RunBenchmark(False); // silent installs skip the wizard pages
  Largest := 0;
  for I := 1 to ModelCount - 1 do
    if Available(I) then Largest := I;
  if Largest = 0 then Exit; // only the game's models: the mod's defaults already use them
  // What the benchmark recommended, or (if a bigger model was chosen by hand) the largest downloaded.
  Gpu := GpuPick;
  Cpu := CpuPick;
  if Largest > Gpu then Gpu := Largest;
  if GpuName <> '' then
  begin
    Gpu := SettleModel(Gpu, 0);
    Cpu := SettleModel(Cpu, 1);
    SetConfig('Model', 'English', EnglishFile(Gpu));
    SetConfig('Model', 'Multilingual', ModelFile(Gpu));
  end
  else
  begin
    Cpu := SettleModel(Gpu, 1);
    SetConfig('Model', 'English', EnglishFile(Cpu));
    SetConfig('Model', 'Multilingual', ModelFile(Cpu));
  end;
  SetConfig('Model', 'EnglishCpu', EnglishFile(Cpu));
  SetConfig('Model', 'MultilingualCpu', ModelFile(Cpu));
  Log('Models: GPU ' + ModelLabel(Gpu) + ', CPU ' + ModelLabel(Cpu));
end;

procedure InstallCuda;
var
  Src, Dest: String;
  Find: TFindRec;
begin
  Unzip(ExpandConstant('{tmp}\whisper-cuda.zip'), ExpandConstant('{tmp}\cuda'));
  Dest := ExpandConstant('{app}\{#PluginSub}\native\cuda');
  ForceDirectories(Dest);
  // The DLLs are in a Release subfolder of the archive.
  Src := ExpandConstant('{tmp}\cuda\Release');
  if not DirExists(Src) then Src := ExpandConstant('{tmp}\cuda');
  if FindFirst(Src + '\*.dll', Find) then
    try
      repeat
        if (CompareText(Find.Name, 'llama.dll') <> 0) and (CompareText(Find.Name, 'parakeet.dll') <> 0) and (CompareText(Find.Name, 'SDL2.dll') <> 0) then
          FileCopy(Src + '\' + Find.Name, Dest + '\' + Find.Name, False);
      until not FindNext(Find);
    finally
      FindClose(Find);
    end;
  // The mod's own interface DLL works with the official build of the same version.
  FileCopy(ExpandConstant('{app}\{#PluginSub}\native\vulkan\cmwhisper.dll'), Dest + '\cmwhisper.dll', False);
  SaveStringToFile(Dest + '\README.txt', 'Downloaded by the Cryptmaster Whisper installer from {#CudaUrl}' + #13#10 +
    'Contains NVIDIA CUDA runtime files under NVIDIA''s licence. Delete this folder to remove CUDA; the mod then uses native\vulkan.' + #13#10, False);
  SetConfig('Performance', 'Backend', 'CUDA');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Code, I: Integer;
  Models: String;
begin
  if CurStep <> ssPostInstall then Exit;
  if FileExists(ExpandConstant('{tmp}\BepInEx.zip')) then
    Unzip(ExpandConstant('{tmp}\BepInEx.zip'), ExpandConstant('{app}'));
  if FileExists(ExpandConstant('{tmp}\vc_redist.x64.exe')) then
    Exec(ExpandConstant('{tmp}\vc_redist.x64.exe'), '/install /quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Models := ExpandConstant('{app}\{#PluginSub}\models');
  ForceDirectories(Models);
  for I := 1 to ModelCount - 1 do
    if FileExists(ExpandConstant('{tmp}\') + ModelFile(I)) then
      FileCopy(ExpandConstant('{tmp}\') + ModelFile(I), Models + '\' + ModelFile(I), False);
  ConfigureModels;
  if WizardIsComponentSelected('cuda') and FileExists(ExpandConstant('{tmp}\whisper-cuda.zip')) then
    InstallCuda;
end;
