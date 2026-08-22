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

# BtbN'de sabit adli dosyalar "latest" ETIKETLI surumde durur:
#   releases/download/latest/ffmpeg-master-latest-win64-gpl.zip
# ("releases/latest/download/..." kisayolu KULLANILMAZ: o, API'nin son surumune
# yani dosya adlari her derlemede degisen autobuild-* surumune gider ve 404 verir.)
# Sabit adres bir gun kalkarsa API'den, o da olmazsa surum sayfasindan cozulur.
function Resolve-FfmpegUrl {
    $stable = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip'
    try {
        $null = Invoke-WebRequest -Uri $stable -Method Head -UseBasicParsing
        return $stable
    } catch {
        Write-Host '  (sabit adres yanit vermedi, guncel derleme adi cozuluyor...)'
    }
    try {
        $r = Invoke-RestMethod 'https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest' -UseBasicParsing
        $a = @($r.assets | Where-Object { $_.name -match '^ffmpeg-N-.*-win64-gpl\.zip$' })
        if ($a.Count -gt 0) { return $a[0].browser_download_url }
    } catch { }
    $html = (Invoke-WebRequest 'https://github.com/BtbN/FFmpeg-Builds/releases/expanded_assets/latest' -UseBasicParsing).Content
    if ($html -match 'href="([^"]*ffmpeg-master-latest-win64-gpl\.zip)"') {
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

# ---- 4) VapourSynth (RIFE icin; tasinabilir kurulum, sisteme dokunmaz) ----
# Resmi "Install-Portable-VapourSynth" akisinin katilimsiz kopyasi: gomulu
# Python + pip + VapourSynth wheel, hepsi vapoursynth\portable\ icine.
$VsDir  = Join-Path $Vap 'portable'
$vspipe = Join-Path $VsDir 'Lib\site-packages\vapoursynth\vspipe.exe'
if (-not (Test-Path -LiteralPath $vspipe)) {
    $sys = Get-Command vspipe.exe -ErrorAction SilentlyContinue
    if ($sys) { $vspipe = $sys.Source }   # sistemde zaten varsa onu kullan
}
if ($Force -or -not (Test-Path -LiteralPath $vspipe)) {
    try {
        Write-Host 'VapourSynth (tasinabilir) kuruluyor / installing portable VapourSynth...'
        New-Item -ItemType Directory -Force -Path $VsDir | Out-Null
        $py = Join-Path $Tmp 'python-embed.zip'
        Get-Download 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip' $py
        Expand-Archive $py $VsDir -Force
        Add-Content -Path (Join-Path $VsDir 'python312._pth') -Encoding UTF8 -Value 'Lib\site-packages'
        Get-Download 'https://bootstrap.pypa.io/get-pip.py' (Join-Path $Tmp 'get-pip.py')
        & (Join-Path $VsDir 'python.exe') (Join-Path $Tmp 'get-pip.py') --no-warn-script-location | Out-Null
        $vsz = Join-Path $Tmp 'vs-portable.zip'
        Get-Download 'https://github.com/vapoursynth/vapoursynth/releases/download/R79/VapourSynth64-Portable-R79.zip' $vsz
        Expand-Archive $vsz $VsDir -Force
        $whl = Get-ChildItem (Join-Path $VsDir 'wheel') -Filter '*.whl' | Select-Object -First 1
        & (Join-Path $VsDir 'python.exe') -m pip install --no-warn-script-location $whl.FullName | Out-Null
        $vspipe = Join-Path $VsDir 'Lib\site-packages\vapoursynth\vspipe.exe'
    } catch {
        Write-Warning "VapourSynth kurulamadi: $($_.Exception.Message)"
        Write-Warning 'RIFE olmadan da uygulama calisir; setup.ps1''i tekrar calistirip deneyebilirsiniz.'
    }
}

# ---- Ozet ----
Write-Host ''
Write-Host '=== Aniflow kurulum ozeti / setup summary ==='
Write-Host ('  ffmpeg (libplacebo) : {0}' -f $(if (Test-Path $ff) { 'OK' } else { 'EKSIK' }))
Write-Host ('  bestsource.dll      : {0}' -f $(if (Test-Path $bsDll) { 'OK' } else { 'EKSIK (RIFE calismaz)' }))
Write-Host ('  RIFE eklenti+model  : {0}' -f $(if ((Test-Path $rifeDll) -and (Test-Path $rifeMod)) { 'OK' } else { 'EKSIK (RIFE calismaz)' }))
Write-Host ('  Real-ESRGAN (AI)    : {0}' -f $(if (Test-Path $AiExe) { 'OK' } else { 'EKSIK (AI modu calismaz)' }))
Write-Host ('  vspipe (VapourSynth): {0}' -f $(if (Test-Path -LiteralPath $vspipe) { 'OK - ' + $vspipe } else { 'EKSIK (RIFE calismaz; setup.ps1''i tekrar calistirin)' }))
Write-Host ''
Write-Host 'Hazir! "Aniflow.bat" ile baslatabilirsiniz. / Done - launch "Aniflow.bat".'
