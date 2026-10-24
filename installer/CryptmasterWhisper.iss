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
  #define AppVersion "0.9.1"
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
; Info pages: installer-info*.txt are the sources; tools\info-to-rtf.ps1 makes the .rtf shown (bold lines).
; Inno's own detailed log (copied into the mod's logs folder at the end, next to the event log).
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"; InfoBeforeFile: "installer-info.rtf"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"; InfoBeforeFile: "installer-info-spa.rtf"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"; InfoBeforeFile: "installer-info-por.rtf"

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
  // The next model up for the CPU when its estimate is close to the budget (-1 = none): downloaded too,
  // timed for real, and kept if it measures within the budget (the estimate is noisy near the line).
  CpuStretch: Integer;
  // Things already there before this installation.
  FoundCount: Integer;
  FoundPath: array of String;
  FoundIsDir: array of Boolean;
  FoundIsSettings: array of Boolean;
  FoundCaption: array of String;
  FoundWarning: array of String;
  FoundBox: array of TNewCheckBox;
  FoundWarn: array of TNewStaticText;
  Ticked: TStringList;  // paths ticked for deletion, kept across Back and Next
  FoundDetected: Boolean;
  // Replacing an installation made by this installer (set on the "already installed" page).
  Upgrading: Boolean;
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

// Appends one line to a log, UTF-8 (the texts have accents). Retries for a moment: a text editor opening
// the log (the finish page's option) can hold it while the last lines are written.
procedure AppendLogLine(FileName, Line: String);
var
  Lines: TArrayOfString;
  Tries: Integer;
begin
  SetArrayLength(Lines, 1);
  Lines[0] := Line;
  for Tries := 1 to 20 do
  begin
    if SaveStringsToUTF8FileWithoutBOM(FileName, Lines, True) then Exit;
    Sleep(100);
  end;
end;

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
  if EventLogFile <> '' then AppendLogLine(EventLogFile, Line);
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

// Listed on NVIDIA PCs only (if it's there already, it isn't downloaded again but it's tested anyway).
function CudaOffered: Boolean;
begin
  // Whether it's already there is only known once the folder is: UpdateCudaItem greys it out then.
  Result := HasNvidiaGpu;
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
  // Again after Back: the previous folder's checkboxes go first, remembering what was ticked (the same
  // things found again stay ticked).
  if Ticked = nil then Ticked := TStringList.Create;
  Ticked.Clear;
  for Known := 0 to GetArrayLength(FoundBox) - 1 do
  begin
    if (FoundBox[Known] <> nil) and FoundBox[Known].Checked then Ticked.Add(Lowercase(FoundPath[Known]));
    if FoundBox[Known] <> nil then FoundBox[Known].Free;
    if FoundWarn[Known] <> nil then FoundWarn[Known].Free;
  end;
  FoundCount := 0;
  SetArrayLength(FoundWarn, MaxFound);
  for Known := 0 to MaxFound - 1 do FoundWarn[Known] := nil;
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

// CUDA ticked and needing a download: not there yet, or there but ticked for deletion (then downloaded afresh).
function CudaWanted: Boolean;
begin
  Result := WizardIsComponentSelected('cuda') and ((not CudaPresent) or MarkedForDeletion(CudaDir));
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
    Box.Checked := (Ticked <> nil) and (Ticked.IndexOf(Lowercase(FoundPath[I])) >= 0);
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
    FoundWarn[I] := Warn;
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

// Runs a cmwbench.exe (Exe) on a model; returns the output lines. AsPlayer: without admin rights, for a copy in
// the game's folder, which the player's programs can write to (a DLL planted there gains nothing that way).
function RunBenchExe(Exe, Model, Args: String; AsPlayer: Boolean; var Lines: TArrayOfString): Boolean;
var
  Code: Integer;
  OutFile: String;
  Output: TExecOutput;
begin
  if AsPlayer then
  begin
    // A process without admin rights can't write to {tmp}, so its result goes next to it.
    OutFile := ExtractFileDir(Exe) + '\cmwbench-installer-result.txt';
    DeleteFile(OutFile);
    Result := ExecAsOriginalUser(Exe, '"' + Model + '" ' + Args + ' --out "' + OutFile + '"', ExtractFileDir(Exe),
      SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0) and LoadStringsFromFile(OutFile, Lines);
    DeleteFile(OutFile);
  end
  else
  begin
    Result := ExecAndCaptureOutput(Exe, '"' + Model + '" ' + Args, ExtractFileDir(Exe), SW_HIDE, ewWaitUntilTerminated, Code, Output)
      and (Code = 0);
    if Result then Lines := Output.StdOut;
  end;
  if Result then EventLog('cmwbench (' + ExtractFileDir(Exe) + ') ' + Args + ': ' + BenchValue(Lines, 'backend') + ' ' + BenchValue(Lines, 'device') +
    ', median ' + BenchValue(Lines, 'median_ms') + ' ms, encode ' + BenchValue(Lines, 'encode_ms') + ' ms')
  else EventLog('cmwbench failed: ' + Exe + ' ' + Args);
end;

function RunBench(Model, Args: String; var Lines: TArrayOfString): Boolean;
begin
  Result := RunBenchExe(ExpandConstant('{tmp}\bench\cmwbench.exe'), Model, Args, False, Lines);
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
  // Testing only: /TESTCPUESTIMATE=<percent> scales the CPU estimates (a borderline PC on demand). Always logged.
  Est := StrToIntDef(ExpandConstant('{param:TESTCPUESTIMATE|0}'), 0);
  if (Device = 1) and (Est > 0) then
  begin
    for I := 0 to ModelCount - 1 do
      if Estimate[Device][I] >= 0 then Estimate[Device][I] := Estimate[Device][I] * Est div 100;
    EventLog('TEST: /TESTCPUESTIMATE scaled the processor estimates to ' + IntToStr(Est) + '%.');
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
  CpuStretch := -1;
  if (CpuPick + 1 < ModelCount) and (Estimate[1][CpuPick + 1] >= 0) and (Estimate[1][CpuPick + 1] <= BudgetMs * 5 div 4) then
    CpuStretch := CpuPick + 1;

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
  if CpuStretch >= 0 then
    Report := Report + Fmt('RepStretch', [ModelLabel(CpuStretch), FormatMs(Estimate[1][CpuStretch]), IntToStr(BudgetMs)]) + #13#10;
  if CudaPresent then
    Report := Report + Msg('RepCudaPresent') + #13#10;
  Report := Report + #13#10 + Fmt('RepFootnote', [IntToStr(BudgetMs)]);
  BenchPage.RichEditViewer.Text := Report;
  EventLog(Report);
  if not Interactive then Exit;
  // Tick the recommendations on the components page. Replacing an installation keeps the models it had
  // ticked (unticking them would only bring up Inno's "components exist" warning; they'd stay anyway).
  if not Upgrading then
    for I := 1 to ModelCount - 1 do
      WizardSelectComponents('!' + ModelComponent(I));
  if (GpuName <> '') and (GpuPick > 0) then WizardSelectComponents(ModelComponent(GpuPick));
  if CpuPick > 0 then WizardSelectComponents(ModelComponent(CpuPick));
  if CpuStretch > 0 then WizardSelectComponents(ModelComponent(CpuStretch));
end;

// ---- An existing installation: replace it, or remove it ----

const
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{6F1B2C3D-8E4A-4C7B-9D2E-5A1F0C9B7E21}_is1';

var
  ExistingPage: TInputOptionWizardPage;
  ExistingKind: Integer;            // 0 none, 1 installed by this installer, 2 installed by hand (zip or build)
  ExistingDir, ExistingVersion, ExistingUninstaller: String;
  CloseQuietly: Boolean;

// Only the entry this install mode writes: an admin install never trusts the per-user one, which any program
// the player runs can write (its uninstaller would then be started with admin rights).
function ReadUninstallValue(Name: String; var Value: String): Boolean;
begin
  if IsAdminInstallMode then Result := RegQueryStringValue(HKLM, UninstallKey, Name, Value)
  else Result := RegQueryStringValue(HKCU, UninstallKey, Name, Value);
end;

// Inno's own uninstaller (unins000.exe...), nothing else.
function RegisteredInstallExists: Boolean;
var
  Uninstaller: String;
begin
  Result := ReadUninstallValue('UninstallString', Uninstaller);
  if not Result then Exit;
  Uninstaller := RemoveQuotes(Uninstaller);
  Result := FileExists(Uninstaller) and (CompareText(Copy(ExtractFileName(Uninstaller), 1, 5), 'unins') = 0)
    and (CompareText(ExtractFileExt(Uninstaller), '.exe') = 0);
end;

procedure DetectExisting;
var
  Location: String;
begin
  ExistingKind := 0;
  if RegisteredInstallExists then
  begin
    ExistingKind := 1;
    ReadUninstallValue('UninstallString', ExistingUninstaller);
    ExistingUninstaller := RemoveQuotes(ExistingUninstaller);
    if not ReadUninstallValue('DisplayVersion', ExistingVersion) then ExistingVersion := '?';
    if ReadUninstallValue('InstallLocation', Location) then ExistingDir := RemoveBackslashUnlessRoot(Location)
    else ExistingDir := ExtractFileDir(ExistingUninstaller);
  end
  // Installed by hand: only looked for in the folder this installer is pointed at.
  else if FileExists(PluginDir + '\CryptmasterWhisper.dll') then
  begin
    ExistingKind := 2;
    ExistingDir := RemoveBackslashUnlessRoot(GameDir);
  end;
end;

var
  ManualLogFile: String;

procedure Note(S: String);
begin
  EventLog(S);
  AppendLogLine(ManualLogFile, GetDateTimeString('yyyy-mm-dd hh:nn:ss.zzz', '-', ':') + '  ' + S);
end;

// Removes a hand-installed copy: only the mod's own files, never models, recordings, logs or settings.
procedure RemoveManualInstall;
var
  Plugin: String;
  I: Integer;
  Own: array[0..8] of String;
begin
  Plugin := AddBackslash(ExistingDir) + '{#PluginSub}';
  ForceDirectories(Plugin + '\logs');
  ManualLogFile := Plugin + '\logs\uninstall-' + GetDateTimeString('yyyymmdd-hhnnss', '-', ':') + '.log';
  Note('Uninstall started (installed by hand): Cryptmaster Whisper, in ' + ExistingDir);
  Own[0] := 'CryptmasterWhisper.dll'; Own[1] := 'CryptmasterWhisper.pdb'; Own[2] := 'LICENSE';
  Own[3] := 'THIRD-PARTY-NOTICES.txt'; Own[4] := 'README.md'; Own[5] := 'models\README.txt';
  Own[6] := 'native\vulkan'; Own[7] := 'textos'; Own[8] := 'vad';
  for I := 0 to 8 do
    if DirExists(Plugin + '\' + Own[I]) then
    begin
      DelTree(Plugin + '\' + Own[I], True, True, True);
      Note('Removed: ' + Own[I] + '\');
    end
    else if FileExists(Plugin + '\' + Own[I]) then
    begin
      DeleteFile(Plugin + '\' + Own[I]);
      Note('Removed: ' + Own[I]);
    end;
  RemoveDir(Plugin + '\native');
  RemoveDir(Plugin + '\models');
  Note('Kept: models, recordings, logs, settings, any CUDA folder, BepInEx and anything else that was here.');
  Note('Uninstall finished.');
end;

// Inno's uninstaller relaunches itself from a temporary copy (_iu*.tmp), so its first process may end
// straight away: wait while that copy runs.
function UninstallerRunning: Boolean;
var
  Locator, Service, Items: Variant;
begin
  Result := False;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Service := Locator.ConnectServer('.', 'root\CIMV2');
    // Named _unins.tmp by current Inno versions, _iu*.tmp by older ones.
    Items := Service.ExecQuery('SELECT ProcessId FROM Win32_Process WHERE Name LIKE ''\_unins%.tmp'' OR Name LIKE ''\_iu%.tmp''');
    Result := Items.Count > 0;
  except
    Result := False;
  end;
end;

// Runs the registered uninstaller (its own window and confirmation); True if it actually uninstalled.
function RunRegisteredUninstaller: Boolean;
var
  Code, Waited: Integer;
begin
  Result := False;
  EventLog('Running the existing uninstaller: ' + ExistingUninstaller);
  if not Exec(ExistingUninstaller, '', '', SW_SHOWNORMAL, ewWaitUntilTerminated, Code) then Exit;
  Waited := 0;
  // Done when its uninstall entry is gone; cancelled when its process ended and the entry is still there.
  while RegisteredInstallExists and (Waited < 3600) do
  begin
    Sleep(500);
    Waited := Waited + 1;
    if (Waited > 4) and not UninstallerRunning then Break;
  end;
  Result := not RegisteredInstallExists;
  if Result then EventLog('Existing installation removed.') else EventLog('Existing installation not removed (uninstall cancelled or failed).');
end;

function ExistingPageNext: Boolean;
begin
  Result := True;
  if ExistingPage.SelectedValueIndex = 0 then
  begin
    EventLog('Existing installation: replacing it (models, recordings, logs and settings are kept).');
    if ExistingKind = 1 then WizardForm.DirEdit.Text := ExistingDir;
    Upgrading := ExistingKind = 1;
    Exit;
  end;
  EventLog('Existing installation: removing it.');
  if ExistingKind = 1 then
  begin
    if RunRegisteredUninstaller then
    begin
      MsgBox(Msg('ExistRemoved'), mbInformation, MB_OK);
      CloseQuietly := True;
      WizardForm.Close;
    end
    else
      MsgBox(Msg('ExistNotRemoved'), mbInformation, MB_OK);
    Result := False;
  end
  else
  begin
    RemoveManualInstall;
    MsgBox(Msg('ExistRemoved'), mbInformation, MB_OK);
    CloseQuietly := True;
    WizardForm.Close;
    Result := False;
  end;
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  Confirm := not CloseQuietly;
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
  // First page: an existing installation (skipped when there's none).
  DetectExisting;
  ExistingPage := CreateInputOptionPage(wpWelcome, Msg('ExistTitle'), '', '', True, False);
  // The folder on its own line, shortened with "..." if it doesn't fit; the options move down to make room.
  if ExistingKind = 1 then ExistingPage.SubCaptionLabel.Caption := Fmt('ExistRegistered', [ExistingVersion,
    MinimizePathName(ExistingDir, ExistingPage.SubCaptionLabel.Font, ExistingPage.SurfaceWidth - ScaleX(8))])
  else ExistingPage.SubCaptionLabel.Caption := Fmt('ExistManual', [MinimizePathName(ExistingDir, ExistingPage.SubCaptionLabel.Font, ExistingPage.SurfaceWidth - ScaleX(8))]);
  ExistingPage.SubCaptionLabel.AdjustHeight;
  ExistingPage.CheckListBox.Top := ExistingPage.SubCaptionLabel.Top + ExistingPage.SubCaptionLabel.Height + ScaleY(10);
  ExistingPage.Add(Msg('ExistReplace'));
  ExistingPage.Add(Msg('ExistRemove'));
  ExistingPage.SelectedValueIndex := 0;
  if ExistingKind = 1 then EventLog('Already installed (by this installer): version ' + ExistingVersion + ' in ' + ExistingDir)
  else if ExistingKind = 2 then EventLog('Already installed (by hand) in ' + ExistingDir)
  else EventLog('No existing installation found.');
end;

var
  ComponentsClickCheck: TNotifyEvent; // Inno's own handler (updates the disk space needed)

procedure UpdateCudaNote(Sender: TObject);
begin
  if (Sender <> nil) and (ComponentsClickCheck <> nil) then ComponentsClickCheck(Sender);
  CudaNote.Visible := WizardIsComponentSelected('cuda') and not CudaPresent;
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
  // Chained, not replaced: Inno's handler keeps the "requires at least ... MB" line up to date.
  ComponentsClickCheck := List.OnClickCheck;
  List.OnClickCheck := @UpdateCudaNote;
end;

// ---- The Portuguese localisation (a separate mod): offered on the Portuguese installer's finish page ----

const
  PtRepo = 'AngusSckitt/cryptmaster-localizacao-ptbr';
  // Off until that mod has a public release with an installer (the download would fail otherwise).
  OfferPtMod = False;

var
  PtModBox: TNewCheckBox;
  PtModLabel: TNewStaticText;

procedure PtModLabelClick(Sender: TObject);
begin
  PtModBox.Checked := not PtModBox.Checked;
end;

function PtModInstalled: Boolean;
begin
  Result := FileExists(AddBackslash(GameDir) + 'BepInEx\plugins\CryptmasterLocalizacaoPTBR\CryptmasterLocalizacaoPTBR.dll');
end;

procedure ShowPtModOffer;
begin
  // Interactive installs only: a silent install never downloads or launches anything unasked.
  if not OfferPtMod or WizardSilent or (ActiveLanguage <> 'brazilianportuguese') or PtModInstalled or (PtModBox <> nil) then Exit;
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
  // Never below the bottom of the page.
  if PtModBox.Top + PtModBox.Height > WizardForm.FinishedPage.ClientHeight - ScaleY(4) then
    PtModBox.Top := WizardForm.FinishedPage.ClientHeight - PtModBox.Height - ScaleY(4);
  PtModBox.Checked := True;
  // Checkboxes don't wrap their caption: it goes in a label beside the box (clicking it ticks the box too).
  PtModBox.Width := ScaleX(17);
  PtModBox.Caption := '';
  PtModLabel := TNewStaticText.Create(WizardForm);
  PtModLabel.Parent := WizardForm.FinishedPage;
  PtModLabel.Left := PtModBox.Left + ScaleX(20);
  PtModLabel.Top := PtModBox.Top + ScaleY(1);
  PtModLabel.Width := WizardForm.FinishedLabel.Width - ScaleX(20);
  PtModLabel.AutoSize := False;
  PtModLabel.WordWrap := True;
  PtModLabel.Height := PtModBox.Height;
  PtModLabel.Caption := Msg('PtModOffer');
  PtModLabel.OnClick := @PtModLabelClick;
  PtModBox.Height := ScaleY(17);
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

var
  FolderDone: Boolean;

// The game folder is settled: look for what's already there. Runs when leaving the folder page, or (when
// Inno skips that page, as it does when replacing an installation) on reaching the benchmark page.
procedure FolderChosen;
var
  I: Integer;
begin
  FolderDone := True;
  EventLog('Game folder: ' + WizardDirValue);
  DetectFound;
  BuildFoundPage;
  if FoundCount = 0 then EventLog('Nothing of the mod''s was already there.');
  for I := 0 to FoundCount - 1 do
    EventLog('Already there: ' + FoundPath[I]);
end;

// The CUDA item: when a CUDA folder is already there, it isn't downloaded again (it's timed anyway), so the
// item is greyed out and says so. Its tick, if any, is left alone: unticking something installed before
// would only bring up Inno's "components exist" warning.
procedure UpdateCudaItem;
var
  I: Integer;
begin
  for I := 0 to WizardForm.ComponentsList.Items.Count - 1 do
    if WizardForm.ComponentsList.ItemObject[I] <> nil then
      if Pos('CUDA', WizardForm.ComponentsList.ItemCaption[I]) > 0 then
      begin
        WizardForm.ComponentsList.ItemEnabled[I] := not CudaPresent;
        if CudaPresent then WizardForm.ComponentsList.ItemCaption[I] := Msg('CompCudaPresent');
      end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpSelectComponents then
  begin
    UpdateCudaItem;
    UpdateCudaNote(nil);
  end
  // Inno calls this in silent installs too: there, nothing is ticked on the player's behalf.
  else if CurPageID = BenchPage.ID then
  begin
    if not FolderDone then FolderChosen;
    RunBenchmark(not WizardSilent);
  end
  else if CurPageID = wpFinished then
  begin
    WizardForm.FinishedLabel.Caption := Msg('Finished') + #13#10#13#10 + Summary;
    if Msg('FinishLangNote') <> '' then
      WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + #13#10 + Msg('FinishLangNote');
    // The label keeps its original height unless told otherwise: grow it to fit the summary, and move
    // the checkboxes below it.
    WizardForm.FinishedLabel.AdjustHeight;
    WizardForm.RunList.Top := WizardForm.FinishedLabel.Top + WizardForm.FinishedLabel.Height + ScaleY(8);
    // The list reaches the bottom of the page by default: shrink it to its items, so anything placed under
    // it (the PT localisation offer) is on the page and can be seen and unticked.
    if WizardForm.RunList.Items.Count > 0 then
      WizardForm.RunList.Height := WizardForm.RunList.Items.Count * ScaleY(22) + ScaleY(4);
    ShowPtModOffer;
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := ((PageID = ExistingPage.ID) and (ExistingKind = 0)) or ((PageID = CudaPage.ID) and not CudaWanted)
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
  if CurPageID = ExistingPage.ID then
  begin
    Result := ExistingPageNext;
    Exit;
  end;
  if CurPageID = wpSelectDir then
  begin
    if not IsGameDir(WizardDirValue) then
    begin
      MsgBox(Msg('NotGameDir'), mbError, MB_OK);
      Result := False;
      Exit;
    end;
    FolderChosen;
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
    if CudaWanted then
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

// A path as a PowerShell single-quoted string, where only quotes need doubling. PowerShell also takes the
// typographic single quotes as quotes (a folder can be called "Angus’s games"); Windows paths can't hold ".
function PsQuote(S: String): String;
begin
  Result := S;
  StringChangeEx(Result, '''', '''''', True);
  StringChangeEx(Result, #$2018, #$2018#$2018, True);
  StringChangeEx(Result, #$2019, #$2019#$2019, True);
  StringChangeEx(Result, #$201A, #$201A#$201A, True);
  StringChangeEx(Result, #$201B, #$201B#$201B, True);
  Result := '''' + Result + '''';
end;

procedure Unzip(Zip, Dest: String);
var
  Code: Integer;
begin
  ForceDirectories(Dest);
  Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath ' + PsQuote(Zip) + ' -DestinationPath ' + PsQuote(Dest) + ' -Force"',
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

// Times the GPU model on the CUDA build (ours runs from its folder, so its DLLs are found; without admin
// rights, since that folder may hold DLLs this installer never checked); -1 if it fails.
function TimeCuda(Model: Integer): Integer;
var
  Lines: TArrayOfString;
  Exe: String;
  Penalty: Integer;
begin
  Result := -1;
  Exe := CudaDir + '\cmwbench-installer-test.exe';
  if not FileCopy(ExpandConstant('{tmp}\bench\cmwbench.exe'), Exe, False) then Exit;
  try
    if RunBenchExe(Exe, ModelPath(Model), '--ctx 256 --runs 3', True, Lines) and (Pos('CUDA', BenchValue(Lines, 'backend')) = 1) then
      Result := StrToIntDef(BenchValue(Lines, 'median_ms'), -1);
  finally
    DeleteFile(Exe);
  end;
  // Testing only: /TESTCUDAPENALTY=<ms> makes CUDA look slower, to exercise the "CUDA lost" path on a PC
  // where it wins. Always logged.
  Penalty := StrToIntDef(ExpandConstant('{param:TESTCUDAPENALTY|0}'), 0);
  if (Result >= 0) and (Penalty > 0) then
  begin
    Result := Result + Penalty;
    EventLog('TEST: /TESTCUDAPENALTY added ' + IntToStr(Penalty) + ' ms to the CUDA time (now ' + IntToStr(Result) + ' ms).');
  end;
end;

procedure ConfigureModels;
var
  Largest, I, Gpu, Cpu, GpuMs, CpuMs, CudaMs, StretchMs: Integer;
  AskKey: String;
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
    // A borderline bigger model, if it was downloaded: kept when it measures within the budget.
    StretchMs := -1;
    if (CpuStretch > Cpu) and Available(CpuStretch) then
    begin
      StretchMs := Verify(CpuStretch, 1);
      if (StretchMs >= 0) and (StretchMs <= BudgetMs) then
        EventLog('Borderline ' + ModelLabel(CpuStretch) + ' on the processor: ' + IntToStr(StretchMs) + ' ms, within ' + IntToStr(BudgetMs) + ' ms: kept.')
      else
      begin
        EventLog('Borderline ' + ModelLabel(CpuStretch) + ' on the processor: ' + IntToStr(StretchMs) + ' ms, over ' + IntToStr(BudgetMs) + ' ms: the smaller one stays.');
        StretchMs := -1;
      end;
    end;
    if StretchMs >= 0 then
    begin
      Cpu := CpuStretch;
      CpuMs := StretchMs;
    end
    else
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
      // More than 10% slower gets its own line; roughly even gets the polite one.
      if (CudaMs >= 0) and (GpuMs > 0) and (CudaMs * 10 > GpuMs * 11) then
        Summary := Summary + Msg('SumCudaSlower') + #13#10
      else
        Summary := Summary + Msg('SumCudaNotFaster') + #13#10;
      if (CudaMs * 10 > GpuMs * 11) then AskKey := 'AskDeleteCudaSlower' else AskKey := 'AskDeleteCuda';
      if CudaDownloaded and (SuppressibleMsgBox(Fmt(AskKey, [IntToStr(CudaMs), IntToStr(GpuMs)]), mbConfirmation, MB_YESNO, IDNO) = IDYES) then
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
      AppendLogLine(EventLogFile, EventLines[I]);
  // The logs folder isn't recorded for the uninstaller: logs survive an uninstall.
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

var
  UninstallLogFile: String;

// The uninstaller's own timestamped log, next to the install logs (which it never deletes).
procedure UninstallLog(S: String);
var
  Line: String;
begin
  Log(S);
  if UninstallLogFile = '' then
  begin
    ForceDirectories(ExpandConstant('{app}\{#PluginSub}\logs'));
    UninstallLogFile := ExpandConstant('{app}\{#PluginSub}\logs\uninstall-') + GetDateTimeString('yyyymmdd-hhnnss', '-', ':') + '.log';
  end;
  Line := GetDateTimeString('yyyy-mm-dd hh:nn:ss.zzz', '-', ':') + '  ' + S;
  AppendLogLine(UninstallLogFile, Line);
end;

// Only what an install can have listed: native\cuda, or a model file directly in models\. The list sits in a
// folder the player's programs can write to, so anything else in it (..\, drive letters) is ignored.
function IsAddedItem(Item: String): Boolean;
var
  Name: String;
begin
  Result := CompareText(Item, 'native\cuda') = 0;
  if Result or (CompareText(Copy(Item, 1, 7), 'models\') <> 0) then Exit;
  Name := Copy(Item, 8, Length(Item));
  Result := (Name <> '') and (Pos('\', Name) = 0) and (Pos('/', Name) = 0) and (Pos(':', Name) = 0)
    and (Pos('..', Name) = 0) and (CompareText(ExtractFileExt(Name), '.bin') = 0);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Lines: TArrayOfString;
  I: Integer;
  Plugin, Path, Item: String;
begin
  Plugin := ExpandConstant('{app}\{#PluginSub}');
  if CurUninstallStep = usUninstall then
  begin
    UninstallLog('Uninstall started: Cryptmaster Whisper, in ' + ExpandConstant('{app}'));
    UninstallLog('Removing the mod''s own installed files (the ones this installer copied)...');
    Exit;
  end;
  if CurUninstallStep <> usPostUninstall then Exit;
  if LoadStringsFromFile(Plugin + '\' + AddedListName, Lines) then
    for I := 0 to GetArrayLength(Lines) - 1 do
    begin
      Item := Trim(Lines[I]);
      // Logs always survive an uninstall (an older install may have listed them): not an added item either.
      if not IsAddedItem(Item) then
      begin
        if (Item <> '') and (CompareText(Item, 'logs') <> 0) then UninstallLog('Ignored (not something this installer adds): ' + Item);
        Continue;
      end;
      Path := Plugin + '\' + Item;
      if DirExists(Path) then
      begin
        DelTree(Path, True, True, True);
        UninstallLog('Removed (added by the installer): ' + Item + '\');
      end
      else if FileExists(Path) then
      begin
        DeleteFile(Path);
        UninstallLog('Removed (added by the installer): ' + Item);
      end;
    end;
  DeleteFile(Plugin + '\' + AddedListName);
  UninstallLog('Kept: the logs folder, settings, BepInEx, and anything that was already here before installing.');
  UninstallLog('Uninstall finished.');
  // Remove folders only if they're now empty (anything else in them was someone else's).
  RemoveDir(Plugin + '\models');
  RemoveDir(Plugin + '\native\cuda');
  // Folders a hand-installed copy had made before this installer came along (Inno keeps those).
  RemoveDir(Plugin + '\native\vulkan');
  RemoveDir(Plugin + '\vad');
  RemoveDir(Plugin + '\native');
  RemoveDir(Plugin + '\textos');
  RemoveDir(Plugin);
end;
