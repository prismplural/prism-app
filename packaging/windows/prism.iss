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
OutputBaseFilename=Prism-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
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
