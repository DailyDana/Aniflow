# Aniflow tek satir kurulum / one-line installer — Daily Dana
# Git gerektirmez. Kullanim / usage (PowerShell):
#   irm https://raw.githubusercontent.com/DailyDana/Aniflow/main/install.ps1 | iex
#
# Yaptiklari: depoyu ZIP olarak indirir, %LOCALAPPDATA%\Aniflow'a acar,
# setup.ps1 ile bagimliliklari kurar ve masaustune kisayol koyar.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Dest = Join-Path $env:LOCALAPPDATA 'Aniflow'
Write-Host "Aniflow kuruluyor / installing to: $Dest"

# ---- 1) Depoyu ZIP olarak indir (git gerekmez) ----
$zip = Join-Path $env:TEMP 'Aniflow-main.zip'
Invoke-WebRequest 'https://github.com/DailyDana/Aniflow/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
$tmp = Join-Path $env:TEMP ('Aniflow-inst-' + [guid]::NewGuid().ToString('N'))
Expand-Archive $zip $tmp -Force
$src = Get-ChildItem $tmp -Directory | Select-Object -First 1

# ---- 2) Hedefe kopyala (ayar dosyasi %APPDATA%'da durur, guncelleme guvenlidir) ----
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
Copy-Item (Join-Path $src.FullName '*') $Dest -Recurse -Force
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

# ---- 3) Bagimliliklar (ffmpeg + RIFE + Real-ESRGAN) ----
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dest 'setup.ps1')

# ---- 4) Masaustu kisayolu ----
$ws  = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Aniflow.lnk'))
$lnk.TargetPath       = Join-Path $Dest 'Aniflow.bat'
$lnk.WorkingDirectory = $Dest
$lnk.Description      = 'Aniflow - Anime4K/FSRCNNX Video Upscaler'
$lnk.Save()

Write-Host ''
Write-Host 'Bitti! Masaustundeki "Aniflow" kisayoluyla baslatabilirsiniz.'
Write-Host 'Done - launch Aniflow from the desktop shortcut.'
