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
if (-not (Test-Path $installer)) {
  throw 'Falta Visual Studio Installer en el runner de Windows.'
}

$instance = $null
if (Test-Path $vswhere) {
  $instance = & $vswhere -all -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1
  if (-not $instance) {
    $instance = & $vswhere -products '*' -property installationPath 2>$null |
      Where-Object { $_ -and (Test-Path (Join-Path $_ 'VC\Tools\MSVC')) } |
      Select-Object -First 1
  }
}

if (-not $instance -and $env:VSINSTALLDIR) {
  $cand = $env:VSINSTALLDIR.TrimEnd('\')
  if (Test-Path (Join-Path $cand 'VC\Tools\MSVC')) {
    $instance = $cand
  }
}

if (-not $instance) {
  $instance = Get-ChildItem -Path @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\*\*",
    "${env:ProgramFiles}\Microsoft Visual Studio\*\*"
  ) -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'VC\Tools\MSVC') } |
    Select-Object -ExpandProperty FullName -First 1
}

if (-not $instance) {
  throw 'Faltan las herramientas C++ de Visual Studio.'
}

Write-Host "Añadiendo ATL a Visual Studio ($instance) en el runner de Windows."
$process = Start-Process -FilePath $installer -ArgumentList @(
  'modify', '--installPath', ('"' + $instance + '"'),
  '--add', 'Microsoft.VisualStudio.Component.VC.ATL',
  '--quiet', '--norestart'
) -Wait -PassThru -WindowStyle Hidden
if ($process.ExitCode -ne 0) {
  throw "No se pudo instalar ATL (código $($process.ExitCode))."
}

if (-not (Buscar-AtlEnDisco)) {
  throw 'ATL no aparece instalado tras ejecutar Visual Studio Installer.'
}
if (Test-Path 'C:\ci\msvc-env.ps1') {
  & 'C:\ci\msvc-env.ps1'
}
Write-Host 'ATL disponible para la compilación de Windows.'
