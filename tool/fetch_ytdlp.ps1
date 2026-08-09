# Descarga el binario de yt-dlp y lo deja donde la app lo busca.
#
# A diferencia de librespot, yt-dlp no se compila aqui: es Python empaquetado
# como binario independiente por el propio proyecto, asi que basta con bajar
# el ultimo release. Hay que repetir este paso de vez en cuando -YouTube
# rompe extractores sin aviso y yt-dlp se actualiza para seguirle el paso-,
# no es un "una vez y ya" como librespot.
#
#   powershell -ExecutionPolicy Bypass -File tool\fetch_ytdlp.ps1

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$binDir = Join-Path $root 'tool\ytdlp-build\bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

$exe = Join-Path $binDir 'yt-dlp.exe'
$url = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'

Write-Output "Descargando yt-dlp desde $url ..."
Invoke-WebRequest -Uri $url -OutFile $exe

if (-not (Test-Path $exe)) {
    throw "La descarga termino pero no aparece $exe"
}

$size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Output "yt-dlp listo en $exe ($size MB)"
Write-Output ""
Write-Output "Listo. Ahora: flutter build windows --release"
