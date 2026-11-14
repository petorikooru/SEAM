#define MyAppName "KAI Bridge Inspection"
#define MyAppVersion "5.2.0"
#define MyAppPublisher "KAI"
#define MyAppExeName "KAI Bridge Inspection.exe"

#ifndef SourceDir
  #define SourceDir "..\..\dist\KAI Bridge Inspection"
#endif

[Setup]
AppId={{70D6B682-A69B-4CBE-9BF2-1CEB2C046AE4}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\KAI Bridge Inspection
DefaultGroupName=KAI Bridge Inspection
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\release
OutputBaseFilename=KAI_Bridge_Inspection_v5.2.0_Windows_x64_Setup
SetupIconFile=..\..\src\kai_bridge_inspection\qml\assets\KAI.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ChangesAssociations=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "launchstartup"; Description: "Start KAI Bridge Inspection when Windows starts"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\KAI Bridge Inspection"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\KAI Bridge Inspection"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon
Name: "{userstartup}\KAI Bridge Inspection"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: launchstartup

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch KAI Bridge Inspection"; Flags: nowait postinstall skipifsilent
