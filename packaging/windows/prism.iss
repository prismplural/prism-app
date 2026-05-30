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
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
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
