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
; La versión la inyecta build_installer.ps1 leyéndola de `kVersion` en
; lib/core/app_config.dart, que es la única fuente de la verdad: así el
; instalador y el actualizador no pueden decir cosas distintas.
#ifndef Version
  #define Version "0.0.0"
#endif
#define Autor     "neogex.xyz"
#define Ejecutable "neofy.exe"
#define RedirectUri "http://127.0.0.1:8898/callback"

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
var
  PaginaClientId: TInputQueryWizardPage;
  EditRedirect: TNewEdit;

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

procedure AbrirPanel(Sender: TObject);
var
  Codigo: Integer;
begin
  ShellExec('open', 'https://developer.spotify.com/dashboard', '', '',
            SW_SHOWNORMAL, ewNoWait, Codigo);
end;

// El Client ID ya configurado, si el usuario reinstala o actualiza. Evita
// pedirle otra vez algo que ya dio.
function ClientIdGuardado(): String;
var
  Contenido: AnsiString;
  Inicio, Fin: Integer;
begin
  Result := '';
  if not LoadStringFromFile(ExpandConstant('{userappdata}\neofy\config.json'),
                            Contenido) then
    Exit;
  Inicio := Pos('"clientId"', Contenido);
  if Inicio = 0 then Exit;
  // Saltar hasta la comilla que abre el valor, pasando por encima de los dos
  // puntos y de los espacios que pudiera haber si alguien lo editó a mano.
  Inicio := Inicio + Length('"clientId"');
  while (Inicio <= Length(Contenido)) and (Contenido[Inicio] <> '"') do
    Inicio := Inicio + 1;
  Inicio := Inicio + 1;
  Fin := Inicio;
  while (Fin <= Length(Contenido)) and (Contenido[Fin] <> '"') do
    Fin := Fin + 1;
  Result := Copy(Contenido, Inicio, Fin - Inicio);
end;

procedure InitializeWizard();
var
  Etiqueta: TNewStaticText;
  Boton: TNewButton;
  Y: Integer;
begin
  PaginaClientId := CreateInputQueryPage(
    wpSelectTasks,
    'Conectar con tu cuenta de Spotify',
    'NeoFy necesita una app de Spotify propia, y se crea en dos minutos.',
    'Spotify solo permite que una aplicación de terceros funcione para los usuarios' + #13#10 +
    'que su creador da de alta a mano, así que NeoFy no puede traer una configurada.' + #13#10 +
    'Créate la tuya (es gratis) y pega aquí su Client ID.' + #13#10 + #13#10 +
    'Puedes dejarlo en blanco y hacerlo más tarde desde la propia aplicación.');

  PaginaClientId.Add('Client ID:', False);
  // `/CLIENTID=xxx` permite instalaciones desatendidas sin pasar por la
  // interfaz; si no viene, se recupera el que ya estuviera configurado.
  if ExpandConstant('{param:clientid|}') <> '' then
    PaginaClientId.Values[0] := ExpandConstant('{param:clientid|}')
  else
    PaginaClientId.Values[0] := ClientIdGuardado();

  Y := PaginaClientId.Edits[0].Top + PaginaClientId.Edits[0].Height + ScaleY(14);

  Boton := TNewButton.Create(PaginaClientId);
  Boton.Parent := PaginaClientId.Surface;
  Boton.Left := 0;
  Boton.Top := Y;
  Boton.Width := ScaleX(190);
  Boton.Height := ScaleY(23);
  Boton.Caption := '1. Abrir el panel de Spotify';
  Boton.OnClick := @AbrirPanel;

  Etiqueta := TNewStaticText.Create(PaginaClientId);
  Etiqueta.Parent := PaginaClientId.Surface;
  Etiqueta.Left := 0;
  Etiqueta.Top := Y + ScaleY(34);
  Etiqueta.Width := PaginaClientId.SurfaceWidth;
  Etiqueta.WordWrap := True;
  Etiqueta.Caption :=
    '2. Marca "Web API" y pon este Redirect URI, exactamente así ' +
    '(Spotify ya no acepta "localhost", solo el 127.0.0.1 literal):';

  // Un campo de solo lectura en vez de texto suelto: así se puede seleccionar
  // y copiar, que es justo lo que hay que hacer con esto.
  EditRedirect := TNewEdit.Create(PaginaClientId);
  EditRedirect.Parent := PaginaClientId.Surface;
  EditRedirect.Left := 0;
  EditRedirect.Top := Y + ScaleY(70);
  EditRedirect.Width := PaginaClientId.SurfaceWidth;
  EditRedirect.ReadOnly := True;
  EditRedirect.Text := '{#RedirectUri}';

  Etiqueta := TNewStaticText.Create(PaginaClientId);
  Etiqueta.Parent := PaginaClientId.Surface;
  Etiqueta.Left := 0;
  Etiqueta.Top := Y + ScaleY(100);
  Etiqueta.Width := PaginaClientId.SurfaceWidth;
  Etiqueta.WordWrap := True;
  Etiqueta.Caption :=
    '3. Copia el Client ID de la app y pégalo arriba.' + #13#10 + #13#10 +
    'Ten en cuenta que hace falta una cuenta Spotify Premium: es la propia ' +
    'API de Spotify la que lo exige para controlar la reproducción.';
end;

function NextButtonClick(PageID: Integer): Boolean;
var
  Valor: String;
  i: Integer;
  C: Char;
begin
  Result := True;
  if PageID <> PaginaClientId.ID then Exit;

  Valor := Trim(PaginaClientId.Values[0]);
  if Valor = '' then Exit; // Se permite seguir y configurarlo luego.

  // Un Client ID son 32 caracteres hexadecimales. Comprobarlo aquí evita que
  // un valor mal pegado —o el Client Secret, que mide lo mismo— acabe en un
  // error incomprensible de Spotify a mitad del login.
  if Length(Valor) <> 32 then
  begin
    MsgBox('El Client ID debe tener 32 caracteres. El que has pegado tiene ' +
           IntToStr(Length(Valor)) + '.', mbError, MB_OK);
    Result := False;
    Exit;
  end;
  for i := 1 to 32 do
  begin
    C := Valor[i];
    if not (((C >= '0') and (C <= '9')) or
            ((C >= 'a') and (C <= 'f')) or
            ((C >= 'A') and (C <= 'F'))) then
    begin
      MsgBox('El Client ID solo puede tener números y letras de la A a la F. ' +
             'Revisa que lo hayas copiado entero y que no sea el Client Secret.',
             mbError, MB_OK);
      Result := False;
      Exit;
    end;
  end;
end;

// Escribe el Client ID en config.json conservando lo demás: si el usuario ya
// tenía volumen o modo rendimiento guardados, reinstalar no debe borrárselos.
procedure GuardarClientId(Valor: String);
var
  Ruta, Dir: String;
  Contenido: AnsiString;
  Inicio, Fin: Integer;
begin
  Dir := ExpandConstant('{userappdata}\neofy');
  if not DirExists(Dir) then
    ForceDirectories(Dir);
  Ruta := Dir + '\config.json';

  if LoadStringFromFile(Ruta, Contenido) and (Pos('"clientId"', Contenido) > 0) then
  begin
    Inicio := Pos('"clientId"', Contenido) + Length('"clientId"');
    while (Inicio <= Length(Contenido)) and (Contenido[Inicio] <> '"') do
      Inicio := Inicio + 1;
    Inicio := Inicio + 1;
    Fin := Inicio;
    while (Fin <= Length(Contenido)) and (Contenido[Fin] <> '"') do
      Fin := Fin + 1;
    Contenido := Copy(Contenido, 1, Inicio - 1) + Valor +
                 Copy(Contenido, Fin, Length(Contenido) - Fin + 1);
  end
  else
    Contenido := '{"clientId":"' + Valor + '"}';

  SaveStringToFile(Ruta, Contenido, False);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Valor: String;
begin
  if CurStep <> ssPostInstall then Exit;
  Valor := Trim(PaginaClientId.Values[0]);
  if Valor <> '' then
    GuardarClientId(Valor);
end;
