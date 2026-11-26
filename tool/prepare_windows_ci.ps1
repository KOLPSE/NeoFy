$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

foreach ($d in @($env:APPDATA, $env:LOCALAPPDATA, $env:USERPROFILE, $env:TEMP, $env:TMP, $env:CARGO_HOME)) {
  if ($d) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

# El SDK vive fuera del directorio del repo en una ruta corta para evitar
# errores de MAX_PATH (>260 caracteres) al limpiar el workspace del runner.
$toolsDir = if ($env:NEOFY_CI_TOOLS_DIR) { $env:NEOFY_CI_TOOLS_DIR } else { 'C:\ci\flutter-3.44.6' }
$sdkRoot = Join-Path $toolsDir 'flutter'
$completed = Join-Path $toolsDir 'sdk-ready'

function Instalar-FlutterSdk {
  Write-Host 'Preparando Flutter 3.44.6 en el directorio del job.'
  New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
  $manifest = Invoke-RestMethod -TimeoutSec 45 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
  $release = $manifest.releases | Where-Object { $_.version -eq '3.44.6' -and $_.channel -eq 'stable' } | Select-Object -First 1
  if (-not $release -or -not $release.sha256) { throw 'No se encuentra Flutter 3.44.6 en el manifiesto oficial.' }
  $archive = Join-Path $toolsDir "flutter-$env:CI_JOB_ID.zip"
  try {
    & curl.exe --fail --location --retry 3 --connect-timeout 20 --max-time 1200 --output $archive "https://storage.googleapis.com/flutter_infra_release/releases/$($release.archive)"
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo descargar el SDK de Flutter.' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash -ne $release.sha256) {
      throw 'La suma de Flutter no coincide con el manifiesto oficial.'
    }
    Write-Host 'SDK descargado y verificado; extrayendo archivos.'
    & tar.exe -xf $archive -C $toolsDir
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $sdkRoot 'bin\flutter.bat'))) {
      Remove-Item -LiteralPath $sdkRoot -Recurse -Force -ErrorAction SilentlyContinue
      throw 'No se pudo extraer el SDK de Flutter.'
    }
    [IO.File]::WriteAllText($completed, 'Flutter 3.44.6')
  } finally {
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
  }
}

if (-not (Test-Path $completed)) {
  $cleanDir = "$toolsDir-clean"
  $cleanReady = Join-Path $cleanDir 'sdk-ready'
  if (Test-Path $cleanReady) {
    $toolsDir = $cleanDir
    $sdkRoot = Join-Path $toolsDir 'flutter'
    $completed = $cleanReady
  } else {
    if (Test-Path $toolsDir) {
      Write-Host "Directorio $toolsDir incompleto sin sdk-ready; intentando apartarlo."
      $sufijo = if ($env:CI_JOB_ID) { $env:CI_JOB_ID } else { [DateTime]::UtcNow.ToString('yyyyMMddHHmmss') }
      $corrupto = "$toolsDir.corrupt-$sufijo"
      cmd /c "move `"$toolsDir`" `"$corrupto`" >nul 2>nul"
      if (Test-Path $corrupto) {
        Remove-Item -LiteralPath $corrupto -Recurse -Force -ErrorAction SilentlyContinue
      }
      if (Test-Path $toolsDir) {
        Write-Host "No se pudo mover $toolsDir; usando ruta limpia $cleanDir."
        $toolsDir = $cleanDir
        $sdkRoot = Join-Path $toolsDir 'flutter'
        $completed = $cleanReady
      }
    }
    if (-not (Test-Path $completed)) {
      Instalar-FlutterSdk
    }
  }
}
if ($env:PUB_CACHE) {
  $env:PUB_CACHE = [IO.Path]::GetFullPath($env:PUB_CACHE)
} else {
  $env:PUB_CACHE = 'C:\ci\pub-cache'
}
New-Item -ItemType Directory -Force -Path $env:PUB_CACHE | Out-Null

# Si algún paquete en PUB_CACHE quedó corrupto (bytes no UTF-8 o basura en
# disco), bórralo para que flutter pub get vuelva a descargarlo limpio.
$pubHosted = Join-Path $env:PUB_CACHE 'hosted'
if (Test-Path $pubHosted) {
  $utf8Estricto = New-Object System.Text.UTF8Encoding($false, $true)
  $pubCorrupto = $false
  try {
    foreach ($f in Get-ChildItem -LiteralPath $pubHosted -File -Recurse -Filter '*.dart' -ErrorAction Stop) {
      $textoPub = [IO.File]::ReadAllText($f.FullName, $utf8Estricto)
      if ($textoPub.IndexOf([char]0) -ge 0) {
        Write-Host "Paquete con bytes de control en PUB_CACHE: $($f.FullName)"
        $pubCorrupto = $true
        break
      }
    }
  } catch {
    Write-Host "Error leyendo PUB_CACHE (posible directorio o archivo corrupto): $($_.Exception.Message)"
    $pubCorrupto = $true
  }
  if ($pubCorrupto) {
    Write-Host "Limpiando caché corrupta en $pubHosted..."
    $sufijo = if ($env:CI_JOB_ID) { $env:CI_JOB_ID } else { $PID }
    $apartado = "$pubHosted.corrupt-$sufijo"
    cmd /c "move `"$pubHosted`" `"$apartado`" 2>nul" | Out-Null
    $global:LASTEXITCODE = 0
    if (Test-Path $pubHosted) {
      Remove-Item -LiteralPath $pubHosted -Recurse -Force -ErrorAction SilentlyContinue
      if (Test-Path $pubHosted) {
        cmd /c "rmdir /s /q `"$pubHosted`" 2>nul"
        $global:LASTEXITCODE = 0
      }
    }
    if (Test-Path $pubHosted) {
      $env:PUB_CACHE = "$($env:PUB_CACHE)-$sufijo"
      New-Item -ItemType Directory -Force -Path $env:PUB_CACHE | Out-Null
      Write-Host "Aislando PUB_CACHE en $($env:PUB_CACHE) por entrada corrupta."
    } elseif (Test-Path $apartado) {
      Remove-Item -LiteralPath $apartado -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

# Si falta el snapshot compilado (primer uso o intento previo fallido), limpia
# el estado de flutter_tools para regenerar package_config.json con rutas válidas.
$snapshot = Join-Path $sdkRoot 'bin\cache\flutter_tools.snapshot'
if (-not (Test-Path $snapshot)) {
  Remove-Item -LiteralPath (Join-Path $sdkRoot 'packages\flutter_tools\.dart_tool') -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $sdkRoot 'bin\cache\flutter.bat.lock') -Force -ErrorAction SilentlyContinue
}

$env:PATH = "$sdkRoot\bin;$env:USERPROFILE\.cargo\bin;$env:PATH"
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'safe.directory'
$env:GIT_CONFIG_VALUE_0 = $sdkRoot.Replace('\', '/')

function Ejecutar-FlutterVersion {
  $prevPref = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & (Join-Path $sdkRoot 'bin\flutter.bat') --version
    return $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $prevPref
  }
}

if ((Ejecutar-FlutterVersion) -ne 0) {
  Write-Host 'flutter --version falló; regenerando flutter_tools.snapshot...'
  Remove-Item -LiteralPath (Join-Path $sdkRoot 'packages\flutter_tools\.dart_tool') -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $sdkRoot 'bin\cache\flutter_tools.snapshot') -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $sdkRoot 'bin\cache\flutter.bat.lock') -Force -ErrorAction SilentlyContinue
  if ((Ejecutar-FlutterVersion) -ne 0) {
    Write-Host 'El SDK de Flutter en caché está corrupto; reinstalando desde cero...'
    $apartadoSdk = "$toolsDir.corrupt-$(if ($env:CI_JOB_ID) { $env:CI_JOB_ID } else { $PID })"
    cmd /c "move `"$toolsDir`" `"$apartadoSdk`" 2>nul" | Out-Null
    $global:LASTEXITCODE = 0
    if (Test-Path $toolsDir) { Remove-Item -LiteralPath $toolsDir -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $apartadoSdk) { Remove-Item -LiteralPath $apartadoSdk -Recurse -Force -ErrorAction SilentlyContinue }
    Instalar-FlutterSdk
    if ((Ejecutar-FlutterVersion) -ne 0) { throw 'Flutter no está disponible.' }
  }
}

$dartExe = Join-Path $sdkRoot 'bin\cache\dart-sdk\bin\dart.exe'
$toolBackend = Join-Path $sdkRoot 'packages\flutter_tools\bin\tool_backend.dart'
function Probar-ToolBackend {
  $prevProj = $env:PROJECT_DIR
  Remove-Item Env:PROJECT_DIR -ErrorAction SilentlyContinue
  $prevPref = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $salida = & $dartExe $toolBackend windows-x64 release 2>&1
    $codigo = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $prevPref
    if ($null -ne $prevProj) { $env:PROJECT_DIR = $prevProj }
  }
  return @{ Codigo = $codigo; Salida = ($salida | Out-String).Trim() }
}
$pruebaBackend = Probar-ToolBackend
if ($pruebaBackend.Codigo -ne 1) {
  Write-Host "tool_backend.dart devolvió código $($pruebaBackend.Codigo): $($pruebaBackend.Salida)"
  Write-Host "Regenerando packages\flutter_tools\.dart_tool y flutter_tools.snapshot..."
  $dotTool = Join-Path $sdkRoot 'packages\flutter_tools\.dart_tool'
  $apartadoDot = "$dotTool.corrupt-$PID"
  if (Test-Path $dotTool) {
    cmd /c "move `"$dotTool`" `"$apartadoDot`" 2>nul" | Out-Null
    $global:LASTEXITCODE = 0
    Remove-Item -LiteralPath $apartadoDot -Recurse -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath (Join-Path $sdkRoot 'bin\cache\flutter_tools.snapshot') -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $sdkRoot 'bin\cache\flutter.bat.lock') -Force -ErrorAction SilentlyContinue
  & (Join-Path $sdkRoot 'bin\flutter.bat') --version
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo regenerar flutter_tools.' }
  $pruebaBackend = Probar-ToolBackend
  if ($pruebaBackend.Codigo -ne 1) {
    throw "tool_backend.dart sigue fallando (código $($pruebaBackend.Codigo)): $($pruebaBackend.Salida)"
  }
}

# Verifica que los archivos del wrapper C++ del engine Windows en caché no estén
# corruptos (por ejemplo tras un fallo de disco en vm-windows que deje
# standard_codec.cc ilegible para MSVC).
$engineDir = Join-Path $sdkRoot 'bin\cache\artifacts\engine'
$wrapperDir = Join-Path $engineDir 'windows-x64\cpp_client_wrapper'
$genSnapshot = Join-Path $engineDir 'windows-x64-release\gen_snapshot.exe'
$corrupto = -not (Test-Path $genSnapshot)
if (-not $corrupto -and (Test-Path $wrapperDir)) {
  foreach ($f in (Get-ChildItem -LiteralPath $wrapperDir -File -Recurse | Where-Object { $_.Extension -in '.cc','.h' })) {
    $texto = [IO.File]::ReadAllText($f.FullName)
    if ($texto.IndexOf([char]0) -ge 0 -or -not $texto.TrimStart().StartsWith('// Copyright')) {
      Write-Host "Archivo corrupto en caché de Flutter: $($f.FullName)"
      $corrupto = $true
      break
    }
  }
}
if ($corrupto) {
  Write-Host 'Limpiando caché corrupta del engine Windows de Flutter y ejecutando precache...'
  foreach ($sub in @('windows-x64', 'windows-x64-profile', 'windows-x64-release')) {
    $d = Join-Path $engineDir $sub
    if (Test-Path $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
  }
  if (Test-Path 'windows\flutter\ephemeral') {
    Remove-Item -LiteralPath 'windows\flutter\ephemeral' -Recurse -Force -ErrorAction SilentlyContinue
  }
  & (Join-Path $sdkRoot 'bin\flutter.bat') precache --windows --force
  if ($LASTEXITCODE -ne 0) { throw 'Falló flutter precache --windows --force.' }
}
