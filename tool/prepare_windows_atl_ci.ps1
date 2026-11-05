$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$installer = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\setup.exe'
if (-not (Test-Path $vswhere) -or -not (Test-Path $installer)) {
  throw 'Falta Visual Studio Installer en el runner de Windows.'
}
$atl = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.ATL -property installationPath
if (-not $atl) {
  $instance = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (-not $instance) { throw 'Faltan las herramientas C++ de Visual Studio.' }
  Write-Host 'Añadiendo ATL al Visual Studio del runner de Windows.'
  $process = Start-Process -FilePath $installer -ArgumentList @(
    'modify', '--installPath', ('"' + $instance + '"'),
    '--add', 'Microsoft.VisualStudio.Component.VC.ATL',
    '--quiet', '--norestart'
  ) -Wait -PassThru -WindowStyle Hidden
  if ($process.ExitCode -ne 0) { throw "No se pudo instalar ATL (código $($process.ExitCode))." }
  $atl = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.ATL -property installationPath
  if (-not $atl) { throw 'ATL no aparece instalado tras ejecutar Visual Studio Installer.' }
}
Write-Host 'ATL disponible para la compilación de Windows.'
