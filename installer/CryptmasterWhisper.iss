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
UninstallDisplayName=Cryptmaster Whisper
; Inno's own detailed log (copied into the mod's logs folder at the end, next to the event log).
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"; InfoBeforeFile: "installer-info.txt"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"; InfoBeforeFile: "installer-info-spa.txt"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"; InfoBeforeFile: "installer-info-por.txt"

#include "messages.iss"

[Types]
Name: "custom"; Description: "Custom"; Flags: iscustom

[Components]
Name: "main"; Description: "{cm:CompMain}"; Types: custom; Flags: fixed
Name: "models"; Description: "{cm:CompModels}"
Name: "models\base"; Description: "{cm:CompBase}"; ExtraDiskSpaceRequired: 59707625
Name: "models\small"; Description: "{cm:CompSmall}"; ExtraDiskSpaceRequired: 190085487
Name: "models\turbo"; Description: "{cm:CompTurbo}"; ExtraDiskSpaceRequired: 574041195
Name: "cuda"; Description: "{cm:CompCuda}"; ExtraDiskSpaceRequired: 1400000000; Check: CudaOffered

[Files]
; Only the mod's own files: other files already in the folder are left alone.
Source: "{#Stage}\plugin\*"; DestDir: "{app}\{#PluginSub}"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: main
Source: "{#Stage}\bepinex\BepInEx.zip"; DestDir: "{tmp}"; Flags: deleteafterinstall; Components: main; Check: not BepInExInstalled
; The benchmark (whisper.cpp Vulkan build + cmwbench.exe), extracted to {tmp}\bench while setup runs.
; Same source files as native\vulkan above, so the installer stores them once.
Source: "{#Stage}\plugin\native\vulkan\*.dll"; DestDir: "{tmp}\bench"; Flags: dontcopy
Source: "{#Stage}\bench\cmwbench.exe"; DestDir: "{tmp}\bench"; Flags: dontcopy

[Run]
; Finish page: open this installation's event log in the default text editor.
Filename: "{code:EventLogPath}"; Description: "{cm:OpenLog}"; Flags: postinstall shellexec skipifsilent unchecked; Check: EventLogExists

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
  // Shown under the components list while CUDA is ticked.
  CudaNote: TNewStaticText;
  // Results for the finish page.
  Summary: String;
  AddedFiles: TStringList;

// ---- Texts (installer\messages.iss) ----

function Msg(Key: String): String;
begin
  Result := CustomMessage(Key);
  StringChangeEx(Result, '%n', #13#10, True);
end;

// %1, %2... (FmtMessage can't take an open array passed through from here).
function Fmt(Key: String; Args: array of String): String;
var
  I: Integer;
begin
  Result := Msg(Key);
  for I := GetArrayLength(Args) - 1 downto 0 do
    StringChangeEx(Result, '%' + IntToStr(I + 1), Args[I], True);
end;

// ---- Event log: shown live on the installing page and written to the mod's logs folder as it happens ----

var
  EventLines: TStringList;   // everything so far (kept until the mod folder exists, then written)
  EventLogFile: String;      // '' until the mod folder exists
  LiveLog: TNewMemo;

procedure EventLog(S: String);
var
  Line: String;
begin
  Log(S);
  // Every entry is stamped with the date and time to the millisecond; lines of a multi-line entry are
  // indented under its stamp.
  Line := GetDateTimeString('yyyy-mm-dd hh:nn:ss.zzz', '-', ':') + '  ' + S;
  StringChangeEx(Line, #13#10, #13#10 + '                         ', True);
  if EventLines = nil then EventLines := TStringList.Create;
  EventLines.Add(Line);
  if EventLogFile <> '' then SaveStringToFile(EventLogFile, Line + #13#10, True);
  if LiveLog <> nil then
  begin
    LiveLog.Lines.Add(Line);
    LiveLog.SelStart := Length(LiveLog.Text); // keep the newest line in view
  end;
end;

function EventLogPath(Param: String): String;
begin
  Result := EventLogFile;
end;

function EventLogExists: Boolean;
begin
  Result := (EventLogFile <> '') and FileExists(EventLogFile);
end;

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
    0: Result := Msg('ModelTiny');
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
            Note := Msg('FoundSame')
          else
            Note := Msg('FoundDiffers');
        end
        else
          Note := Msg('FoundForeign');
        AddFound(PluginDir + '\models\' + Find.Name, False, False,
          Fmt('FoundDelModel', [Find.Name, IntToStr(FileMb(PluginDir + '\models\' + Find.Name))]), Msg('FoundMaybe') + ' ' + Note);
      until not FindNext(Find);
    finally
      FindClose(Find);
    end;
  // A CUDA backend.
  if DirExists(CudaDir) then
    AddFound(CudaDir, True, False, Fmt('FoundDelCuda', [IntToStr(CountFiles(CudaDir, '*.dll'))]),
      Msg('FoundMaybe') + ' ' + Msg('FoundCudaNote'));
  // Test recordings.
  if DirExists(PluginDir + '\recordings') then
  begin
    Sessions := IntToStr(CountFiles(PluginDir + '\recordings', '*')) ;
    AddFound(PluginDir + '\recordings', True, False, Msg('FoundDelRec'),
      Msg('FoundMaybe') + ' ' + Msg('FoundRecNote'));
  end;
  // Existing settings.
  if FileExists(ConfigFile) then
    AddFound(ConfigFile, False, True, Msg('FoundSettings'), Msg('FoundSettingsNote'));
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
  if Result then EventLog('cmwbench (' + ExtractFileDir(Exe) + ') ' + Args + ': ' + BenchValue(Lines, 'backend') + ' ' + BenchValue(Lines, 'device') +
    ', median ' + BenchValue(Lines, 'median_ms') + ' ms, encode ' + BenchValue(Lines, 'encode_ms') + ' ms')
  else EventLog('cmwbench failed: ' + Exe + ' ' + Args);
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
    Progress := CreateOutputProgressPage(Msg('BenchProgressTitle'), Msg('BenchProgressText'));
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

  if GpuName <> '' then Report := Fmt('RepGpu', [GpuName, IntToStr(GpuFreeMb)]) + #13#10
  else Report := Msg('RepNoGpu') + #13#10;
  Report := Report + #13#10 + Msg('RepEstimated') + #13#10 + #13#10 +
    PadRight('', 20) + PadRight(Msg('RepColGpu'), 16) + Msg('RepColCpu') + #13#10;
  for I := 0 to ModelCount - 1 do
    Report := Report + PadRight(ModelLabel(I), 20) + PadRight(FormatMs(Estimate[0][I]), 16) + FormatMs(Estimate[1][I]) + #13#10;
  Report := Report + #13#10;
  if GpuName <> '' then
  begin
    Report := Report + Fmt('RepRecGpu', [ModelLabel(GpuPick)]) + #13#10;
    if CpuPick <> GpuPick then
      Report := Report + Fmt('RepRecCpu', [ModelLabel(CpuPick)]) + #13#10
    else
      Report := Report + Msg('RepSameCpu') + #13#10;
  end
  else
    Report := Report + Fmt('RepRecOnly', [ModelLabel(CpuPick)]) + #13#10;
  if CudaPresent then
    Report := Report + Msg('RepCudaPresent') + #13#10;
  Report := Report + #13#10 + Fmt('RepFootnote', [IntToStr(BudgetMs)]);
  BenchPage.RichEditViewer.Text := Report;
  EventLog(Report);
  if not Interactive then Exit;
  // Tick the recommendations on the components page.
  for I := 1 to ModelCount - 1 do
    WizardSelectComponents('!' + ModelComponent(I));
  if (GpuName <> '') and (GpuPick > 0) then WizardSelectComponents(ModelComponent(GpuPick));
  if CpuPick > 0 then WizardSelectComponents(ModelComponent(CpuPick));
end;

// ---- Pages ----

procedure CreateCudaNote; forward;

procedure InitializeWizard;
begin
  AddedFiles := TStringList.Create;
  BenchPage := CreateOutputMsgMemoPage(wpSelectDir, Msg('BenchProgressTitle'), Msg('BenchPageDesc'), Msg('BenchPageCaption'), '');
  BenchPage.RichEditViewer.Font.Name := 'Consolas';
  FoundPage := CreateCustomPage(wpSelectComponents, Msg('FoundTitle'), Msg('FoundDesc'));
  FoundPage2 := CreateCustomPage(FoundPage.ID, Msg('Found2Title'), Msg('Found2Desc'));
  CudaPage := CreateOutputMsgMemoPage(FoundPage2.ID, Msg('CudaTitle'), Msg('CudaDesc'), Msg('CudaCaption'), Msg('CudaBody'));
  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing), Msg('DownloadDesc'), nil);
  CreateCudaNote;
  // The installing page: a live view of the event log under the progress bar.
  LiveLog := TNewMemo.Create(WizardForm);
  LiveLog.Parent := WizardForm.InstallingPage;
  LiveLog.Left := WizardForm.ProgressGauge.Left;
  LiveLog.Width := WizardForm.ProgressGauge.Width;
  LiveLog.Top := WizardForm.ProgressGauge.Top + WizardForm.ProgressGauge.Height + ScaleY(12);
  LiveLog.Height := WizardForm.InstallingPage.ClientHeight - LiveLog.Top - ScaleY(4);
  LiveLog.ReadOnly := True;
  LiveLog.ScrollBars := ssVertical;
  LiveLog.WordWrap := True;
  LiveLog.Font.Name := 'Consolas';
  LiveLog.Font.Size := 8;
  EventLog('Setup started: Cryptmaster Whisper {#AppVersion}, language ' + ActiveLanguage + ', ' + GetWindowsVersionString + '.');
end;

procedure UpdateCudaNote(Sender: TObject);
begin
  CudaNote.Visible := WizardIsComponentSelected('cuda');
end;

procedure CreateCudaNote;
var
  List: TNewCheckListBox;
begin
  List := WizardForm.ComponentsList;
  CudaNote := TNewStaticText.Create(WizardForm);
  CudaNote.Parent := List.Parent;
  CudaNote.Caption := Msg('CudaNoteLabel');
  CudaNote.Font.Style := [fsBold];
  CudaNote.Left := List.Left;
  CudaNote.Width := List.Width;
  // Make room under the list.
  List.Height := List.Height - ScaleY(20);
  CudaNote.Top := List.Top + List.Height + ScaleY(4);
  CudaNote.Visible := False;
  List.OnClickCheck := @UpdateCudaNote;
end;

// ---- The Portuguese localisation (a separate mod): offered on the Portuguese installer's finish page ----

const
  PtRepo = 'AngusSckitt/cryptmaster-localizacao-ptbr';

var
  PtModBox: TNewCheckBox;

function PtModInstalled: Boolean;
begin
  Result := FileExists(AddBackslash(GameDir) + 'BepInEx\plugins\CryptmasterLocalizacaoPTBR\CryptmasterLocalizacaoPTBR.dll');
end;

procedure ShowPtModOffer;
begin
  // Interactive installs only: a silent install never downloads or launches anything unasked.
  if WizardSilent or (ActiveLanguage <> 'brazilianportuguese') or PtModInstalled or (PtModBox <> nil) then Exit;
  PtModBox := TNewCheckBox.Create(WizardForm);
  PtModBox.Parent := WizardForm.FinishedPage;
  PtModBox.Left := WizardForm.FinishedLabel.Left;
  PtModBox.Width := WizardForm.FinishedLabel.Width;
  PtModBox.Height := ScaleY(34);
  // Under the "open the log" checkbox, if it's there; otherwise at the bottom of the page.
  if WizardForm.RunList.Visible then
    PtModBox.Top := WizardForm.RunList.Top + WizardForm.RunList.Height + ScaleY(6)
  else
    PtModBox.Top := WizardForm.FinishedPage.ClientHeight - ScaleY(44);
  PtModBox.Caption := Msg('PtModOffer');
  PtModBox.Checked := True;
end;

// The latest release's installer (an .exe asset) from the PT mod's GitHub repository; '' if none.
function LatestPtInstallerUrl: String;
var
  Json: AnsiString;
  S: String;
  P, E: Integer;
begin
  Result := '';
  try
    DownloadTemporaryFile('https://api.github.com/repos/' + PtRepo + '/releases/latest', 'pt-latest.json', '', nil);
    if not LoadStringFromFile(ExpandConstant('{tmp}\pt-latest.json'), Json) then Exit;
    S := String(Json);
    // Each asset has "browser_download_url":"https://github.com/<repo>/releases/download/<tag>/<file>".
    repeat
      P := Pos('"browser_download_url":"', S);
      if P = 0 then Exit;
      S := Copy(S, P + 24, Length(S));
      E := Pos('"', S);
      if (E > 0) and (Pos('https://github.com/' + PtRepo + '/releases/download/', Copy(S, 1, E - 1)) = 1)
        and (CompareText(Copy(S, E - 4, 4), '.exe') = 0) then
      begin
        Result := Copy(S, 1, E - 1);
        Exit;
      end;
    until False;
  except
    EventLog('PT mod release lookup failed: ' + GetExceptionMessage);
  end;
end;

procedure RunPtModOffer;
var
  Url: String;
  Code: Integer;
begin
  if PtModBox = nil then Exit;
  if not PtModBox.Checked then
  begin
    EventLog('Portuguese localisation offer: declined.');
    Exit;
  end;
  EventLog('Portuguese localisation offer: accepted; looking for its latest installer...');
  Url := LatestPtInstallerUrl;
  if Url <> '' then
    try
      EventLog('Downloading ' + Url);
      DownloadTemporaryFile(Url, 'pt-installer.exe', '', nil);
      // Copied out of {tmp}, which this installer deletes when it closes.
      FileCopy(ExpandConstant('{tmp}\pt-installer.exe'), ExpandConstant('{%TEMP}\CryptmasterLocalizacaoPTBR-Setup.exe'), False);
      if ShellExec('', ExpandConstant('{%TEMP}\CryptmasterLocalizacaoPTBR-Setup.exe'), '', '', SW_SHOWNORMAL, ewNoWait, Code) then
      begin
        EventLog('Portuguese localisation installer started.');
        Exit;
      end;
    except
      EventLog('PT mod installer download failed: ' + GetExceptionMessage);
    end;
  // No installer release yet (or no connection): the releases page instead.
  EventLog('No Portuguese localisation installer available: opening its releases page instead.');
  SuppressibleMsgBox(Msg('PtModFallback'), mbInformation, MB_OK, IDOK);
  ShellExec('open', 'https://github.com/' + PtRepo + '/releases/latest', '', '', SW_SHOWNORMAL, ewNoWait, Code);
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpSelectComponents then UpdateCudaNote(nil)
  // Inno calls this in silent installs too: there, nothing is ticked on the player's behalf.
  else if CurPageID = BenchPage.ID then RunBenchmark(not WizardSilent)
  else if CurPageID = wpFinished then
  begin
    WizardForm.FinishedLabel.Caption := Msg('Finished') + #13#10#13#10 + Summary;
    if Msg('FinishLangNote') <> '' then
      WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + #13#10 + Msg('FinishLangNote');
    // The label keeps its original height unless told otherwise: grow it to fit the summary, and move
    // the checkboxes below it.
    WizardForm.FinishedLabel.AdjustHeight;
    WizardForm.RunList.Top := WizardForm.FinishedLabel.Top + WizardForm.FinishedLabel.Height + ScaleY(8);
    ShowPtModOffer;
  end;
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
      MsgBox(Msg('NotGameDir'), mbError, MB_OK);
      Result := False;
      Exit;
    end;
    EventLog('Game folder: ' + WizardDirValue);
    DetectFound;
    BuildFoundPage;
    if FoundCount = 0 then EventLog('Nothing of the mod''s was already there.');
    for I := 0 to FoundCount - 1 do
      EventLog('Already there: ' + FoundPath[I]);
  end
  else if CurPageID = wpSelectComponents then
    EventLog('Components chosen: ' + WizardSelectedComponents(False))
  else if CurPageID = wpReady then
  begin
    DownloadPage.Clear;
    Any := False;
    for I := 1 to ModelCount - 1 do
      if NeedsDownload(I) then
      begin
        DownloadPage.Add('{#HfBase}' + ModelFile(I), ModelFile(I), ModelSha(I));
        EventLog('To download: ' + ModelFile(I) + ' (SHA-256 checked)');
        Any := True;
      end
      else if WizardIsComponentSelected(ModelComponent(I)) then
        EventLog('Not downloading ' + ModelFile(I) + ': already there.');
    if WizardIsComponentSelected('cuda') then
    begin
      DownloadPage.Add('{#CudaUrl}', 'whisper-cuda.zip', '{#CudaSha}');
      EventLog('To download: the CUDA backend from {#CudaUrl} (SHA-256 checked)');
      Any := True;
    end;
    if NeedsVcRuntime then
    begin
      DownloadPage.Add('https://aka.ms/vs/17/release/vc_redist.x64.exe', 'vc_redist.x64.exe', '');
      EventLog('To download: the Microsoft Visual C++ runtime (it''s missing)');
      Any := True;
    end;
    if Any then
    begin
      DownloadPage.Show;
      try
        try
          DownloadPage.Download;
          EventLog('Downloads finished; every checksum matched.');
        except
          if DownloadPage.AbortedByUser then EventLog('Download aborted by user.')
          else
          begin
            EventLog('Download failed: ' + GetExceptionMessage);
            SuppressibleMsgBox(AddPeriod(GetExceptionMessage), mbCriticalError, MB_OK, IDOK);
          end;
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
    EventLog('Kept existing setting ' + Section + '.' + Key + ' = ' + GetIniString(Section, Key, '', ConfigFile) + ' (wanted ' + Value + ')');
    Exit;
  end;
  if SetIniString(Section, Key, Value, ConfigFile) then EventLog('Setting written: ' + Section + '.' + Key + ' = ' + Value)
  else EventLog('Could not write the setting ' + Section + '.' + Key);
end;

procedure SetMeasurement(Key: String; Ms: Integer);
begin
  ForceDirectories(ExtractFileDir(ConfigFile));
  SetIniString('Benchmark', Key, IntToStr(Ms), ConfigFile);
  EventLog('Measurement recorded: Benchmark.' + Key + ' = ' + IntToStr(Ms) + ' ms');
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
    EventLog('Verified ' + ModelLabel(Result) + ' on device ' + IntToStr(Device) + ': ' + IntToStr(Ms) + ' ms');
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
    Summary := Fmt('SumGpu', [GpuName, ModelLabel(Gpu), IntToStr(GpuMs)]) + #13#10 +
      Fmt('SumCpuFallback', [ModelLabel(Cpu), IntToStr(CpuMs)]) + #13#10;
  end
  else
  begin
    Cpu := SettleModel(Gpu, 1, CpuMs);
    Gpu := Cpu;
    Summary := Fmt('SumCpuOnly', [ModelLabel(Cpu), IntToStr(CpuMs)]) + #13#10;
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
      Summary := Summary + Msg('SumCudaFail') + #13#10
    else
      Summary := Summary + Fmt('SumCudaTimes', [IntToStr(CudaMs), IntToStr(GpuMs)]) + #13#10;
    if CudaMs > 0 then SetMeasurement('CudaGpuMs', CudaMs);
    // The backend itself isn't written: Auto (the default) uses CUDA only when these measurements say it's
    // more than 10% faster, and anyone who chose a backend keeps it.
    if (CudaMs >= 0) and (GpuMs > 0) and (CudaMs * 10 < GpuMs * 9) then
      Summary := Summary + Msg('SumCudaFaster') + #13#10
    else
    begin
      Summary := Summary + Msg('SumCudaNotFaster') + #13#10;
      if CudaDownloaded and (SuppressibleMsgBox(Fmt('AskDeleteCuda', [IntToStr(CudaMs), IntToStr(GpuMs)]), mbConfirmation, MB_YESNO, IDNO) = IDYES) then
      begin
        DelTree(CudaDir, True, True, True);
        AddedFiles.Delete(AddedFiles.IndexOf('native\cuda'));
        Summary := Summary + Msg('SumCudaDeleted') + #13#10;
      end;
    end;
  end;
  EventLog(Summary);
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
      EventLog('Deleting (ticked by the player): ' + FoundPath[I]);
      if FoundIsDir[I] then DelTree(FoundPath[I], True, True, True) else DeleteFile(FoundPath[I]);
    end
    else if FoundIsSettings[I] then
    begin
      if ReplaceSettings then EventLog('Existing settings: will be replaced with the recommendations (ticked by the player).')
      else EventLog('Existing settings: kept; only missing settings will be added.');
    end
    else
      EventLog('Kept as it was: ' + FoundPath[I]);
end;

// The mod folder exists from here on: write everything logged so far, then keep appending.
procedure StartEventLogFile;
var
  I: Integer;
begin
  if EventLogFile <> '' then Exit;
  ForceDirectories(PluginDir + '\logs');
  EventLogFile := PluginDir + '\logs\install-' + GetDateTimeString('yyyymmdd-hhnnss', '-', ':') + '.log';
  if EventLines <> nil then
    for I := 0 to EventLines.Count - 1 do
      SaveStringToFile(EventLogFile, EventLines[I] + #13#10, True);
  AddedFiles.Add('logs');
  EventLog('Event log: ' + EventLogFile);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Code, I: Integer;
  Models, Src, Dest: String;
begin
  if CurStep = ssDone then
  begin
    RunPtModOffer;
    EventLog('Setup finished.');
    // Inno's own detailed log, next to the event log.
    if (ExpandConstant('{log}') <> '') and (EventLogFile <> '') then
      FileCopy(ExpandConstant('{log}'), ChangeFileExt(EventLogFile, '') + '-detailed.log', False);
    Exit;
  end;
  if CurStep = ssInstall then
  begin
    StartEventLogFile;
    if not FoundDetected then DetectFound; // silent installs: detected, never deleted
    DeleteMarked;
    EventLog('Installing the mod''s files into ' + PluginDir + '...');
    Exit;
  end;
  if CurStep <> ssPostInstall then Exit;
  EventLog('Mod files installed.');
  if FileExists(ExpandConstant('{tmp}\BepInEx.zip')) then
  begin
    EventLog('Installing BepInEx 5 (it wasn''t there)...');
    Unzip(ExpandConstant('{tmp}\BepInEx.zip'), ExpandConstant('{app}'));
    if BepInExInstalled then EventLog('BepInEx installed.') else EventLog('BepInEx could NOT be installed.');
  end
  else
    EventLog('BepInEx was already installed: left as it is.');
  if FileExists(ExpandConstant('{tmp}\vc_redist.x64.exe')) then
  begin
    EventLog('Installing the Microsoft Visual C++ runtime...');
    Exec(ExpandConstant('{tmp}\vc_redist.x64.exe'), '/install /quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, Code);
    EventLog('Visual C++ runtime installer finished (exit code ' + IntToStr(Code) + ').');
  end;
  Models := PluginDir + '\models';
  ForceDirectories(Models);
  for I := 1 to ModelCount - 1 do
  begin
    Src := ExpandConstant('{tmp}\') + ModelFile(I);
    Dest := Models + '\' + ModelFile(I);
    // Never overwrites a file that was already there (it was kept, so it stays).
    if FileExists(Src) and not FileExists(Dest) then
    begin
      if FileCopy(Src, Dest, True) then
      begin
        AddedFiles.Add('models\' + ModelFile(I));
        EventLog('Model added: ' + ModelFile(I));
      end
      else
        EventLog('Model could NOT be copied: ' + ModelFile(I));
    end
    else if FileExists(Src) then
      EventLog('Model not copied, one was already there: ' + ModelFile(I));
  end;
  if WizardIsComponentSelected('cuda') and FileExists(ExpandConstant('{tmp}\whisper-cuda.zip')) and not DirExists(CudaDir) then
  begin
    EventLog('Unpacking the CUDA backend (about 1.3 GB)...');
    InstallCuda;
    EventLog('CUDA backend unpacked into ' + CudaDir);
  end;
  EventLog('Timing the chosen models for real...');
  ConfigureModels;
  // For the uninstaller: what this installation added besides its own [Files] (appended to earlier runs).
  for I := 0 to AddedFiles.Count - 1 do
    SaveStringToFile(PluginDir + '\' + AddedListName, AddedFiles[I] + #13#10, True);
  EventLog('Recorded for the uninstaller: ' + IntToStr(AddedFiles.Count) + ' added item(s).');
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
