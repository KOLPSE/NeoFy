$ErrorActionPreference = 'Stop'

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$installer = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\setup.exe'

function Buscar-InstanciaVs {
  param([string]$Requiere = '')
  if (-not (Test-Path $vswhere)) { return $null }
  if ($Requiere) {
    return (& $vswhere -all -products '*' -requires $Requiere -property installationPath 2>$null | Select-Object -First 1)
  }
  return (& $vswhere -all -products '*' -property installationPath 2>$null | Select-Object -First 1)
}

$atl = Buscar-InstanciaVs -Requiere 'Microsoft.VisualStudio.Component.VC.ATL'
if ($atl) {
  Write-Host "ATL disponible para la compilación de Windows ($atl)."
  return
}

$instance = Buscar-InstanciaVs -Requiere 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
if ($instance -and (Test-Path $installer)) {
  Write-Host "Añadiendo ATL a Visual Studio ($instance) en el runner de Windows."
  $process = Start-Process -FilePath $installer -ArgumentList @(
    'modify', '--installPath', ('"' + $instance + '"'),
    '--add', 'Microsoft.VisualStudio.Component.VC.ATL',
    '--quiet', '--norestart'
  ) -Wait -PassThru -WindowStyle Hidden
  if ($process.ExitCode -notin @(0, 3010)) {
    throw "No se pudo instalar ATL (código $($process.ExitCode))."
  }
} else {
  # Si vswhere no detecta ninguna instancia registrada (p. ej. si falta state.json),
  # CMake tampoco encontrará Visual Studio 17 2022: instalamos BuildTools + ATL en C:\ci\vs2022.
  $vsDir = 'C:\ci\vs2022'
  $bootstrapper = Join-Path $env:TEMP "vs_buildtools-$PID.exe"
  Write-Host "Instalando Visual Studio 2022 BuildTools + ATL en $vsDir..."
  try {
    & curl.exe --fail --location --retry 3 --connect-timeout 20 --max-time 600 --output $bootstrapper 'https://aka.ms/vs/17/release/vs_buildtools.exe'
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo descargar vs_buildtools.exe.' }
    $process = Start-Process -FilePath $bootstrapper -ArgumentList @(
      '--installPath', $vsDir,
      '--add', 'Microsoft.VisualStudio.Workload.VCTools',
      '--includeRecommended',
      '--add', 'Microsoft.VisualStudio.Component.VC.ATL',
      '--quiet', '--wait', '--norestart'
    ) -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -notin @(0, 3010)) {
      throw "No se pudo instalar BuildTools + ATL (código $($process.ExitCode))."
    }
  } finally {
    Remove-Item -LiteralPath $bootstrapper -Force -ErrorAction SilentlyContinue
  }
}

$atl = Buscar-InstanciaVs -Requiere 'Microsoft.VisualStudio.Component.VC.ATL'
if (-not $atl) {
  throw 'ATL no aparece registrado en vswhere tras la instalación.'
}
Write-Host "ATL disponible para la compilación de Windows ($atl)."
