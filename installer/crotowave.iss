; Instalador de CrotoWave (Inno Setup 6)
#define AppName "CrotoWave"
; La versión la pasa scripts/build_windows_installer.sh (/DAppVersion=...);
; este valor solo se usa al compilar el .iss a mano.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppExe "CrotoWave.exe"

[Setup]
AppId={{B7E1C5A2-4D3F-4F6A-9C1E-5C0A7F2D9E11}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=CrotoWave
AppPublisherURL=https://github.com/Dante0Q/CrotoWave
SetupIconFile=..\windows\runner\resources\app_icon.ico
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=output
OutputBaseFilename=CrotoWave-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
DisableProgramGroupPage=yes

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "stage\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Licencias (GPL): la de CrotoWave y el detalle de los componentes de terceros.
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "..\LICENSING.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Desinstalar {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Abrir {#AppName}"; Flags: nowait postinstall skipifsilent
