; Installer for Cryptmaster Whisper. Built by tools\package.ps1 (which stages the files in dist\stage).
; Ships only what may be redistributed (docs\LICENSING.md): the mod, the Vulkan whisper.cpp build, BepInEx.
; Larger Whisper models and the optional CUDA build are downloaded from their official sources on the
; player's computer, checked against pinned SHA-256 hashes, and never packed in here.
;
; Model benchmark: before choosing models, the installer times the game's own tiny model on the GPU (if any)
; and always on the CPU, each with a short and a full encoder window. That separates fixed overhead from
; compute speed, from which the bigger models (same architecture, more compute) are estimated. It
; recommends the largest model that fits the time budget for each device: one for the GPU, and one for the
; CPU, which the mod falls back to whenever the GPU isn't available. After downloading, the chosen models
; are timed for real, and swapped for a smaller one if they turn out too slow. With CUDA present (already
; there, or downloaded now), the GPU model is timed on both CUDA and Vulkan and the faster one is used.
;
; Things already there: model files, a CUDA folder, test recordings and an existing settings file are
; listed on their own page, each with an unticked delete box and a red warning. Nothing that was already
; there is overwritten or deleted unless ticked, existing settings are kept unless the player asks to
; replace them, and the uninstaller removes only what this installer added.

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
Name: "cuda"; Description: "NVIDIA CUDA backend: about 650 MB download, then tested against Vulkan (read the next page)"; ExtraDiskSpaceRequired: 1400000000; Check: CudaOffered

[Files]
; Only the mod's own files: other files already in the folder are left alone.
Source: "{#Stage}\plugin\*"; DestDir: "{app}\{#PluginSub}"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: main
Source: "{#Stage}\bepinex\BepInEx.zip"; DestDir: "{tmp}"; Flags: deleteafterinstall; Components: main; Check: not BepInExInstalled
; The benchmark (whisper.cpp Vulkan build + cmwbench.exe), extracted to {tmp}\bench while setup runs.
; Same source files as native\vulkan above, so the installer stores them once.
Source: "{#Stage}\plugin\native\vulkan\*.dll"; DestDir: "{tmp}\bench"; Flags: dontcopy
Source: "{#Stage}\bench\cmwbench.exe"; DestDir: "{tmp}\bench"; Flags: dontcopy

[Code]
const
  BudgetMs = 300;    // per-word time a model may take to be recommended
  VerifyMaxMs = 500; // after download: slower than this, use the next smaller model
  ModelCount = 4;
  MaxFound = 8;
  // Files this installer added outside [Files] (downloads), for the uninstaller.
  AddedListName = 'added-by-installer.txt';

var
  CudaPage: TOutputMsgMemoWizardPage;
  BenchPage: TOutputMsgMemoWizardPage;
  FoundPage, FoundPage2: TWizardPage;
  DownloadPage: TDownloadWizardPage;
  Benchmarked: Boolean;
  GpuName: String;
  GpuFreeMb: Integer;
  // Per device (0 = GPU, 1 = CPU): estimated per-word ms for each model; -1 = can't run there.
  Estimate: array[0..1] of array[0..3] of Integer;
  GpuPick, CpuPick: Integer;
  // Things already there before this installation.
  FoundCount: Integer;
  FoundPath: array of String;
  FoundIsDir: array of Boolean;
  FoundIsSettings: array of Boolean;
  FoundCaption: array of String;
  FoundWarning: array of String;
  FoundBox: array of TNewCheckBox;
  FoundDetected: Boolean;
  // Results for the finish page.
  Summary: String;
  AddedFiles: TStringList;

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

function ModelSha(I: Integer): String;
begin
  case I of
    1: Result := '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898';
    2: Result := 'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb';
    3: Result := '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2';
  else Result := '';
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

// ---- Paths ----

function GetGameDir(Param: String): String; forward;

// The chosen game folder (before the wizard exists, the detected one).
function GameDir: String;
begin
  if WizardForm = nil then Result := GetGameDir('') else Result := WizardDirValue;
end;

function PluginDir: String;
begin
  Result := AddBackslash(GameDir) + '{#PluginSub}';
end;

function ConfigFile: String;
begin
  Result := AddBackslash(GameDir) + 'BepInEx\config\cryptmaster.whisper.cfg';
end;

function CudaDir: String;
begin
  Result := PluginDir + '\native\cuda';
end;

function CudaPresent: Boolean;
begin
  Result := FileExists(CudaDir + '\ggml-cuda.dll') and FileExists(CudaDir + '\whisper.dll');
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

// Offered for download only on NVIDIA PCs that don't have it already (if it's there, it's tested anyway).
function CudaOffered: Boolean;
begin
  Result := HasNvidiaGpu and not CudaPresent;
end;

function NeedsVcRuntime: Boolean;
begin
  // whisper.cpp needs the Microsoft Visual C++ 2015-2022 runtime (vcomp140 is its OpenMP part).
  Result := not FileExists(ExpandConstant('{sys}\vcomp140.dll')) or not FileExists(ExpandConstant('{sys}\msvcp140.dll'));
end;

// ---- Things already there ----

procedure AddFound(Path: String; IsDir, IsSettings: Boolean; Caption, Warning: String);
begin
  if FoundCount >= MaxFound then Exit;
  FoundPath[FoundCount] := Path;
  FoundIsDir[FoundCount] := IsDir;
  FoundIsSettings[FoundCount] := IsSettings;
  FoundCaption[FoundCount] := Caption;
  FoundWarning[FoundCount] := Warning;
  FoundCount := FoundCount + 1;
end;

function FileMb(Path: String): Integer;
var
  Size: Int64;
begin
  Result := 0;
  if FileSize64(Path, Size) then Result := Size div 1048576;
end;

function CountFiles(Dir, Pattern: String): Integer;
var
  Find: TFindRec;
begin
  Result := 0;
  if FindFirst(AddBackslash(Dir) + Pattern, Find) then
    try
      repeat
        if (Find.Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then Result := Result + 1;
      until not FindNext(Find);
    finally
      FindClose(Find);
    end;
end;

function KnownModel(Name: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 1 to ModelCount - 1 do
    if CompareText(Name, ModelFile(I)) = 0 then Result := I;
end;

const
  Maybe = 'Already here before this installation: maybe a previous install, maybe something else entirely. ';

procedure DetectFound;
var
  Find: TFindRec;
  Known: Integer;
  Note, Sessions: String;
begin
  FoundCount := 0;
  SetArrayLength(FoundPath, MaxFound);
  SetArrayLength(FoundIsDir, MaxFound);
  SetArrayLength(FoundIsSettings, MaxFound);
  SetArrayLength(FoundCaption, MaxFound);
  SetArrayLength(FoundWarning, MaxFound);
  SetArrayLength(FoundBox, MaxFound);
  for Known := 0 to MaxFound - 1 do FoundBox[Known] := nil; // silent installs never build the page: nothing ticked
  // Model files.
  if FindFirst(PluginDir + '\models\*.bin', Find) then
    try
      repeat
        Known := KnownModel(Find.Name);
        if Known > 0 then
        begin
          if GetSHA256OfFile(PluginDir + '\models\' + Find.Name) = ModelSha(Known) then
            Note := 'Same as the official download, so it won''t be downloaded again.'
          else
            Note := 'Differs from the official download; kept as it is unless deleted here.';
        end
        else
          Note := 'Not one of this installer''s downloads: maybe there on purpose.';
        AddFound(PluginDir + '\models\' + Find.Name, False, False,
          'Delete model ' + Find.Name + ' (' + IntToStr(FileMb(PluginDir + '\models\' + Find.Name)) + ' MB)', Maybe + Note);
      until not FindNext(Find);
    finally
      FindClose(Find);
    end;
  // A CUDA backend.
  if DirExists(CudaDir) then
    AddFound(CudaDir, True, False, 'Delete the CUDA backend folder (native\cuda, ' + IntToStr(CountFiles(CudaDir, '*.dll')) + ' DLLs, about 1.3 GB)',
      Maybe + 'If kept, it''s tested against Vulkan and used only if faster.');
  // Test recordings.
  if DirExists(PluginDir + '\recordings') then
  begin
    Sessions := IntToStr(CountFiles(PluginDir + '\recordings', '*')) ;
    AddFound(PluginDir + '\recordings', True, False, 'Delete the test recordings folder (recordings\)',
      Maybe + 'Real people''s voices from test sessions: be sure before deleting.');
  end;
  // Existing settings.
  if FileExists(ConfigFile) then
    AddFound(ConfigFile, False, True, 'Replace my current Whisper settings with this installer''s recommendations',
      'A settings file was already here. Unticked, every setting in it is kept as it is; only missing ones are added.');
  FoundDetected := True;
end;

function MarkedForDeletion(Path: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to FoundCount - 1 do
    if (not FoundIsSettings[I]) and (CompareText(FoundPath[I], Path) = 0) and (FoundBox[I] <> nil) and FoundBox[I].Checked then Result := True;
end;

function ReplaceSettings: Boolean;
var
  I: Integer;
begin
  Result := not FileExists(ConfigFile);
  for I := 0 to FoundCount - 1 do
    if FoundIsSettings[I] and (FoundBox[I] <> nil) and FoundBox[I].Checked then Result := True;
end;

procedure BuildFoundPage;
var
  I, Y: Integer;
  Page: TWizardPage;
  Box: TNewCheckBox;
  Warn: TNewStaticText;
begin
  Y := 0;
  for I := 0 to FoundCount - 1 do
  begin
    // Four per page, so the warnings are never cut off.
    if I < 4 then Page := FoundPage else Page := FoundPage2;
    if I = 4 then Y := 0;
    Box := TNewCheckBox.Create(Page);
    Box.Parent := Page.Surface;
    Box.Top := Y;
    Box.Width := Page.SurfaceWidth;
    Box.Height := ScaleY(17);
    Box.Caption := FoundCaption[I];
    Box.Checked := False;
    FoundBox[I] := Box;
    Warn := TNewStaticText.Create(Page);
    Warn.Parent := Page.Surface;
    Warn.Left := ScaleX(18);
    Warn.Top := Y + ScaleY(18);
    Warn.Width := Page.SurfaceWidth - ScaleX(18);
    Warn.AutoSize := False;
    Warn.WordWrap := True;
    Warn.Height := ScaleY(28);
    Warn.Font.Style := [fsBold];
    Warn.Font.Color := clRed;
    Warn.Caption := FoundWarning[I];
    Y := Y + ScaleY(52);
  end;
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

// Runs a cmwbench.exe (Exe) on a model; returns the output lines.
function RunBenchExe(Exe, Model, Args: String; var Lines: TArrayOfString): Boolean;
var
  Code: Integer;
  OutFile: String;
begin
  OutFile := ExpandConstant('{tmp}\bench-result.txt');
  DeleteFile(OutFile);
  Result := Exec(ExpandConstant('{cmd}'), '/C ""' + Exe + '" "' + Model + '" ' + Args + ' > "' + OutFile + '""',
    ExtractFileDir(Exe), SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0) and LoadStringsFromFile(OutFile, Lines);
  if Result then Log('cmwbench (' + ExtractFileDir(Exe) + ') ' + Args + ': ' + BenchValue(Lines, 'backend') + ' ' + BenchValue(Lines, 'device') +
    ', median ' + BenchValue(Lines, 'median_ms') + ' ms, encode ' + BenchValue(Lines, 'encode_ms') + ' ms')
  else Log('cmwbench failed: ' + Exe + ' ' + Args);
end;

function RunBench(Model, Args: String; var Lines: TArrayOfString): Boolean;
begin
  Result := RunBenchExe(ExpandConstant('{tmp}\bench\cmwbench.exe'), Model, Args, Lines);
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
  if CudaPresent then
    Report := Report + 'A CUDA backend is already installed: it will be tested against Vulkan after installing.' + #13#10;
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
  AddedFiles := TStringList.Create;
  BenchPage := CreateOutputMsgMemoPage(wpSelectDir, 'Testing your PC', 'Which Whisper models suit this computer.', 'Results:', '');
  BenchPage.RichEditViewer.Font.Name := 'Consolas';
  FoundPage := CreateCustomPage(wpSelectComponents, 'Already on this PC',
    'These were already in the mod''s folder before this installation. Nothing here is touched unless you tick it.');
  FoundPage2 := CreateCustomPage(FoundPage.ID, 'Already on this PC (continued)', 'More things that were already here. Same deal: nothing is touched unless ticked.');
  CudaPage := CreateOutputMsgMemoPage(FoundPage2.ID,
    'About the CUDA backend', 'You almost certainly don''t need this. Read before continuing.',
    'The CUDA backend is selected. Here is what that means:',
    'WHAT IT IS' + #13#10 +
    'An alternative GPU backend for NVIDIA cards, using NVIDIA CUDA. The standard Vulkan backend is installed anyway and already uses your NVIDIA GPU.' + #13#10#13#10 +
    'HOW IT PERFORMED' + #13#10 +
    'In our rigorous, peer-reviewed test campaign of exactly one graphics card (an RTX 4070 SUPER, sample size n = 1), CUDA and Vulkan performed very similarly: both recognised a word in well under 0.1 seconds, with CUDA usually ahead by a few milliseconds (32 against 41 ms with the largest model). An earlier measurement that crowned Vulkan the clear winner turned out to be measuring CUDA''s start-up instead. Neither difference is noticeable while playing; a blink takes about 100 times longer.' + #13#10#13#10 +
    'HOW BIG IT IS' + #13#10 +
    'Pretty massive. About 650 MB to download and about 1.3 GB on disk, mostly NVIDIA''s own libraries, to maybe save a few milliseconds you will never notice.' + #13#10#13#10 +
    'WHAT HAPPENS NEXT' + #13#10 +
    'After downloading, it''s timed against Vulkan on your card. It''s only used if it''s actually faster, and if it isn''t, you''ll be offered to delete it straight away.' + #13#10#13#10 +
    'WHERE IT COMES FROM' + #13#10 +
    'The official whisper.cpp release on GitHub (ggml-org/whisper.cpp, build b5454), checked against a fixed SHA-256 hash. It contains NVIDIA CUDA runtime files under NVIDIA''s own licence (the CUDA Toolkit EULA). This installer doesn''t contain any NVIDIA files; it downloads them onto your computer only if you keep this option.' + #13#10#13#10 +
    'If unsure, go back and untick it. You can switch backends later in BepInEx\config\cryptmaster.whisper.cfg (Performance.Backend).');
  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing), 'Downloading the selected files...', nil);
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = BenchPage.ID then RunBenchmark(True)
  else if CurPageID = wpFinished then
    WizardForm.FinishedLabel.Caption := 'Cryptmaster Whisper is installed. Windows Speech Recognition (default; vanilla) stays the default; set Engine = Whisper in BepInEx\config\cryptmaster.whisper.cfg to try Whisper.' + #13#10#13#10 + Summary;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := ((PageID = CudaPage.ID) and not WizardIsComponentSelected('cuda'))
    or ((PageID = FoundPage.ID) and (FoundCount = 0))
    or ((PageID = FoundPage2.ID) and (FoundCount <= 4));
end;

// A model download is needed if selected and not already there (or there but about to be deleted).
function NeedsDownload(I: Integer): Boolean;
var
  Path: String;
begin
  Path := PluginDir + '\models\' + ModelFile(I);
  Result := WizardIsComponentSelected(ModelComponent(I)) and ((not FileExists(Path)) or MarkedForDeletion(Path));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  I: Integer;
  Any: Boolean;
begin
  Result := True;
  if CurPageID = wpSelectDir then
  begin
    if not IsGameDir(WizardDirValue) then
    begin
      MsgBox('CryptMaster.exe was not found in this folder. Please choose your Cryptmaster game folder.', mbError, MB_OK);
      Result := False;
      Exit;
    end;
    DetectFound;
    BuildFoundPage;
  end
  else if CurPageID = wpReady then
  begin
    DownloadPage.Clear;
    Any := False;
    for I := 1 to ModelCount - 1 do
      if NeedsDownload(I) then
      begin
        DownloadPage.Add('{#HfBase}' + ModelFile(I), ModelFile(I), ModelSha(I));
        Any := True;
      end;
    if WizardIsComponentSelected('cuda') then begin DownloadPage.Add('{#CudaUrl}', 'whisper-cuda.zip', '{#CudaSha}'); Any := True; end;
    if NeedsVcRuntime then begin DownloadPage.Add('https://aka.ms/vs/17/release/vc_redist.x64.exe', 'vc_redist.x64.exe', ''); Any := True; end;
    if Any then
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

// Writes a setting, unless the player already had one there and chose to keep their settings.
procedure SetConfig(Section, Key, Value: String);
begin
  ForceDirectories(ExtractFileDir(ConfigFile)); // BepInEx creates it only on its first run
  if (not ReplaceSettings) and (GetIniString(Section, Key, '', ConfigFile) <> '') then
  begin
    Log('Kept existing setting ' + Section + '.' + Key + ' = ' + GetIniString(Section, Key, '', ConfigFile) + ' (wanted ' + Value + ')');
    Exit;
  end;
  if not SetIniString(Section, Key, Value, ConfigFile) then Log('Could not write the setting ' + Section + '.' + Key);
end;

procedure SetMeasurement(Key: String; Ms: Integer);
begin
  ForceDirectories(ExtractFileDir(ConfigFile));
  SetIniString('Benchmark', Key, IntToStr(Ms), ConfigFile);
end;

function ModelPath(I: Integer): String;
begin
  if I = 0 then Result := AddBackslash(WizardDirValue) + 'CryptMaster_Data\StreamingAssets\Whisper\ggml-tiny.bin'
  else Result := PluginDir + '\models\' + ModelFile(I);
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

// Times a model for real on one device with the Vulkan build; returns the per-word ms (median), or -1.
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
function SettleModel(Wanted, Device: Integer; var Ms: Integer): Integer;
begin
  Result := BestAvailable(Wanted);
  Ms := -1;
  while Result >= 0 do
  begin
    Ms := Verify(Result, Device);
    Log('Verified ' + ModelLabel(Result) + ' on device ' + IntToStr(Device) + ': ' + IntToStr(Ms) + ' ms');
    if (Result = 0) or ((Ms >= 0) and (Ms <= VerifyMaxMs)) then Exit;
    Result := BestAvailable(Result - 1);
  end;
end;

function EnglishFile(I: Integer): String;
begin
  // The game's English-only tiny model is better at English than its multilingual tiny.
  if I = 0 then Result := 'ggml-model-whisper-tiny.en-q8_0.bin' else Result := ModelFile(I);
end;

// Times the GPU model on the CUDA build (ours runs from its folder, so its DLLs are found); -1 if it fails.
function TimeCuda(Model: Integer): Integer;
var
  Lines: TArrayOfString;
  Exe: String;
begin
  Result := -1;
  Exe := CudaDir + '\cmwbench-installer-test.exe';
  if not FileCopy(ExpandConstant('{tmp}\bench\cmwbench.exe'), Exe, False) then Exit;
  try
    if RunBenchExe(Exe, ModelPath(Model), '--ctx 256 --runs 3', Lines) and (Pos('CUDA', BenchValue(Lines, 'backend')) = 1) then
      Result := StrToIntDef(BenchValue(Lines, 'median_ms'), -1);
  finally
    DeleteFile(Exe);
  end;
end;

procedure ConfigureModels;
var
  Largest, I, Gpu, Cpu, GpuMs, CpuMs, CudaMs: Integer;
  CudaDownloaded: Boolean;
begin
  if not Benchmarked then RunBenchmark(False); // silent installs skip the wizard pages
  Largest := 0;
  for I := 1 to ModelCount - 1 do
    if Available(I) then Largest := I;
  // What the benchmark recommended, or (if a bigger model was chosen by hand) the largest available.
  Gpu := GpuPick;
  Cpu := CpuPick;
  if Largest > Gpu then Gpu := Largest;
  GpuMs := -1;
  if GpuName <> '' then
  begin
    Gpu := SettleModel(Gpu, 0, GpuMs);
    Cpu := SettleModel(Cpu, 1, CpuMs);
    Summary := 'Graphics card (' + GpuName + '): ' + ModelLabel(Gpu) + ', ' + IntToStr(GpuMs) + ' ms per word with Vulkan.' + #13#10 +
      'Processor (fallback): ' + ModelLabel(Cpu) + ', ' + IntToStr(CpuMs) + ' ms per word.' + #13#10;
  end
  else
  begin
    Cpu := SettleModel(Gpu, 1, CpuMs);
    Gpu := Cpu;
    Summary := 'Processor: ' + ModelLabel(Cpu) + ', ' + IntToStr(CpuMs) + ' ms per word.' + #13#10;
  end;
  // Measurements, shown in the game's Options menu (they describe this PC, not choices, so always written).
  if GpuMs > 0 then SetMeasurement('VulkanGpuMs', GpuMs);
  if CpuMs > 0 then SetMeasurement('CpuMs', CpuMs);
  if Largest > 0 then
  begin
    SetConfig('Model', 'English', EnglishFile(Gpu));
    SetConfig('Model', 'Multilingual', ModelFile(Gpu));
    SetConfig('Model', 'EnglishCpu', EnglishFile(Cpu));
    SetConfig('Model', 'MultilingualCpu', ModelFile(Cpu));
  end;

  // CUDA, if it's here (already, or downloaded now): only used if it's actually faster than Vulkan.
  if (GpuName <> '') and CudaPresent then
  begin
    CudaDownloaded := AddedFiles.IndexOf('native\cuda') >= 0;
    CudaMs := TimeCuda(Gpu);
    if CudaMs < 0 then
      Summary := Summary + 'CUDA: didn''t work on this PC, so Vulkan stays.' + #13#10
    else
      Summary := Summary + 'CUDA: ' + IntToStr(CudaMs) + ' ms per word, against ' + IntToStr(GpuMs) + ' ms with Vulkan.' + #13#10;
    if CudaMs > 0 then SetMeasurement('CudaGpuMs', CudaMs);
    // The backend itself isn't written: Auto (the default) uses CUDA only when these measurements say it's
    // more than 10% faster, and anyone who chose a backend keeps it.
    if (CudaMs >= 0) and (GpuMs > 0) and (CudaMs * 10 < GpuMs * 9) then
      Summary := Summary + 'CUDA is faster here, so Auto uses it. Congratulations on your extra milliseconds.' + #13#10
    else
    begin
      Summary := Summary + 'CUDA isn''t meaningfully faster, so Auto uses Vulkan.' + #13#10;
      if CudaDownloaded and (SuppressibleMsgBox('CUDA wasn''t meaningfully faster than Vulkan on your card (' + IntToStr(CudaMs) + ' ms against ' + IntToStr(GpuMs) +
        ' ms per word). Delete the CUDA files it just downloaded (about 1.3 GB)?', mbConfirmation, MB_YESNO, IDNO) = IDYES) then
      begin
        DelTree(CudaDir, True, True, True);
        AddedFiles.Delete(AddedFiles.IndexOf('native\cuda'));
        Summary := Summary + 'The CUDA files were deleted.' + #13#10;
      end;
    end;
  end;
  Log(Summary);
end;

procedure InstallCuda;
var
  Src, Dest: String;
  Find: TFindRec;
begin
  Unzip(ExpandConstant('{tmp}\whisper-cuda.zip'), ExpandConstant('{tmp}\cuda'));
  Dest := CudaDir;
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
  FileCopy(PluginDir + '\native\vulkan\cmwhisper.dll', Dest + '\cmwhisper.dll', False);
  SaveStringToFile(Dest + '\README.txt', 'Downloaded by the Cryptmaster Whisper installer from {#CudaUrl}' + #13#10 +
    'Contains NVIDIA CUDA runtime files under NVIDIA''s licence. Delete this folder to remove CUDA; the mod then uses native\vulkan.' + #13#10, False);
  AddedFiles.Add('native\cuda');
end;

procedure DeleteMarked;
var
  I: Integer;
begin
  for I := 0 to FoundCount - 1 do
    if (not FoundIsSettings[I]) and (FoundBox[I] <> nil) and FoundBox[I].Checked then
    begin
      Log('Deleting (ticked by the player): ' + FoundPath[I]);
      if FoundIsDir[I] then DelTree(FoundPath[I], True, True, True) else DeleteFile(FoundPath[I]);
    end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Code, I: Integer;
  Models, Src, Dest: String;
begin
  if CurStep = ssInstall then
  begin
    if not FoundDetected then DetectFound; // silent installs: detected, never deleted
    DeleteMarked;
    Exit;
  end;
  if CurStep <> ssPostInstall then Exit;
  if FileExists(ExpandConstant('{tmp}\BepInEx.zip')) then
    Unzip(ExpandConstant('{tmp}\BepInEx.zip'), ExpandConstant('{app}'));
  if FileExists(ExpandConstant('{tmp}\vc_redist.x64.exe')) then
    Exec(ExpandConstant('{tmp}\vc_redist.x64.exe'), '/install /quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Models := PluginDir + '\models';
  ForceDirectories(Models);
  for I := 1 to ModelCount - 1 do
  begin
    Src := ExpandConstant('{tmp}\') + ModelFile(I);
    Dest := Models + '\' + ModelFile(I);
    // Never overwrites a file that was already there (it was kept, so it stays).
    if FileExists(Src) and not FileExists(Dest) then
      if FileCopy(Src, Dest, True) then AddedFiles.Add('models\' + ModelFile(I));
  end;
  if WizardIsComponentSelected('cuda') and FileExists(ExpandConstant('{tmp}\whisper-cuda.zip')) and not DirExists(CudaDir) then
    InstallCuda;
  ConfigureModels;
  // For the uninstaller: what this installation added besides its own [Files] (appended to earlier runs).
  for I := 0 to AddedFiles.Count - 1 do
    SaveStringToFile(PluginDir + '\' + AddedListName, AddedFiles[I] + #13#10, True);
end;

// ---- Uninstalling: only what this installer added ----

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Lines: TArrayOfString;
  I: Integer;
  Plugin, Path: String;
begin
  if CurUninstallStep <> usPostUninstall then Exit;
  Plugin := ExpandConstant('{app}\{#PluginSub}');
  if LoadStringsFromFile(Plugin + '\' + AddedListName, Lines) then
    for I := 0 to GetArrayLength(Lines) - 1 do
    begin
      Path := Plugin + '\' + Trim(Lines[I]);
      if Trim(Lines[I]) = '' then Continue;
      if DirExists(Path) then DelTree(Path, True, True, True) else DeleteFile(Path);
    end;
  DeleteFile(Plugin + '\' + AddedListName);
  // Remove folders only if they're now empty (anything else in them was someone else's).
  RemoveDir(Plugin + '\models');
  RemoveDir(Plugin + '\native\cuda');
  RemoveDir(Plugin + '\native');
  RemoveDir(Plugin + '\textos');
  RemoveDir(Plugin);
end;
