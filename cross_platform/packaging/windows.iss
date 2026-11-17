; Install the entire Flutter runtime, not just the launcher EXE.
[Setup]
AppId={{77D37AA5-7A42-4A86-9BC7-6C3C5F67BBAC}
AppName=Kumanda
AppVersion=1.0.0-preview.25
VersionInfoVersion=1.0.0.25
AppPublisher=Ertugrul Erzin
AppPublisherURL=https://github.com/ertugrulerzin/LGKumanda
DefaultDirName={localappdata}\Programs\LGKumanda
DefaultGroupName=Kumanda
PrivilegesRequired=lowest
OutputDir=..\build
OutputBaseFilename=LGKumanda-Windows-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\lg_kumanda.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\..\LICENSE

[Tasks]
Name: desktopicon; Description: "Masaüstü kısayolu oluştur"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Kumanda"; Filename: "{app}\lg_kumanda.exe"
Name: "{autodesktop}\Kumanda"; Filename: "{app}\lg_kumanda.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\lg_kumanda.exe"; Description: "Kumanda’yı aç"; Flags: nowait postinstall skipifsilent
