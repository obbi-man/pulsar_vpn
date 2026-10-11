; Inno Setup script — build after `flutter build windows --release`
; CI: iscc flutter/installer/windows/pulsar.iss
; Output: dist/windows/PulsarVPN-Setup.exe

#define MyAppName "Pulsar VPN"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Pulsar"
#define MyAppExeName "PulsarVPN.exe"
; Relative to this .iss file → flutter/build/windows/x64/runner/Release
#define BuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{A8E3C2B1-7D4F-4E9A-9C11-B0C4D5E6F701}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\PulsarVPN
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\..\dist\windows
OutputBaseFilename=PulsarVPN-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
; Russian.isl is not always present on CI Inno installs — keep English only.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Optional: ship wintun.dll beside the exe when present in Release folder
; Source: "{#BuildDir}\wintun.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
