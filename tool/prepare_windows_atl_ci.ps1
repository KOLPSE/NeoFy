$ErrorActionPreference = 'Stop'

function Buscar-AtlEnDisco {
  if ($env:VCToolsInstallDir -and (Test-Path (Join-Path $env:VCToolsInstallDir 'atlmfc\include\atlbase.h'))) {
    return $true
  }
  $candidatos = Get-ChildItem -Path @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\*\*\VC\Tools\MSVC\*\atlmfc\include\atlbase.h",
    "${env:ProgramFiles}\Microsoft Visual Studio\*\*\VC\Tools\MSVC\*\atlmfc\include\atlbase.h"
  ) -ErrorAction SilentlyContinue
  return [bool]($candidatos | Select-Object -First 1)
}

if (Buscar-AtlEnDisco) {
  Write-Host 'ATL disponible para la compilación de Windows.'
  return
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$installer = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\setup.exe'
if (-not (Test-Path $vswhere) -or -not (Test-Path $installer)) {
  throw 'Falta Visual Studio Installer en el runner de Windows.'
}

$atl = & $vswhere -all -products '*' -requires Microsoft.VisualStudio.Component.VC.ATL -property installationPath | Select-Object -First 1
if (-not $atl) {
  $instance = & $vswhere -all -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
  if (-not $instance) {
    $instance = & $vswhere -all -products '*' -property installationPath |
      Where-Object { Test-Path (Join-Path $_ 'VC\Tools\MSVC') } |
      Select-Object -First 1
  }
  if (-not $instance) { throw 'Faltan las herramientas C++ de Visual Studio.' }

  Write-Host 'Añadiendo ATL al Visual Studio del runner de Windows.'
  $process = Start-Process -FilePath $installer -ArgumentList @(
    'modify', '--installPath', ('"' + $instance + '"'),
    '--add', 'Microsoft.VisualStudio.Component.VC.ATL',
    '--quiet', '--norestart'
  ) -Wait -PassThru -WindowStyle Hidden
  if ($process.ExitCode -ne 0) { throw "No se pudo instalar ATL (código $($process.ExitCode))." }

  if (-not (Buscar-AtlEnDisco)) {
    $atl = & $vswhere -all -products '*' -requires Microsoft.VisualStudio.Component.VC.ATL -property installationPath | Select-Object -First 1
    if (-not $atl) { throw 'ATL no aparece instalado tras ejecutar Visual Studio Installer.' }
  }
  if (Test-Path 'C:\ci\msvc-env.ps1') {
    & 'C:\ci\msvc-env.ps1'
  }
}
Write-Host 'ATL disponible para la compilación de Windows.'
