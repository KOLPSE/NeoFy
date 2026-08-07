; Instalador de NeoFy (Inno Setup 6).
;
; Empaqueta los TRES ejecutables en uno solo: la interfaz, librespot (audio) y
; el sidecar de metadatos. Sin esto, publicar el proyecto obligaba a cada
; usuario a compilar Rust por su cuenta.
;
; Se genera con:
;   powershell -ExecutionPolicy Bypass -File tool\build_installer.ps1
;
; Es un instalador **por usuario** (PrivilegesRequired=lowest): no pide
; administrador, no toca Archivos de programa y no necesita firma para
; instalarse. Para una app que solo escribe en %APPDATA% y %LOCALAPPDATA% no
; hace falta más, y quita la fricción de un SmartScreen pidiendo elevación.

#define Nombre    "NeoFy"
#define Version   "0.1.0"
#define Autor     "neogex.xyz"
#define Ejecutable "neofy.exe"

[Setup]
AppId={{8C3A1F52-7D64-4E9B-9A21-NEOFY0000001}
AppName={#Nombre}
AppVersion={#Version}
AppVerName={#Nombre} {#Version}
AppPublisher={#Autor}
DefaultDirName={autopf}\{#Nombre}
DefaultGroupName={#Nombre}
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist
OutputBaseFilename=NeoFy-{#Version}-windows-x64
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#Ejecutable}
UninstallDisplayName={#Nombre}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Windows 10 1809 en adelante, que es lo que pide Flutter en escritorio.
MinVersion=10.0.17763

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "Iniciar NeoFy al encender el equipo"; GroupDescription: "Inicio"; Flags: unchecked

[Files]
; Todo el contenido de la carpeta Release: el exe, flutter_windows.dll, los
; plugins, la carpeta data\ con los assets... y los dos sidecars, que el script
; de compilación deja ahí antes de invocar a Inno.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#Nombre}"; Filename: "{app}\{#Ejecutable}"
Name: "{group}\{cm:UninstallProgram,{#Nombre}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#Nombre}"; Filename: "{app}\{#Ejecutable}"; Tasks: desktopicon
Name: "{userstartup}\{#Nombre}"; Filename: "{app}\{#Ejecutable}"; Tasks: startup

[Run]
Filename: "{app}\{#Ejecutable}"; Description: "{cm:LaunchProgram,{#Nombre}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Los sidecars sobreviven a un cierre a lo bruto de la app. Si el usuario
; desinstala con la música sonando, quedarían dos procesos huérfanos ocupando
; el nombre del dispositivo en Spotify Connect y sin ventana que los pare.
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM neofy.exe"; Flags: runhidden; RunOnceId: "MatarApp"
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM librespot.exe"; Flags: runhidden; RunOnceId: "MatarAudio"
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM metadata-sidecar.exe"; Flags: runhidden; RunOnceId: "MatarMeta"

[UninstallDelete]
; La caché de carátulas y de audio se puede regenerar; no tiene sentido dejarla
; ocupando disco tras desinstalar. Los tokens y las credenciales NO se tocan
; aquí a propósito: si el usuario reinstala, no tendrá que volver a loguearse.
Type: filesandordirs; Name: "{userappdata}\neofy\art"
Type: filesandordirs; Name: "{userappdata}\neofy\librespot\audio"

[Code]
// Instalar encima de una copia en marcha deja ficheros bloqueados y el
// instalador falla a mitad. Se avisa y se cierra todo antes de empezar.
function InitializeSetup(): Boolean;
var
  Codigo: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM neofy.exe', '',
       SW_HIDE, ewWaitUntilTerminated, Codigo);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM librespot.exe', '',
       SW_HIDE, ewWaitUntilTerminated, Codigo);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM metadata-sidecar.exe', '',
       SW_HIDE, ewWaitUntilTerminated, Codigo);
  Result := True;
end;
