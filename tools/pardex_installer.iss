; PARDEX Windows installer (Inno Setup 6). package_windows.ps1 builds it from
; dist\PARDEX-Windows when Inno Setup is installed:
;   ISCC.exe /DAppVersion=0.1.0 /DSourceDir=...\dist\PARDEX-Windows tools\pardex_installer.iss
; Installs per user (no administrator prompt), so the launcher can update itself
; by running a newer PARDEX-Setup.exe with /SILENT.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\dist\PARDEX-Windows"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

[Setup]
AppId={{99B43818-A3F2-48A8-A739-DEC1155DCB3B}
AppName=PARDEX
AppVersion={#AppVersion}
AppVerName=PARDEX {#AppVersion}
AppPublisher=PARDEX
DefaultDirName={localappdata}\Programs\PARDEX
DefaultGroupName=PARDEX
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=PARDEX-Setup
SetupIconFile=pardex.ico
UninstallDisplayIcon={app}\PARDEX.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=PARDEX.exe
RestartApplications=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "Masaüstüne kısayol oluştur"; GroupDescription: "Kısayollar:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "pardex-distribution.json,games\*"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceDir}\pardex-distribution.json"; DestDir: "{app}"; Flags: onlyifdoesntexist

[Icons]
Name: "{autoprograms}\PARDEX"; Filename: "{app}\PARDEX.exe"
Name: "{autodesktop}\PARDEX"; Filename: "{app}\PARDEX.exe"; Tasks: desktopicon

[Run]
; Also runs after a silent self-update, so PARDEX comes back on its own.
Filename: "{app}\PARDEX.exe"; Description: "PARDEX'i başlat"; Flags: nowait postinstall
