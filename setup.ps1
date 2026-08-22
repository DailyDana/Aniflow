# Aniflow bagimlilik kurulumu / dependency bootstrap — Daily Dana
# Depoda tutulmayan buyuk ikili dosyalari indirir:
#   bin\ffmpeg.exe        BtbN'in resmi statik yapimi (libplacebo destekli)
#   vapoursynth\*         RIFE eklentisi + v4.6 modeli + BestSource (istege bagli RIFE icin)
param([switch]$Force)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = $PSScriptRoot
$Bin  = Join-Path $Root 'bin'
$Vap  = Join-Path $Root 'vapoursynth'
$Tmp  = Join-Path $env:TEMP 'Aniflow-setup'
New-Item -ItemType Directory -Force -Path $Bin, $Vap, $Tmp | Out-Null

$DepsUrl   = 'https://github.com/DailyDana/Aniflow/releases/download/deps-v1/vapoursynth-deps.zip'

# BtbN sabit adli "ffmpeg-master-latest-win64-gpl.zip" dosyasini kaldirdi (Agu 2026);
# dosya adi artik her derlemede degisiyor. Once GitHub API'den coz, API oran
# sinirina takilirsa (anonim 60 istek/saat) surum sayfasinin HTML'inden coz.
function Resolve-FfmpegUrl {
    try {
        $r = Invoke-RestMethod 'https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest' -UseBasicParsing
        $a = @($r.assets | Where-Object { $_.name -match '^ffmpeg-N-.*-win64-gpl\.zip$' })
        if ($a.Count -gt 0) { return $a[0].browser_download_url }
    } catch {
        Write-Host '  (GitHub API yanit vermedi, surum sayfasindan cozuluyor...)'
    }
    $resp = Invoke-WebRequest 'https://github.com/BtbN/FFmpeg-Builds/releases/latest' -UseBasicParsing
    $final = $null   # PS 5.1: ResponseUri; PS 7: RequestMessage.RequestUri
    if ($resp.BaseResponse.PSObject.Properties['ResponseUri']) { $final = $resp.BaseResponse.ResponseUri.AbsolutePath }
    elseif ($resp.BaseResponse.RequestMessage) { $final = $resp.BaseResponse.RequestMessage.RequestUri.AbsolutePath }
    $tag = if ($final) { ($final -split '/')[-1] } else { 'latest' }
    $html = (Invoke-WebRequest "https://github.com/BtbN/FFmpeg-Builds/releases/expanded_assets/$tag" -UseBasicParsing).Content
    if ($html -match 'href="([^"]*ffmpeg-N-[^"]*-win64-gpl\.zip)"') {
        $u = $Matches[1]
        if ($u -notmatch '^https?:') { $u = 'https://github.com' + $u }
        return $u
    }
    throw ('BtbN ffmpeg indirme adresi cozulemedi. Elle kurulum: https://github.com/BtbN/FFmpeg-Builds/releases ' +
           'adresinden "win64-gpl.zip" dosyasini indirip icindeki ffmpeg.exe''yi bin\ klasorune kopyalayin.')
}

function Get-Download([string]$url, [string]$out) {
    Write-Host "Indiriliyor / downloading: $url"
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
}

# ---- 1) ffmpeg ----
$ff = Join-Path $Bin 'ffmpeg.exe'
if ($Force -or -not (Test-Path $ff)) {
    $zip = Join-Path $Tmp 'ffmpeg.zip'
    Get-Download (Resolve-FfmpegUrl) $zip
    Expand-Archive $zip $Tmp -Force
    $exe = Get-ChildItem $Tmp -Recurse -Filter 'ffmpeg.exe' | Select-Object -First 1
    if (-not $exe) { throw 'ffmpeg.exe zip icinde bulunamadi.' }
    Copy-Item $exe.FullName $ff -Force
    # dogrulama: libplacebo filtresi var mi?
    $ErrorActionPreference = 'Continue'
    $filters = & $ff -hide_banner -filters 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    if ($filters -notmatch 'libplacebo') { throw 'Indirilen ffmpeg libplacebo icermiyor!' }
}

# ---- 2) RIFE / VapourSynth dosyalari (istege bagli ozellik) ----
$rifeDll  = Join-Path $Vap 'librife_windows_x86-64.dll'
$rifeMod  = Join-Path $Vap 'models\rife-v4.6_ensembleFalse'
$bsDll    = Join-Path $Vap 'bestsource.dll'
$mpvVap   = Join-Path $env:APPDATA 'mpv\vapoursynth'

# mpv kurulumunda zaten varsa yerelden kopyala (indirme gerekmez)
if (-not (Test-Path $rifeDll) -and (Test-Path (Join-Path $mpvVap 'librife_windows_x86-64.dll'))) {
    Copy-Item (Join-Path $mpvVap 'librife_windows_x86-64.dll') $Vap -Force
}
if (-not (Test-Path $rifeMod) -and (Test-Path (Join-Path $mpvVap 'models\rife-v4.6_ensembleFalse'))) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Vap 'models') | Out-Null
    Copy-Item (Join-Path $mpvVap 'models\rife-v4.6_ensembleFalse') (Join-Path $Vap 'models\') -Recurse -Force
}

if ($Force -or -not ((Test-Path $rifeDll) -and (Test-Path $rifeMod) -and (Test-Path $bsDll))) {
    $zip = Join-Path $Tmp 'vapoursynth-deps.zip'
    try {
        Get-Download $DepsUrl $zip
        Expand-Archive $zip $Vap -Force
    } catch {
        Write-Warning "RIFE bagimliliklari indirilemedi: $($_.Exception.Message)"
        Write-Warning 'RIFE olmadan da uygulama calisir; daha sonra tekrar deneyin.'
    }
}

# ---- 3) Real-ESRGAN (AI upscale modu icin; resmi release'ten) ----
$AiDir = Join-Path $Root 'realesrgan'
$AiExe = Join-Path $AiDir 'realesrgan-ncnn-vulkan.exe'
if ($Force -or -not (Test-Path $AiExe)) {
    $zip = Join-Path $Tmp 'realesrgan.zip'
    try {
        Get-Download 'https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-windows.zip' $zip
        Expand-Archive $zip $AiDir -Force
    } catch {
        Write-Warning "Real-ESRGAN indirilemedi: $($_.Exception.Message)"
        Write-Warning 'AI upscale modu olmadan da uygulama calisir.'
    }
}

# ---- 4) vspipe (kullanicinin kurmasi gereken tek parca) ----
$vspipe = Get-Command vspipe.exe -ErrorAction SilentlyContinue

# ---- Ozet ----
Write-Host ''
Write-Host '=== Aniflow kurulum ozeti / setup summary ==='
Write-Host ('  ffmpeg (libplacebo) : {0}' -f $(if (Test-Path $ff) { 'OK' } else { 'EKSIK' }))
Write-Host ('  bestsource.dll      : {0}' -f $(if (Test-Path $bsDll) { 'OK' } else { 'EKSIK (RIFE calismaz)' }))
Write-Host ('  RIFE eklenti+model  : {0}' -f $(if ((Test-Path $rifeDll) -and (Test-Path $rifeMod)) { 'OK' } else { 'EKSIK (RIFE calismaz)' }))
Write-Host ('  Real-ESRGAN (AI)    : {0}' -f $(if (Test-Path $AiExe) { 'OK' } else { 'EKSIK (AI modu calismaz)' }))
Write-Host ('  vspipe (VapourSynth): {0}' -f $(if ($vspipe) { 'OK - ' + $vspipe.Source } else { 'EKSIK' }))
if (-not $vspipe) {
    Write-Host ''
    Write-Host 'RIFE kullanmak icin (istege bagli / optional, for RIFE only):'
    Write-Host '  1) Python 3.12+ kurun: winget install Python.Python.3.12'
    Write-Host '  2) pip install vapoursynth'
}
Write-Host ''
Write-Host 'Hazir! "Aniflow.bat" ile baslatabilirsiniz. / Done - launch "Aniflow.bat".'
