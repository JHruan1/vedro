; Vedro Windows x64 Native Installer (Inno Setup 6)
; Compiled automatically by scripts/build-windows.ps1 -> dist/vedro-v<Version>-windows-x64-setup.exe

#ifndef MyAppVersion
  #define MyAppVersion "1.0.12"
#endif
#ifndef MyReleaseDir
  #define MyReleaseDir "..\app\build\windows\x64\runner\Release"
#endif
#ifndef MyOutputDir
  #define MyOutputDir "..\dist"
#endif
#ifndef MyIconFile
  #define MyIconFile "..\app\windows\runner\resources\app_icon.ico"
#endif

[Setup]
AppId={{8D6E4A29-5C1F-4B9E-A732-9F0E1B6D4C20}
AppName=Vedro
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}.0
AppVerName=Vedro {#MyAppVersion}
AppMutex=VedroSingleInstanceMutex
AppPublisher=Vedro Media Player
AppPublisherURL=https://github.com/JHruan1/vedro
AppSupportURL=https://github.com/JHruan1/vedro/releases
DefaultDirName={autopf}\Vedro
DefaultGroupName=Vedro
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#MyOutputDir}
OutputBaseFilename=vedro-v{#MyAppVersion}-windows-x64-setup
SetupIconFile={#MyIconFile}
UninstallDisplayIcon={app}\Vedro.exe
UninstallDisplayName=Vedro
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
#ifdef HasChineseSimplified
Name: "chinesesimplified"; MessagesFile: "{#ChineseIslPath}"
#endif
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#MyReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Vedro"; Filename: "{app}\Vedro.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Vedro"; Filename: "{app}\Vedro.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
; Register common video file Open-With capability under HKA with full cleanup on uninstall
Root: HKA; Subkey: "Software\Classes\Applications\Vedro.exe"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\Vedro.exe\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\Vedro.exe"" ""%1"""; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\Vedro.exe\SupportedTypes"; ValueType: string; ValueName: ".mkv"; ValueData: ""; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\Vedro.exe\SupportedTypes"; ValueType: string; ValueName: ".mp4"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\Vedro.exe\SupportedTypes"; ValueType: string; ValueName: ".mov"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\Vedro.exe\SupportedTypes"; ValueType: string; ValueName: ".avi"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\Vedro.exe\SupportedTypes"; ValueType: string; ValueName: ".ts"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\Vedro.exe\SupportedTypes"; ValueType: string; ValueName: ".m2ts"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\Vedro.exe\SupportedTypes"; ValueType: string; ValueName: ".webm"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\Vedro.exe\SupportedTypes"; ValueType: string; ValueName: ".flv"; ValueData: ""

[Run]
Filename: "{app}\Vedro.exe"; Description: "{cm:LaunchProgram,Vedro}"; Flags: nowait postinstall
