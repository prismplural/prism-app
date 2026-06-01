#define AppName "Prism"
#define AppPublisher "Prism Plural"
#define AppExeName "prism_plurality.exe"

#ifndef AppVersion
#define AppVersion "0.0.0-dev"
#endif

#ifndef AppVersionInfo
#define AppVersionInfo "0.0.0.0"
#endif

#ifndef BundleDir
#define BundleDir "..\..\build\windows\x64\runner\Release"
#endif

#ifndef OutputDir
#define OutputDir "..\..\dist"
#endif

#ifndef VCRedistMajor
#define VCRedistMajor 0
#endif

#ifndef VCRedistMinor
#define VCRedistMinor 0
#endif

#ifndef VCRedistBld
#define VCRedistBld 0
#endif

#ifndef VCRedistRbld
#define VCRedistRbld 0
#endif

[Setup]
AppId={{9D972CC9-3C22-4D37-8A4B-E1B76DBFB90A}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://prismplural.com
AppSupportURL=https://github.com/prismplural/prism-app/issues
AppUpdatesURL=https://github.com/prismplural/prism-app/releases
DefaultDirName={localappdata}\Programs\Prism
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
OutputDir={#OutputDir}
OutputBaseFilename=Prism-{#AppVersion}-windows-x64-install
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
AppMutex=PrismPluralityAppMutex
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} installer
VersionInfoVersion={#AppVersionInfo}
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersionInfo}
VersionInfoCopyright=Copyright (C) 2026 {#AppPublisher}. All rights reserved.
#ifdef SignToolName
SignTool={#SignToolName}
SignedUninstaller=yes
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.dll"
Type: files; Name: "{app}\{#AppExeName}"

[Files]
#ifdef VCRedistPath
Source: "{#VCRedistPath}"; DestName: "vc_redist.x64.exe"; Flags: dontcopy noencryption
#endif
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
var
  VCRedistNeedsRestart: Boolean;

function VCRedistVersionText(
  const Major: Cardinal;
  const Minor: Cardinal;
  const Bld: Cardinal;
  const Rbld: Cardinal): String;
begin
  Result :=
    IntToStr(Major) + '.' +
    IntToStr(Minor) + '.' +
    IntToStr(Bld) + '.' +
    IntToStr(Rbld);
end;

function CompareVCRedistVersion(
  const InstalledMajor: Cardinal;
  const InstalledMinor: Cardinal;
  const InstalledBld: Cardinal;
  const InstalledRbld: Cardinal): Integer;
begin
  Result := 0;

  if InstalledMajor <> {#VCRedistMajor} then
  begin
    if InstalledMajor > {#VCRedistMajor} then Result := 1 else Result := -1;
    Exit;
  end;

  if InstalledMinor <> {#VCRedistMinor} then
  begin
    if InstalledMinor > {#VCRedistMinor} then Result := 1 else Result := -1;
    Exit;
  end;

  if InstalledBld <> {#VCRedistBld} then
  begin
    if InstalledBld > {#VCRedistBld} then Result := 1 else Result := -1;
    Exit;
  end;

  if InstalledRbld <> {#VCRedistRbld} then
  begin
    if InstalledRbld > {#VCRedistRbld} then Result := 1 else Result := -1;
  end;
end;

function ReadVCRedistVersion(
  const RootKey: Integer;
  var InstalledMajor: Cardinal;
  var InstalledMinor: Cardinal;
  var InstalledBld: Cardinal;
  var InstalledRbld: Cardinal): Boolean;
var
  Installed: Cardinal;
  RuntimeKey: String;
begin
  Result := False;
  RuntimeKey := 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64';

  if (not RegQueryDWordValue(RootKey, RuntimeKey, 'Installed', Installed)) or
     (Installed <> 1) then
  begin
    Exit;
  end;

  Result :=
    RegQueryDWordValue(RootKey, RuntimeKey, 'Major', InstalledMajor) and
    RegQueryDWordValue(RootKey, RuntimeKey, 'Minor', InstalledMinor) and
    RegQueryDWordValue(RootKey, RuntimeKey, 'Bld', InstalledBld) and
    RegQueryDWordValue(RootKey, RuntimeKey, 'Rbld', InstalledRbld);
end;

function IsInstalledVCRedistCurrent(
  const ViewName: String;
  const InstalledMajor: Cardinal;
  const InstalledMinor: Cardinal;
  const InstalledBld: Cardinal;
  const InstalledRbld: Cardinal): Boolean;
begin
  Result :=
    CompareVCRedistVersion(
      InstalledMajor, InstalledMinor, InstalledBld, InstalledRbld) >= 0;

  if Result then
  begin
    Log(
      'Visual C++ Runtime x64 version ' +
      VCRedistVersionText(
        InstalledMajor, InstalledMinor, InstalledBld, InstalledRbld) +
      ' is already installed in the ' + ViewName + '.');
  end
    else
  begin
    Log(
      'Visual C++ Runtime x64 version ' +
      VCRedistVersionText(
        InstalledMajor, InstalledMinor, InstalledBld, InstalledRbld) +
      ' in the ' + ViewName + ' is older than bundled version ' +
      VCRedistVersionText(
        {#VCRedistMajor}, {#VCRedistMinor},
        {#VCRedistBld}, {#VCRedistRbld}) +
      '.');
  end;
end;

function NeedsVCRedist: Boolean;
var
  InstalledMajor: Cardinal;
  InstalledMinor: Cardinal;
  InstalledBld: Cardinal;
  InstalledRbld: Cardinal;
  FoundInstalledRuntime: Boolean;
begin
  Result := True;
  FoundInstalledRuntime := False;

  // x64 VC++ v14 may register in either HKLM registry view.
  if ReadVCRedistVersion(
       HKLM32, InstalledMajor, InstalledMinor, InstalledBld, InstalledRbld) then
  begin
    FoundInstalledRuntime := True;
    if IsInstalledVCRedistCurrent(
         '32-bit registry view',
         InstalledMajor, InstalledMinor, InstalledBld, InstalledRbld) then
    begin
      Result := False;
      Exit;
    end;
  end;

  if IsWin64 and
     ReadVCRedistVersion(
       HKLM64, InstalledMajor, InstalledMinor, InstalledBld, InstalledRbld) then
  begin
    FoundInstalledRuntime := True;
    if IsInstalledVCRedistCurrent(
         '64-bit registry view',
         InstalledMajor, InstalledMinor, InstalledBld, InstalledRbld) then
    begin
      Result := False;
      Exit;
    end;
  end;

  if not FoundInstalledRuntime then
  begin
    Log('Visual C++ Runtime x64 is not installed.');
  end;
end;

#ifdef VCRedistPath
function InstallVCRedist: String;
var
  ErrorCode: Integer;
  RedistPath: String;
begin
  Result := '';

  if not NeedsVCRedist then
  begin
    Exit;
  end;

  try
    ExtractTemporaryFile('vc_redist.x64.exe');
  except
    Result :=
      'Could not extract the Microsoft Visual C++ Runtime installer: ' +
      GetExceptionMessage;
    Exit;
  end;

  RedistPath := ExpandConstant('{tmp}\vc_redist.x64.exe');
  Log('Installing Microsoft Visual C++ Runtime x64 from ' + RedistPath + '.');

  if not ShellExec(
       'runas', RedistPath, '/install /passive /norestart', '',
       SW_SHOWNORMAL, ewWaitUntilTerminated, ErrorCode) then
  begin
    Result :=
      'Could not start the Microsoft Visual C++ Runtime installer: ' +
      SysErrorMessage(ErrorCode);
    Exit;
  end;

  if not NeedsVCRedist then
  begin
    Log('Microsoft Visual C++ Runtime x64 prerequisite is now satisfied.');
    Exit;
  end;

  VCRedistNeedsRestart := True;
  Result :=
    'Microsoft Visual C++ Runtime installation did not complete. ' +
    'Restart Windows, then run the Prism installer again.';
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := InstallVCRedist;
  if VCRedistNeedsRestart then
  begin
    NeedsRestart := True;
  end;
end;

function NeedRestart: Boolean;
begin
  Result := VCRedistNeedsRestart;
end;
#endif

// Uninstall-time cleanup of the roaming AppData *data* dir (databases, secure
// storage, prefs), which the sections above never touch. Prompted and
// defaulting to "No" rather than [UninstallDelete]'s unconditional delete, so
// an upgrade-by-reinstall doesn't silently wipe a paired user's data. Leaving
// it behind is what causes the reinstall pairing failure (a stale encrypted
// prism_sync.db can't be opened with the new pairing key).
//
// Dir = %APPDATA%\<CompanyName>\<ProductName> (path_provider_windows reads
// these from the EXE VERSIONINFO; %APPDATA% = Inno {userappdata}, Roaming):
//   Current: Runner.rc -> "Prism Plural"\"Prism"
//   Legacy:  app_data_dir.dart -> com.prismplural\prism_plurality (pre-rebrand,
//            migrated forward on launch, so it can still exist). Remove both.

procedure RemovePrismDataDir(const DataDir: String);
begin
  if DirExists(DataDir) then
  begin
    // DelTree(Dir, IsDir, DeleteFiles, DeleteSubdirsAlso)
    DelTree(DataDir, True, True, True);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  CurrentDataDir: String;
  LegacyDataDir: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    CurrentDataDir := ExpandConstant('{userappdata}\Prism Plural\Prism');
    LegacyDataDir := ExpandConstant('{userappdata}\com.prismplural\prism_plurality');

    // Only bother prompting if there is actually leftover data to remove.
    if DirExists(CurrentDataDir) or DirExists(LegacyDataDir) then
    begin
      if MsgBox(
           'Also remove your local Prism data (databases and settings)?'#13#10#13#10 +
           'Choose No if you plan to reinstall and keep your data.'#13#10 +
           'Choose Yes only if you want a completely clean removal.',
           mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      begin
        RemovePrismDataDir(CurrentDataDir);
        // Remove the legacy dir too when it differs from the current one.
        if CompareText(LegacyDataDir, CurrentDataDir) <> 0 then
          RemovePrismDataDir(LegacyDataDir);
      end;
    end;
  end;
end;
