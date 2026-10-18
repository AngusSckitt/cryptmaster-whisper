; Installer for Cryptmaster Whisper. Built by tools\package.ps1 (which stages the files in dist\stage).
; Ships only what may be redistributed (docs\LICENSING.md): the mod, the Vulkan whisper.cpp build, BepInEx.
; Larger Whisper models and the optional CUDA build are downloaded from their official sources on the
; player's computer, checked against pinned SHA-256 hashes, and never packed in here.

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
Name: "standard"; Description: "Standard"
Name: "custom"; Description: "Custom"; Flags: iscustom

[Components]
Name: "main"; Description: "Cryptmaster Whisper, with the Vulkan whisper.cpp (GPU: AMD, Intel or NVIDIA; CPU otherwise)"; Types: standard custom; Flags: fixed
Name: "models"; Description: "Extra Whisper models (downloaded; the game's own small models are always available)"; Types: standard custom
Name: "models\base"; Description: "base: 57 MB, good on any PC"; Types: standard custom; Flags: exclusive
Name: "models\small"; Description: "small: 181 MB, needs a GPU or a fast CPU"; Types: custom; Flags: exclusive
Name: "models\turbo"; Description: "large-v3-turbo: 547 MB, most accurate, needs a GPU"; Types: custom; Flags: exclusive
Name: "cuda"; Description: "NVIDIA CUDA backend (optional, about 650 MB download; read the next page)"; Types: custom; Check: HasNvidiaGpu

[Files]
Source: "{#Stage}\plugin\*"; DestDir: "{app}\{#PluginSub}"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: main
Source: "{#Stage}\bepinex\BepInEx.zip"; DestDir: "{tmp}"; Flags: deleteafterinstall; Components: main; Check: not BepInExInstalled

[UninstallDelete]
Type: filesandordirs; Name: "{app}\{#PluginSub}"

[Code]
var
  CudaPage: TOutputMsgMemoWizardPage;
  DownloadPage: TDownloadWizardPage;
  ChosenModel: String;

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

// ---- Pages ----

procedure InitializeWizard;
begin
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

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = CudaPage.ID) and not WizardIsComponentSelected('cuda');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
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
    ChosenModel := '';
    if WizardIsComponentSelected('models\base') then begin ChosenModel := 'ggml-base-q5_1.bin'; DownloadPage.Add('{#HfBase}ggml-base-q5_1.bin', ChosenModel, '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898'); end;
    if WizardIsComponentSelected('models\small') then begin ChosenModel := 'ggml-small-q5_1.bin'; DownloadPage.Add('{#HfBase}ggml-small-q5_1.bin', ChosenModel, 'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb'); end;
    if WizardIsComponentSelected('models\turbo') then begin ChosenModel := 'ggml-large-v3-turbo-q5_0.bin'; DownloadPage.Add('{#HfBase}ggml-large-v3-turbo-q5_0.bin', ChosenModel, '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2'); end;
    if WizardIsComponentSelected('cuda') then DownloadPage.Add('{#CudaUrl}', 'whisper-cuda.zip', '{#CudaSha}');
    if NeedsVcRuntime then DownloadPage.Add('https://aka.ms/vs/17/release/vc_redist.x64.exe', 'vc_redist.x64.exe', '');
    if (ChosenModel <> '') or WizardIsComponentSelected('cuda') or NeedsVcRuntime then
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

procedure InstallCuda;
var
  Src, Dest: String;
  Find: TFindRec;
  Code: Integer;
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
  Code: Integer;
  Models: String;
begin
  if CurStep <> ssPostInstall then Exit;
  if FileExists(ExpandConstant('{tmp}\BepInEx.zip')) then
    Unzip(ExpandConstant('{tmp}\BepInEx.zip'), ExpandConstant('{app}'));
  if FileExists(ExpandConstant('{tmp}\vc_redist.x64.exe')) then
    Exec(ExpandConstant('{tmp}\vc_redist.x64.exe'), '/install /quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, Code);
  if ChosenModel <> '' then
  begin
    Models := ExpandConstant('{app}\{#PluginSub}\models');
    ForceDirectories(Models);
    FileCopy(ExpandConstant('{tmp}\') + ChosenModel, Models + '\' + ChosenModel, False);
    SetConfig('Model', 'Multilingual', ChosenModel);
  end;
  if WizardIsComponentSelected('cuda') and FileExists(ExpandConstant('{tmp}\whisper-cuda.zip')) then
    InstallCuda;
end;
