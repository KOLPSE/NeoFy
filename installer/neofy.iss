#define Nombre    "NeoFy"
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
MinVersion=10.0.17763

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "Iniciar NeoFy al encender el equipo"; GroupDescription: "Inicio"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#Nombre}"; Filename: "{app}\{#Ejecutable}"
Name: "{group}\{cm:UninstallProgram,{#Nombre}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#Nombre}"; Filename: "{app}\{#Ejecutable}"; Tasks: desktopicon
Name: "{userstartup}\{#Nombre}"; Filename: "{app}\{#Ejecutable}"; Tasks: startup

[Run]
Filename: "{app}\{#Ejecutable}"; Description: "{cm:LaunchProgram,{#Nombre}}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\{#Ejecutable}"; Flags: nowait runasoriginaluser; Check: WizardSilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM neofy.exe"; Flags: runhidden; RunOnceId: "MatarApp"
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM librespot.exe"; Flags: runhidden; RunOnceId: "MatarAudio"
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM metadata-sidecar.exe"; Flags: runhidden; RunOnceId: "MatarMeta"

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\neofy\art"
Type: filesandordirs; Name: "{userappdata}\neofy\librespot\audio"

[Code]
var
  PaginaClientId: TInputQueryWizardPage;
  EditRedirect: TNewEdit;

function ProcesoVivo(Nombre: String): Boolean;
var
  Codigo: Integer;
begin
  Result := Exec(ExpandConstant('{cmd}'),
                 '/C tasklist /FI "IMAGENAME eq ' + Nombre + '" /NH | ' +
                 'find /I "' + Nombre + '" >nul',
                 '', SW_HIDE, ewWaitUntilTerminated, Codigo) and (Codigo = 0);
end;

function EsperarAQueMuera(Nombre: String; Intentos: Integer): Boolean;
var
  i: Integer;
begin
  for i := 1 to Intentos do
  begin
    if not ProcesoVivo(Nombre) then
    begin
      Result := True;
      Exit;
    end;
    Sleep(250);
  end;
  Result := not ProcesoVivo(Nombre);
end;

function InitializeSetup(): Boolean;
var
  Codigo: Integer;
begin
  EsperarAQueMuera('neofy.exe', 16);

  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM neofy.exe', '',
       SW_HIDE, ewWaitUntilTerminated, Codigo);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM librespot.exe', '',
       SW_HIDE, ewWaitUntilTerminated, Codigo);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM metadata-sidecar.exe', '',
       SW_HIDE, ewWaitUntilTerminated, Codigo);

  EsperarAQueMuera('neofy.exe', 40);
  EsperarAQueMuera('librespot.exe', 40);
  EsperarAQueMuera('metadata-sidecar.exe', 40);
  Result := True;
end;

procedure AbrirPanel(Sender: TObject);
var
  Codigo: Integer;
begin
  ShellExec('open', 'https://developer.spotify.com/dashboard', '', '',
            SW_SHOWNORMAL, ewNoWait, Codigo);
end;

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
