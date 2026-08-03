; Astral — Windows 安装包（Inno Setup 6）
; CI：.github/workflows/build.yml 在 flutter build 后调用 ISCC。
;
;   ISCC installer\astral.iss /DMyAppVersion=1.0.0
;
; 输出：astral-{MyAppVersion}-windows-x64-setup.exe

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#define MyAppName "Astral"
#define MyAppPublisher "AstralNext"
#define MyAppExeName "astral.exe"
#define BuildOutput "..\build\windows\x64\runner\Release"

[Setup]
AppId={{A1C3E5F7-2B4D-4A6C-8E0F-1D3B5A7C9E2F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
PrivilegesRequired=admin
WizardStyle=modern
SolidCompression=yes
OutputDir=..\release_installer
OutputBaseFilename=astral-{#MyAppVersion}-windows-x64-setup

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildOutput}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Flags: nowait postinstall skipifsilent
