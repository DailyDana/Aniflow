# Aniflow — Anime4K / FSRCNNX Video Upscaler GUI (PORTABLE)
# Author: Daily Dana
# All dependencies live in this folder: bin\ffmpeg.exe + shaders\*.glsl (+ realesrgan\, vapoursynth\)
# Runs on Windows PowerShell 5.1+ (built into Windows), no installation needed.
# Optional RIFE 2x interpolation requires vspipe (Python + VapourSynth).
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Root    = $PSScriptRoot
$FFmpeg  = Join-Path $Root 'bin\ffmpeg.exe'
$Shaders = Join-Path $Root 'shaders'
$TempDir = Join-Path $env:TEMP 'Aniflow'
if (-not (Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir | Out-Null }

# Kodlama surerken sistemin uykuya gecmesini engellemek icin
Add-Type -Namespace Win32 -Name Power -MemberDefinition `
    '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
$ES_CONTINUOUS = [uint32]'0x80000000'; $ES_SYSTEM_REQUIRED = [uint32]'0x00000001'

# ================= Dil / Language =================
# Varsayilan Ingilizce; secim %APPDATA%\Aniflow.lang dosyasinda saklanir.
$LangFile = Join-Path $env:APPDATA 'Aniflow.lang'
$script:LangCode = 'en'
if (Test-Path $LangFile) {
    $lc = (Get-Content $LangFile -TotalCount 1 -ErrorAction SilentlyContinue)
    if ($lc) { $lc = $lc.Trim() }
    if ($lc -in @('en','tr')) { $script:LangCode = $lc }
}

$Strings = @{
en = @{
    Queue='Queue (drag files here; outputs are written next to the source):'
    Add='Add...'; Remove='Remove'; Clear='Clear'
    Mode='Shader mode:'; Encoder='Encoder:'; Quality='Quality (lower = better):'
    Scale='Output resolution:'; Audio='Audio:'; Finish='When done:'
    Extra='Advanced ffmpeg parameters (optional):'
    Deband='Deband (color banding)'; Denoise='Denoise (hqdn3d)'; Rife='RIFE 2x frame interpolation'
    Start='Start'; Cancel='Cancel'; Preview='Preview (10 s)'; Compare='Compare (side by side)'
    ScaleItems=@('2x (double input)','3x (triple input)','4x (quadruple - double modes full power)','1080p (Full HD)','1440p (QHD)','2160p (4K)')
    AudioItems=@('Copy (lossless)','AAC 192k','Opus 160k')
    FinishItems=@('Do nothing','Play sound','Sleep','Shut down (30 s)')
    EncoderItems=@('x264 (CPU, works everywhere)','x265 (CPU, works everywhere)','H.264 QSV (Intel GPU)','HEVC QSV (Intel GPU)','AV1 QSV (Intel Arc)','H.264 NVENC (NVIDIA GPU)','HEVC NVENC (NVIDIA GPU)','H.264 AMF (AMD GPU)','HEVC AMF (AMD GPU)')
    AllFiles='All files'
    Ready='Ready. Add videos to the queue; Preview/Compare use one file, Start runs the whole queue.'
    ReadyShort='Ready.'
    RootLog='Root folder: {0}'
    RifeOff='RIFE disabled: {0}'
    AiOff='AI mode disabled: {0}'
    QueueEmpty='Queue is empty - add files.'
    FfmpegMissing='ffmpeg not found: {0}'
    FileStatus='File {0}/{1}: {2}'
    FilePrefix='File {0}/{1} - '
    Speed='speed'; Left='left'
    QueueDone='Queue finished ({0} files).'
    QueueDoneLog='=== QUEUE FINISHED ==='
    Sleeping='Entering sleep mode...'
    Shutdown='SHUTDOWN in 30 s! Cancel with: shutdown /a'
    Done='DONE ({0:N1} MB) -> {1}'
    Cancelled='Cancelled.'
    ErrEncode='ERROR: encoding exited with code {0}. {1}'
    HintHw='If you picked a hardware encoder your GPU may not support it; try x264.'
    HintRife='The RIFE pipeline may have failed - check the vspipe lines in the log.'
    PrevFail='Preview/comparison failed - check the log.'
    SkipMissing='SKIPPED (not found): {0}'
    SkipAiScale='SKIPPED: pick 2x/3x/4x in AI mode.'
    AiScaleErr='In AI mode pick 2x/3x/4x as output resolution (p targets are not supported).'
    RifeIgnored='Note: RIFE is ignored in AI mode.'
    RifeBadName='WARNING: file name contains % & ^ ! - RIFE skipped for this file (cmd limitation).'
    AiDiskLog='AI upscale x{0}: ~{1} frames, estimated temp disk ~{2} GB ({3})'
    AiPhase1='AI 1/3: extracting frames...'
    AiPhase2='AI 2/3: upscaling {0} frames...'
    AiPhase2Tick='AI 2/3: frame {0}/{1}'
    AiPhase3='AI 3/3: encoding...'
    AiFail="ERROR: AI stage '{0}' exited with code {1}."
    AiFailStatus='AI job failed - check the log.'
    PrevPrep='Preparing preview...'
    AiPrevPrep='Preparing AI preview...'
    PrevLog='--- Preview: {0} (midpoint {1:N0}s)'
    AiPrevLog='--- AI Preview: {0} (midpoint {1:N0}s)'
    CmpPrep='Preparing comparison...'
    CmpNote='Note: comparison runs without RIFE.'
    CmpLog='--- Comparison: left=lanczos, right={0}'
    CmpAiErr='Comparison is not supported in AI mode; pick a shader mode.'
    CmpNoRes='Could not read input resolution.'
    PrevFirst='Add a file to the queue first.'
    NoRes='Could not read input resolution; pick a multiplier (2x/3x/4x).'
    Error='Error'
}
tr = @{
    Queue='Kuyruk (dosyalari buraya surukleyin, ciktilar kaynak klasore yazilir):'
    Add='Ekle...'; Remove='Kaldir'; Clear='Temizle'
    Mode='Shader modu:'; Encoder='Kodlayici:'; Quality='Kalite (dusuk = iyi):'
    Scale='Cikti cozunurlugu:'; Audio='Ses:'; Finish='Bitince:'
    Extra='Gelismis ffmpeg parametreleri (istege bagli):'
    Deband='Deband (renk bantlari)'; Denoise='Denoise (hqdn3d)'; Rife='RIFE 2x kare interpolasyonu'
    Start='Baslat'; Cancel='Iptal'; Preview='Onizleme (10 sn)'; Compare='Karsilastir (yan yana)'
    ScaleItems=@('2x (girdinin 2 kati)','3x (girdinin 3 kati)','4x (girdinin 4 kati - cift modlar tam guc)','1080p (Full HD)','1440p (QHD)','2160p (4K)')
    AudioItems=@('Kopyala (kayipsiz)','AAC 192k','Opus 160k')
    FinishItems=@('Hicbir sey yapma','Ses cal','Bilgisayari uyut','Bilgisayari kapat (30 sn)')
    EncoderItems=@('x264 (CPU, her yerde calisir)','x265 (CPU, her yerde calisir)','H.264 QSV (Intel GPU)','HEVC QSV (Intel GPU)','AV1 QSV (Intel Arc)','H.264 NVENC (NVIDIA GPU)','HEVC NVENC (NVIDIA GPU)','H.264 AMF (AMD GPU)','HEVC AMF (AMD GPU)')
    AllFiles='Tum dosyalar'
    Ready='Hazir. Kuyruga video ekleyin; Onizleme/Karsilastir tek dosyayla, Baslat tum kuyrukla calisir.'
    ReadyShort='Hazir.'
    RootLog='Kok klasor: {0}'
    RifeOff='RIFE devre disi: {0}'
    AiOff='AI modu devre disi: {0}'
    QueueEmpty='Kuyruk bos - dosya ekleyin.'
    FfmpegMissing='ffmpeg bulunamadi: {0}'
    FileStatus='Dosya {0}/{1}: {2}'
    FilePrefix='Dosya {0}/{1} - '
    Speed='hiz'; Left='kalan'
    QueueDone='Kuyruk tamamlandi ({0} dosya).'
    QueueDoneLog='=== KUYRUK TAMAMLANDI ==='
    Sleeping='Uyku moduna geciliyor...'
    Shutdown='KAPATMA 30 sn icinde! Iptal: shutdown /a'
    Done='TAMAM ({0:N1} MB) -> {1}'
    Cancelled='Iptal edildi.'
    ErrEncode='HATA: kodlama {0} kodu ile bitti. {1}'
    HintHw='Donanim kodlayici sectiyseniz bu GPU desteklemiyor olabilir; x264''u deneyin.'
    HintRife='RIFE hattinda hata olabilir - log''daki vspipe satirlarina bakin.'
    PrevFail='Onizleme/karsilastirma basarisiz - log''a bakin.'
    SkipMissing='ATLANDI (bulunamadi): {0}'
    SkipAiScale='ATLANDI: AI modunda 2x/3x/4x secin.'
    AiScaleErr='AI modunda cikti cozunurlugu olarak 2x/3x/4x secin (p hedefleri desteklenmez).'
    RifeIgnored='Not: RIFE, AI modunda yok sayilir.'
    RifeBadName='UYARI: dosya adinda % & ^ ! var - RIFE bu dosya icin atlandi (cmd kisiti).'
    AiDiskLog='AI upscale x{0}: ~{1} kare, gecici disk tahmini ~{2} GB ({3})'
    AiPhase1='AI 1/3: kareler cikariliyor...'
    AiPhase2='AI 2/3: {0} kare upscale ediliyor...'
    AiPhase2Tick='AI 2/3: kare {0}/{1}'
    AiPhase3='AI 3/3: kodlaniyor...'
    AiFail="HATA: AI asamasi '{0}' {1} kodu ile bitti."
    AiFailStatus='AI islemi basarisiz - log''a bakin.'
    PrevPrep='Onizleme hazirlaniyor...'
    AiPrevPrep='AI onizleme hazirlaniyor...'
    PrevLog='--- Onizleme: {0} (orta nokta {1:N0}. sn)'
    AiPrevLog='--- AI Onizleme: {0} (orta nokta {1:N0}. sn)'
    CmpPrep='Karsilastirma hazirlaniyor...'
    CmpNote='Not: karsilastirma RIFE olmadan yapilir.'
    CmpLog='--- Karsilastirma: sol=lanczos, sag={0}'
    CmpAiErr='Karsilastirma AI modunda desteklenmiyor; bir shader modu secin.'
    CmpNoRes='Girdi cozunurlugu okunamadi.'
    PrevFirst='Once kuyruga dosya ekleyin.'
    NoRes='Girdi cozunurlugu okunamadi; katsayi (2x/3x/4x) secin.'
    Error='Hata'
}
}
function L([string]$k) { $Strings[$script:LangCode][$k] }

# --- Shader modlari: ad -> zincirdeki dosyalar (sirali) ---
$Modes = [ordered]@{
    # Anime4K tekli modlar: A = genel, B = hafif bulanik kaynak, C = yuksek kaliteli/grenli kaynak
    'Anime4K Mode A (HQ)'                 = @('Anime4K_Clamp_Highlights.glsl','Anime4K_Restore_CNN_VL.glsl','Anime4K_Upscale_CNN_x2_VL.glsl')
    'Anime4K Mode B (HQ)'                 = @('Anime4K_Clamp_Highlights.glsl','Anime4K_Restore_CNN_Soft_VL.glsl','Anime4K_Upscale_CNN_x2_VL.glsl')
    'Anime4K Mode C (HQ)'                 = @('Anime4K_Clamp_Highlights.glsl','Anime4K_Upscale_Denoise_CNN_x2_VL.glsl')
    # Cift modlar: ikinci restore/upscale katmani (mpv'deki Ctrl kisayollariyla ayni zincirler)
    'Anime4K Mode A+A (HQ)'               = @('Anime4K_Clamp_Highlights.glsl','Anime4K_Restore_CNN_VL.glsl','Anime4K_Upscale_CNN_x2_VL.glsl','Anime4K_Restore_CNN_M.glsl','Anime4K_AutoDownscalePre_x2.glsl','Anime4K_AutoDownscalePre_x4.glsl','Anime4K_Upscale_CNN_x2_M.glsl')
    'Anime4K Mode B+B (HQ)'               = @('Anime4K_Clamp_Highlights.glsl','Anime4K_Restore_CNN_Soft_VL.glsl','Anime4K_Upscale_CNN_x2_VL.glsl','Anime4K_AutoDownscalePre_x2.glsl','Anime4K_AutoDownscalePre_x4.glsl','Anime4K_Restore_CNN_Soft_M.glsl','Anime4K_Upscale_CNN_x2_M.glsl')
    'Anime4K Mode C+A (HQ)'               = @('Anime4K_Clamp_Highlights.glsl','Anime4K_Upscale_Denoise_CNN_x2_VL.glsl','Anime4K_AutoDownscalePre_x2.glsl','Anime4K_AutoDownscalePre_x4.glsl','Anime4K_Restore_CNN_M.glsl','Anime4K_Upscale_CNN_x2_M.glsl')
    # Keskinlestirmeli varyantlar
    'Anime4K A+A + Adaptive Sharpen'      = @('Anime4K_Clamp_Highlights.glsl','Anime4K_Restore_CNN_VL.glsl','Anime4K_Upscale_CNN_x2_VL.glsl','Anime4K_Restore_CNN_M.glsl','Anime4K_AutoDownscalePre_x2.glsl','Anime4K_AutoDownscalePre_x4.glsl','Anime4K_Upscale_CNN_x2_M.glsl','adaptive-sharpen.glsl')
    'Anime4K Mode A + Adaptive Sharpen'   = @('Anime4K_Clamp_Highlights.glsl','Anime4K_Restore_CNN_VL.glsl','Anime4K_Upscale_CNN_x2_VL.glsl','adaptive-sharpen.glsl')
    # FSRCNNX (canli cekim / genel icerik)
    'FSRCNNX x2 16 (HQ) + Krig'           = @('FSRCNNX_x2_16-0-4-1.glsl','KrigBilateral.glsl')
    'FSRCNNX x2 8 (hizli) + Krig'         = @('FSRCNNX_x2_8-0-4-1.glsl','KrigBilateral.glsl')
    'FSRCNNX x2 16 + Krig + Sharpen'      = @('FSRCNNX_x2_16-0-4-1.glsl','KrigBilateral.glsl','adaptive-sharpen.glsl')
}

# --- Kodlayicilar: dizin sirasi EncoderItems dizisiyle esler (dil bagimsiz) ---
$EncoderCmds = @(
    { param($q) @('-c:v','libx264','-crf',"$q",'-preset','medium') }
    { param($q) @('-c:v','libx265','-crf',"$q",'-preset','medium') }
    { param($q) @('-c:v','h264_qsv','-global_quality',"$q") }
    { param($q) @('-c:v','hevc_qsv','-global_quality',"$q") }
    { param($q) @('-c:v','av1_qsv','-global_quality',"$q") }
    { param($q) @('-c:v','h264_nvenc','-rc','vbr','-cq',"$q",'-b:v','0') }
    { param($q) @('-c:v','hevc_nvenc','-rc','vbr','-cq',"$q",'-b:v','0') }
    { param($q) @('-c:v','h264_amf','-quality','quality','-rc','cqp','-qp_i',"$q",'-qp_p',"$q") }
    { param($q) @('-c:v','hevc_amf','-quality','quality','-rc','cqp','-qp_i',"$q",'-qp_p',"$q") }
)

# Ses secenekleri: dizin sirasi AudioItems ile esler.
# DIKKAT: bastaki virgul sart - @() blogu ic dizileri duzlestirir, ",@(...)"
# her satiri tek oge olarak korur (PS 5.1 tuzagi).
$AudioCmds = @(
    ,@('-c:a','copy')
    ,@('-c:a','aac','-b:a','192k')
    ,@('-c:a','libopus','-b:a','160k')
)

# Zincir dosyasini birlestir. Shaders klasoru yazilabilirse oraya, degilse
# (salt okunur USB vb.) TEMP'e yazar. Donus: zincirin tam yolu.
function Get-ChainFile([string]$modeName) {
    $files = $Modes[$modeName]
    foreach ($f in $files) {
        if (-not (Test-Path (Join-Path $Shaders $f))) {
            throw "Shader missing: $f (folder: $Shaders)"
        }
    }
    $safe  = ($modeName -replace '[^\w]+','_').Trim('_')
    $name  = "_chain_$safe.glsl"
    $src   = foreach ($f in $files) { Get-Item (Join-Path $Shaders $f) }
    $newest = ($src | Measure-Object -Property LastWriteTime -Maximum).Maximum
    foreach ($dir in @($Shaders, $TempDir)) {
        $chain = Join-Path $dir $name
        try {
            if (-not (Test-Path $chain) -or (Get-Item $chain).LastWriteTime -lt $newest) {
                $src | Get-Content | Set-Content -Path $chain -Encoding UTF8
            }
            return $chain
        } catch { continue }   # yazilamadi -> siradaki klasoru dene
    }
    throw 'Could not write the chain file to any folder.'
}

function Get-MediaInfo([string]$path) {
    # PS 5.1'de EAP=Stop iken 2>&1 stderr'i NativeCommandError'a cevirir;
    # ffmpeg -i tum bilgiyi stderr'e yazdigi icin burada gecici gevsetiyoruz
    $ErrorActionPreference = 'Continue'
    $info = & $FFmpeg -hide_banner -i $path 2>&1 | Out-String
    $r = @{ Duration = 0.0; W = 0; H = 0; Fps = 0.0 }
    if ($info -match 'Duration:\s*(\d+):(\d+):([\d.]+)') {
        $r.Duration = [int]$Matches[1]*3600 + [int]$Matches[2]*60 + [double]$Matches[3]
    }
    if ($info -match 'Stream.*Video.*?\s(\d{2,5})x(\d{2,5})') {
        $r.W = [int]$Matches[1]; $r.H = [int]$Matches[2]
    }
    if ($info -match '(\d+(?:\.\d+)?)\s*fps') { $r.Fps = [double]$Matches[1] }
    return $r
}

# Olcek secimine gore hedef. Katsayilar ifadeyle ("iw*2"), hedef cozunurlukler
# en-boy oranina gore sayiyla cozulur (cift sayiya yuvarlanir).
# NumW/NumH: karsilastirma filtresi icin somut sayilar (ifade kullanamaz).
function Resolve-Target([string]$sel, [int]$inW, [int]$inH) {
    if ($sel -match '^(\d)x') {
        $n = [int]$Matches[1]
        return @{ W = "iw*$n"; H = "ih*$n"; NumW = $inW*$n; NumH = $inH*$n; Tag = "${n}x" }
    }
    if ($sel -match '(\d{3,4})p') {
        $t = [int]$Matches[1]
        if ($inW -le 0 -or $inH -le 0) { throw (L 'NoRes') }
        $w = [Math]::Round($inW * $t / $inH / 2) * 2
        return @{ W = "$w"; H = "$t"; NumW = $w; NumH = $t; Tag = "${t}p" }
    }
    return @{ W = 'iw*2'; H = 'ih*2'; NumW = $inW*2; NumH = $inH*2; Tag = '2x' }
}

# Start-Process -ArgumentList PS 5.1'de ogeleri tirnaklamadan birlestirir;
# bosluk iceren yollari elle tirnakla
function Quote-Args($list) {
    $list | ForEach-Object { if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ } }
}

# Gelismis parametre kutusunu ffmpeg argumanlarina cevirir; cift tirnakli
# obekler tek arguman sayilir (or: -metadata title="Bolum 1" -> title=Bolum 1)
function Split-ExtraArgs([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return @() }
    [regex]::Matches($s, '(?:[^\s"]+|"[^"]*")+') | ForEach-Object { $_.Value -replace '"','' }
}

# --- RIFE 2x kare interpolasyonu (istege bagli) ---
# Video once vspipe+VapourSynth'te RIFE ile 2x fps'e cikarilir, y4m olarak
# ffmpeg'e borulanir; shader zinciri ve kodlama ffmpeg tarafinda ayni kalir.
$VapourDir = Join-Path $Root 'vapoursynth'
$VpyScript = Join-Path $VapourDir 'rife_encode.vpy'

function Find-RifeSupport {
    $r = @{ Ok = $false; Vspipe = ''; RifeDll = ''; ModelDir = ''; SourceDll = ''; Reason = '' }
    $vs = Get-Command vspipe.exe -ErrorAction SilentlyContinue
    if (-not $vs) { $r.Reason = 'vspipe.exe not on PATH (needs Python + "pip install vapoursynth")'; return $r }
    $r.Vspipe = $vs.Source
    # RIFE eklentisi/modeli: once proje klasoru, sonra mpv kurulumu
    foreach ($d in @($VapourDir, (Join-Path $env:APPDATA 'mpv\vapoursynth'))) {
        $dll = Join-Path $d 'librife_windows_x86-64.dll'
        $mod = Join-Path $d 'models\rife-v4.6_ensembleFalse'
        if ((Test-Path $dll) -and (Test-Path $mod)) { $r.RifeDll = $dll; $r.ModelDir = Join-Path $d 'models'; break }
    }
    if (-not $r.RifeDll) { $r.Reason = 'RIFE plugin/model not found (run setup.ps1)'; return $r }
    $bs = Join-Path $VapourDir 'bestsource.dll'
    if (-not (Test-Path $bs)) { $r.Reason = 'bestsource.dll missing (run setup.ps1)'; return $r }
    $r.SourceDll = $bs
    if (-not (Test-Path $VpyScript)) { $r.Reason = 'rife_encode.vpy missing'; return $r }
    $r.Ok = $true
    return $r
}
$script:Rife = Find-RifeSupport
$script:CurFps = 0.0

# --- AI upscale: Real-ESRGAN animevideov3 (offline, ncnn Vulkan) ---
# Boru hatti 3 fazli: ffmpeg kare cikarir -> realesrgan klasoru isler -> ffmpeg kodlar.
# Ara format PNG: kayipsiz VE renk matrisi/aralik belirsizligi yok (jpg 601-full
# varsayimi 709 kaynaklarda mor/karanlik tonlari kaydiriyor, bloklari belirginlestiriyordu).
$AiDir  = Join-Path $Root 'realesrgan'
$AiExe  = Join-Path $AiDir 'realesrgan-ncnn-vulkan.exe'
$AiModeName = 'AI: Real-ESRGAN animevideov3 (offline)'

function Find-AiSupport {
    $r = @{ Ok = $false; Reason = '' }
    if (-not (Test-Path $AiExe)) { $r.Reason = 'realesrgan-ncnn-vulkan.exe missing (run setup.ps1)'; return $r }
    if (-not (Test-Path (Join-Path $AiDir 'models\realesr-animevideov3-x2.param'))) {
        $r.Reason = 'animevideov3 model missing (run setup.ps1)'; return $r
    }
    $r.Ok = $true
    return $r
}
$script:Ai = Find-AiSupport

if ($SelfTest) {
    'ffmpeg: ' + (Test-Path $FFmpeg)
    foreach ($m in $Modes.Keys) {
        $c = Get-ChainFile $m
        '{0} -> {1} ({2:N0} KB)' -f $m, $c, ((Get-Item $c).Length/1KB)
    }
    foreach ($s in @('2x (double input)','4x (quadruple)','1080p (Full HD)','1440p (QHD)','2160p (4K)')) {
        $t = Resolve-Target $s 1920 1080
        '{0} [1920x1080] -> w={1} h={2} tag={3}' -f $s, $t.W, $t.H, $t.Tag
    }
    'lang: ' + $script:LangCode
    'ai-support: {0}{1}' -f $script:Ai.Ok, $(if (-not $script:Ai.Ok) { ' (' + $script:Ai.Reason + ')' } else { '' })
    'rife-support: {0}{1}' -f $script:Rife.Ok, $(if (-not $script:Rife.Ok) { ' (' + $script:Rife.Reason + ')' } else { '' })
    if ($script:Rife.Ok) {
        # input verilmeyince vpy 48 karelik BlankClip uretir; "Frames: 96" gorunmesi
        # iki DLL'in yuklendigini ve RIFE'in GPU'da 2x kurulabildigini kanitlar
        $ErrorActionPreference = 'Continue'
        $o = & $script:Rife.Vspipe --info -a "rife_dll=$($script:Rife.RifeDll)" -a "source_dll=$($script:Rife.SourceDll)" -a "model_dir=$($script:Rife.ModelDir)" $VpyScript 2>&1 | Out-String
        $ErrorActionPreference = 'Stop'
        'rife-vpy: ' + $(if ($o -match 'Frames:\s*96') { 'OK (48 -> 96 frames)' } else { 'ERROR: ' + $o.Trim() })
    }
    exit 0
}

# ================= GUI =================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Aniflow v2 - Anime4K / FSRCNNX Video Upscaler - Daily Dana'
$form.Size = New-Object System.Drawing.Size(690, 756)
$form.MinimumSize = $form.Size
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

function Add-Label($text, $x, $y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.AutoSize = $true; $form.Controls.Add($l); return $l
}

# --- Kuyruk ---
$lblQueue = Add-Label '' 15 15
$lst = New-Object System.Windows.Forms.ListBox
$lst.Location = New-Object System.Drawing.Point(15, 38)
$lst.Size = New-Object System.Drawing.Size(550, 112)
$lst.Anchor = 'Top,Left,Right'
$lst.AllowDrop = $true
$lst.HorizontalScrollbar = $true
$form.Controls.Add($lst)

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Location = New-Object System.Drawing.Point(575, 38)
$btnAdd.Size = New-Object System.Drawing.Size(85, 28); $btnAdd.Anchor = 'Top,Right'
$form.Controls.Add($btnAdd)
$btnDel = New-Object System.Windows.Forms.Button
$btnDel.Location = New-Object System.Drawing.Point(575, 72)
$btnDel.Size = New-Object System.Drawing.Size(85, 28); $btnDel.Anchor = 'Top,Right'
$form.Controls.Add($btnDel)
$btnClr = New-Object System.Windows.Forms.Button
$btnClr.Location = New-Object System.Drawing.Point(575, 106)
$btnClr.Size = New-Object System.Drawing.Size(85, 28); $btnClr.Anchor = 'Top,Right'
$form.Controls.Add($btnClr)

# Dil secici / language picker
$cmbLang = New-Object System.Windows.Forms.ComboBox
$cmbLang.Location = New-Object System.Drawing.Point(575, 140)
$cmbLang.Size = New-Object System.Drawing.Size(85, 24)
$cmbLang.DropDownStyle = 'DropDownList'; $cmbLang.Anchor = 'Top,Right'
@('English','Turkce') | ForEach-Object { [void]$cmbLang.Items.Add($_) }
$cmbLang.SelectedIndex = $(if ($script:LangCode -eq 'tr') { 1 } else { 0 })
$form.Controls.Add($cmbLang)

# --- Mod / kodlayici / kalite ---
$lblMode = Add-Label '' 15 162
$cmbMode = New-Object System.Windows.Forms.ComboBox
$cmbMode.Location = New-Object System.Drawing.Point(15, 185)
$cmbMode.Size = New-Object System.Drawing.Size(250, 24)
$cmbMode.DropDownStyle = 'DropDownList'
$Modes.Keys | ForEach-Object { [void]$cmbMode.Items.Add($_) }
if ($script:Ai.Ok) { [void]$cmbMode.Items.Add($AiModeName) }
$cmbMode.SelectedIndex = 0
$form.Controls.Add($cmbMode)

$lblEnc = Add-Label '' 285 162
$cmbEnc = New-Object System.Windows.Forms.ComboBox
$cmbEnc.Location = New-Object System.Drawing.Point(285, 185)
$cmbEnc.Size = New-Object System.Drawing.Size(215, 24)
$cmbEnc.DropDownStyle = 'DropDownList'
$form.Controls.Add($cmbEnc)

$lblQ = Add-Label '' 520 162
$numQ = New-Object System.Windows.Forms.NumericUpDown
$numQ.Location = New-Object System.Drawing.Point(520, 185)
$numQ.Size = New-Object System.Drawing.Size(70, 24)
$numQ.Minimum = 1; $numQ.Maximum = 51; $numQ.Value = 18
$form.Controls.Add($numQ)

# --- Cozunurluk / ses / bitince ---
$lblScale = Add-Label '' 15 220
$cmbScale = New-Object System.Windows.Forms.ComboBox
$cmbScale.Location = New-Object System.Drawing.Point(15, 243)
$cmbScale.Size = New-Object System.Drawing.Size(250, 24)
$cmbScale.DropDownStyle = 'DropDownList'
$form.Controls.Add($cmbScale)

$lblAudio = Add-Label '' 285 220
$cmbAudio = New-Object System.Windows.Forms.ComboBox
$cmbAudio.Location = New-Object System.Drawing.Point(285, 243)
$cmbAudio.Size = New-Object System.Drawing.Size(150, 24)
$cmbAudio.DropDownStyle = 'DropDownList'
$form.Controls.Add($cmbAudio)

$lblFinish = Add-Label '' 455 220
$cmbFinish = New-Object System.Windows.Forms.ComboBox
$cmbFinish.Location = New-Object System.Drawing.Point(455, 243)
$cmbFinish.Size = New-Object System.Drawing.Size(205, 24)
$cmbFinish.DropDownStyle = 'DropDownList'
$form.Controls.Add($cmbFinish)

# --- Ek filtreler ---
$chkDeband = New-Object System.Windows.Forms.CheckBox
$chkDeband.Location = New-Object System.Drawing.Point(15, 280)
$chkDeband.AutoSize = $true
$form.Controls.Add($chkDeband)
$chkDenoise = New-Object System.Windows.Forms.CheckBox
$chkDenoise.Location = New-Object System.Drawing.Point(210, 280)
$chkDenoise.AutoSize = $true
$form.Controls.Add($chkDenoise)
$chkRife = New-Object System.Windows.Forms.CheckBox
$chkRife.Location = New-Object System.Drawing.Point(405, 280)
$chkRife.AutoSize = $true
$form.Controls.Add($chkRife)

# --- Dugmeler ---
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Location = New-Object System.Drawing.Point(15, 312)
$btnStart.Size = New-Object System.Drawing.Size(115, 32)
$form.Controls.Add($btnStart)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Location = New-Object System.Drawing.Point(140, 312)
$btnCancel.Size = New-Object System.Drawing.Size(115, 32)
$btnCancel.Enabled = $false
$form.Controls.Add($btnCancel)

$btnPrev = New-Object System.Windows.Forms.Button
$btnPrev.Location = New-Object System.Drawing.Point(285, 312)
$btnPrev.Size = New-Object System.Drawing.Size(150, 32)
$form.Controls.Add($btnPrev)

$btnCmp = New-Object System.Windows.Forms.Button
$btnCmp.Location = New-Object System.Drawing.Point(445, 312)
$btnCmp.Size = New-Object System.Drawing.Size(170, 32)
$form.Controls.Add($btnCmp)

# --- Gelismis parametreler ---
$lblExtra = Add-Label '' 15 354
$txtExtra = New-Object System.Windows.Forms.TextBox
$txtExtra.Location = New-Object System.Drawing.Point(330, 351)
$txtExtra.Size = New-Object System.Drawing.Size(330, 24)
$txtExtra.Anchor = 'Top,Left,Right'
$form.Controls.Add($txtExtra)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = New-Object System.Drawing.Point(15, 392)
$bar.Size = New-Object System.Drawing.Size(645, 22)
$bar.Anchor = 'Top,Left,Right'
$form.Controls.Add($bar)

$lblStatus = Add-Label '' 15 420

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(15, 446)
$txtLog.Size = New-Object System.Drawing.Size(645, 250)
$txtLog.Anchor = 'Top,Bottom,Left,Right'
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($txtLog)

function Log([string]$msg) {
    $txtLog.AppendText(('[{0:HH:mm:ss}] {1}{2}' -f (Get-Date), $msg, [Environment]::NewLine))
}

# Tum metinleri secili dile uygular; comboset icerigini secim korunarak yeniler
function Set-UiLanguage {
    $lblQueue.Text = L 'Queue'; $btnAdd.Text = L 'Add'; $btnDel.Text = L 'Remove'; $btnClr.Text = L 'Clear'
    $lblMode.Text = L 'Mode'; $lblEnc.Text = L 'Encoder'; $lblQ.Text = L 'Quality'
    $lblScale.Text = L 'Scale'; $lblAudio.Text = L 'Audio'; $lblFinish.Text = L 'Finish'
    $lblExtra.Text = L 'Extra'
    $chkDeband.Text = L 'Deband'; $chkDenoise.Text = L 'Denoise'; $chkRife.Text = L 'Rife'
    $btnStart.Text = L 'Start'; $btnCancel.Text = L 'Cancel'; $btnPrev.Text = L 'Preview'; $btnCmp.Text = L 'Compare'
    foreach ($pair in @(@($cmbEnc,'EncoderItems'), @($cmbScale,'ScaleItems'), @($cmbAudio,'AudioItems'), @($cmbFinish,'FinishItems'))) {
        $cmb = $pair[0]
        $i = $cmb.SelectedIndex
        $cmb.Items.Clear()
        (L $pair[1]) | ForEach-Object { [void]$cmb.Items.Add($_) }
        $cmb.SelectedIndex = $(if ($i -ge 0 -and $i -lt $cmb.Items.Count) { $i } else { 0 })
    }
    if (-not $btnCancel.Enabled) { $lblStatus.Text = L 'ReadyShort' }
}
Set-UiLanguage
$cmbLang.Add_SelectedIndexChanged({
    $script:LangCode = @('en','tr')[$cmbLang.SelectedIndex]
    try { Set-Content -Path $LangFile -Value $script:LangCode -Encoding ASCII } catch {}
    Set-UiLanguage
})

# --- Durum ---
$state = @{
    Proc = $null; Duration = 0; ProgFile = Join-Path $TempDir 'progress.txt'
    ErrFile = Join-Path $TempDir 'stderr.txt'; ErrOffset = 0; OutPath = ''
    Queue = New-Object System.Collections.ArrayList; Index = 0
    Kind = 'queue'   # queue | preview | compare
    Cancelled = $false; RifeJob = $false
    Ai = $null; AiActive = $false   # AI modu faz durumu (extract | upscale | encode)
}

function Add-Files($paths) {
    foreach ($p in $paths) {
        if (Test-Path $p -PathType Container) {
            Get-ChildItem $p -File | Where-Object Extension -match '\.(mkv|mp4|avi|webm|mov|ts|m2ts|wmv)$' |
                ForEach-Object { if (-not $lst.Items.Contains($_.FullName)) { [void]$lst.Items.Add($_.FullName) } }
        } elseif (-not $lst.Items.Contains($p)) { [void]$lst.Items.Add($p) }
    }
}

$lst.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
$lst.Add_DragDrop({ Add-Files ($_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) })
$btnAdd.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Video|*.mkv;*.mp4;*.avi;*.webm;*.mov;*.ts;*.m2ts;*.wmv|{0}|*.*' -f (L 'AllFiles')
    $dlg.Multiselect = $true
    if ($dlg.ShowDialog() -eq 'OK') { Add-Files $dlg.FileNames }
})
$btnDel.Add_Click({ if ($lst.SelectedIndex -ge 0) { $lst.Items.RemoveAt($lst.SelectedIndex) } })
$btnClr.Add_Click({ $lst.Items.Clear() })

function Set-Busy([bool]$busy) {
    $btnStart.Enabled = -not $busy; $btnPrev.Enabled = -not $busy; $btnCmp.Enabled = -not $busy
    $btnCancel.Enabled = $busy
    if ($busy) { [void][Win32.Power]::SetThreadExecutionState($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED) }
    else       { [void][Win32.Power]::SetThreadExecutionState($ES_CONTINUOUS) }
}

# RIFE isinde $state.Proc cmd.exe'dir; .Kill() yalniz cmd'yi oldurur, vspipe ile
# ffmpeg yetim kalip kodlamaya devam eder. taskkill /T tum agaci indirir.
# (Start-Process: EAP=Stop altinda taskkill'in stderr'i hata sayilmasin diye)
function Stop-EncodeTree {
    if ($state.Proc -and -not $state.Proc.HasExited) {
        Start-Process -FilePath 'taskkill.exe' -ArgumentList "/PID $($state.Proc.Id) /T /F" -WindowStyle Hidden
    }
}

# Tek bir kodlama isi baslatir. $trim: @(ss, t) veya $null; $fc: filter_complex dizesi veya $null
# RIFE isaretliyse (ve $fc yoksa) video vspipe'tan RIFE'li y4m olarak gelir,
# ses/altyazi/bolumler ikinci girdi olarak orijinal dosyadan alinir.
function Start-Job2([string]$in, [string]$out, $trim, $fc, [string]$vfChain) {
    $chainDir = Split-Path $vfChain -Parent
    $useRife = $chkRife.Checked -and $script:Rife.Ok -and -not $fc
    if ($useRife -and $in -match '[%!^&]') {
        # cmd.exe bu karakterleri tirnak icinde bile ozel isler; riske girme
        Log (L 'RifeBadName')
        $useRife = $false
    }
    $state.RifeJob = $useRife

    $ffArgs = @('-y','-hide_banner','-loglevel','warning','-init_hw_device','vulkan')
    if ($useRife) {
        $ffArgs += @('-i','pipe:0')
        if ($trim) { $ffArgs += @('-ss',"$($trim[0])",'-t',"$($trim[1])") }   # ses girdisini ayni araliga kirpar
        $ffArgs += @('-i', $in)
    } else {
        if ($trim) { $ffArgs += @('-ss',"$($trim[0])",'-t',"$($trim[1])") }
        $ffArgs += @('-i', $in)
    }
    if ($fc) {
        $ffArgs += @('-filter_complex', $fc, '-an')
    } else {
        # hqdn3d shader zincirinden ONCE calisir (dusuk cozunurlukte hem dogru hem hizli)
        $pre = ''
        if ($chkDenoise.Checked) { $pre = 'hqdn3d=1.5:1.5:6:6,' }
        $deband = ''
        if ($chkDeband.Checked) { $deband = ':deband=true' }
        $vf = "${pre}libplacebo=w=$($script:tgt.W):h=$($script:tgt.H):custom_shader_path=$(Split-Path $vfChain -Leaf)$deband"
        $ffArgs += @('-vf', $vf)
        # tum ses/altyazi/ek dosyalar korunur; video yalnizca ilk akis (kapak resimleri disarida)
        if ($useRife) {
            $ffArgs += @('-map','0:v:0','-map','1:a?','-map','1:s?','-map','1:d?','-map','1:t?','-map_metadata','1','-map_chapters','1')
        } else {
            $ffArgs += @('-map','0:v:0','-map','0:a?','-map','0:s?','-map','0:d?','-map','0:t?')
        }
        $ffArgs += & $EncoderCmds[$cmbEnc.SelectedIndex] ([int]$numQ.Value)
        $ffArgs += $AudioCmds[$cmbAudio.SelectedIndex]
        # -c:d copy: data akislari (or. Dolby Vision RPU) da tasinir
        $ffArgs += @('-c:s','copy','-c:d','copy','-c:t','copy')
        $ffArgs += Split-ExtraArgs $txtExtra.Text
    }
    $ffArgs += @('-progress', $state.ProgFile, $out)

    $state.ErrOffset = 0
    Remove-Item $state.ProgFile, $state.ErrFile -ErrorAction SilentlyContinue
    $state.OutPath = $out
    if ($useRife) {
        $vsArgs = @($script:Rife.Vspipe,'-c','y4m',
            '-a',"input=$in",
            '-a',"rife_dll=$($script:Rife.RifeDll)",
            '-a',"source_dll=$($script:Rife.SourceDll)",
            '-a',"model_dir=$($script:Rife.ModelDir)")
        if ($script:CurFps -gt 0) {
            $vsArgs += @('-a',"fps_num=$([int][Math]::Round($script:CurFps*1000))",'-a','fps_den=1000')
        }
        if ($trim) { $vsArgs += @('-a',"start_sec=$($trim[0])",'-a',"dur_sec=$($trim[1])") }
        $vsArgs += @($VpyScript,'-')
        # Iki sureci tek cmd altinda borula: tek tutamac, cikis kodu = ffmpeg'inki,
        # iki surecin stderr'i de ayni dosyaya akar (mevcut log/timer duzeni bozulmaz)
        $cmdLine = '/s /c "' + ((Quote-Args $vsArgs) -join ' ') + ' | ' + ((Quote-Args (@($FFmpeg) + $ffArgs)) -join ' ') + '"'
        Log ('cmd ' + $cmdLine)
        $state.Proc = Start-Process -FilePath $env:ComSpec -ArgumentList $cmdLine `
            -WorkingDirectory $chainDir -WindowStyle Hidden -PassThru `
            -RedirectStandardError $state.ErrFile
    } else {
        Log ('ffmpeg ' + ((Quote-Args $ffArgs) -join ' '))
        $state.Proc = Start-Process -FilePath $FFmpeg -ArgumentList (Quote-Args $ffArgs) `
            -WorkingDirectory $chainDir -WindowStyle Hidden -PassThru `
            -RedirectStandardError $state.ErrFile
    }
    # PS 5.1 tuhafligi: handle'a islem bitmeden erisilmezse ExitCode bos doner
    $null = $state.Proc.Handle
    $timer.Start()
}

# --- AI upscale boru hatti (3 faz, timer uzerinden ilerler) ---
function Clear-AiTemp {
    if ($state.Ai) {
        foreach ($d in @($state.Ai.InDir, $state.Ai.OutDir)) {
            if ($d) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Start-AiJob([string]$in, [string]$out, $trim) {
    $fps = $script:CurFps
    if ($fps -le 0) { $fps = 23.976 }
    $sel = $cmbScale.SelectedItem
    if ($sel -notmatch '^([234])x') { throw (L 'AiScaleErr') }
    $state.Ai = @{
        Phase = 'extract'; In = $in; Out = $out; Fps = $fps; Scale = [int]$Matches[1]
        InDir = Join-Path $TempDir 'ai_in'; OutDir = Join-Path $TempDir 'ai_out'
        Trim = $trim; Total = 0
    }
    foreach ($d in @($state.Ai.InDir, $state.Ai.OutDir)) {
        Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $d | Out-Null
    }
    $state.AiActive = $true
    if ($chkRife.Checked) { Log (L 'RifeIgnored') }
    $dur = if ($trim) { [double]$trim[1] } else { $state.Duration }
    $frames = [int]($dur * $fps)
    # kaba tahmin (PNG, 1080p temel): giris ~2.5 MB/kare, cikis ~2.5*olcek^2
    $estGB = [Math]::Round($frames * 2.5 * (1 + $state.Ai.Scale * $state.Ai.Scale) / 1024, 1)
    Log ((L 'AiDiskLog') -f $state.Ai.Scale, $frames, $estGB, $TempDir)
    Invoke-AiPhase
}

function Invoke-AiPhase {
    $ai = $state.Ai
    $state.ErrOffset = 0
    Remove-Item $state.ProgFile, $state.ErrFile -ErrorAction SilentlyContinue
    switch ($ai.Phase) {
        'extract' {
            # PNG cikti: ffmpeg kaynak matris/araligini dogru bilerek RGB'ye cevirir;
            # -fps_mode cfr: VFR kaynaklarda kare/ses senkronu icin sabit kare hizi
            $a = @('-y','-hide_banner','-loglevel','warning')
            if ($ai.Trim) { $a += @('-ss',"$($ai.Trim[0])",'-t',"$($ai.Trim[1])") }
            $a += @('-i',$ai.In,'-fps_mode','cfr','-r',"$($ai.Fps)",
                    '-progress',$state.ProgFile,(Join-Path $ai.InDir 'f%08d.png'))
            $lblStatus.Text = L 'AiPhase1'
            Log ('ffmpeg ' + ((Quote-Args $a) -join ' '))
            $state.Proc = Start-Process -FilePath $FFmpeg -ArgumentList (Quote-Args $a) `
                -WindowStyle Hidden -PassThru -RedirectStandardError $state.ErrFile
        }
        'upscale' {
            $ai.Total = [IO.Directory]::GetFiles($ai.InDir, '*.png').Count
            $a = @('-i',$ai.InDir,'-o',$ai.OutDir,'-n','realesr-animevideov3','-s',"$($ai.Scale)",'-f','png')
            $lblStatus.Text = (L 'AiPhase2') -f $ai.Total
            Log ('realesrgan ' + ((Quote-Args $a) -join ' '))
            $state.Proc = Start-Process -FilePath $AiExe -ArgumentList (Quote-Args $a) `
                -WorkingDirectory $AiDir -WindowStyle Hidden -PassThru -RedirectStandardError $state.ErrFile
        }
        'encode' {
            $a = @('-y','-hide_banner','-loglevel','warning','-framerate',"$($ai.Fps)",'-i',(Join-Path $ai.OutDir 'f%08d.png'))
            if ($ai.Trim) { $a += @('-ss',"$($ai.Trim[0])",'-t',"$($ai.Trim[1])") }   # ses girdisini ayni araliga kirpar
            $a += @('-i',$ai.In)
            $a += @('-map','0:v:0','-map','1:a?','-map','1:s?','-map','1:d?','-map','1:t?','-map_metadata','1','-map_chapters','1')
            $a += & $EncoderCmds[$cmbEnc.SelectedIndex] ([int]$numQ.Value)
            # PNG (RGB) -> standart tv-range bt709 YUV; kaynak matris tahmini gerekmez.
            # trc/primaries de bt709 etiketlenir (PNG'nin sRGB etiketi sizmasin)
            $a += @('-vf','scale=out_range=tv:out_color_matrix=bt709,format=yuv420p',
                    '-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709')
            $a += $AudioCmds[$cmbAudio.SelectedIndex]
            $a += @('-c:s','copy','-c:d','copy','-c:t','copy')
            $a += Split-ExtraArgs $txtExtra.Text
            $a += @('-shortest','-progress',$state.ProgFile,$ai.Out)
            $lblStatus.Text = L 'AiPhase3'
            Log ('ffmpeg ' + ((Quote-Args $a) -join ' '))
            $state.OutPath = $ai.Out
            $state.Proc = Start-Process -FilePath $FFmpeg -ArgumentList (Quote-Args $a) `
                -WindowStyle Hidden -PassThru -RedirectStandardError $state.ErrFile
        }
    }
    $null = $state.Proc.Handle
    $timer.Start()
}

# extract/upscale fazlari bitince siradaki faza gecer; encode fazi Complete-File'a duser
function Step-AiJob {
    $timer.Stop()
    if (Test-Path $state.ErrFile) {
        $errText = Get-Content $state.ErrFile -Raw -ErrorAction SilentlyContinue
        if ($errText -and $errText.Length -gt $state.ErrOffset) { Log ($errText.Substring($state.ErrOffset).Trim()) }
    }
    $code = $state.Proc.ExitCode
    $state.Proc = $null
    if ($null -eq $code) { $code = 0 }   # handle tuhafligi; hata varsa sonraki faz zaten yakalar
    if ($state.Cancelled) {
        $state.Cancelled = $false; $state.AiActive = $false
        Clear-AiTemp
        Log (L 'Cancelled')
        Set-Busy $false; $lblStatus.Text = L 'Cancelled'
        return
    }
    if ($code -ne 0) {
        $failedPhase = $state.Ai.Phase
        $state.AiActive = $false
        Clear-AiTemp
        Log ((L 'AiFail') -f $failedPhase, $code)
        if ($state.Kind -eq 'queue') { Skip-Next }
        else { Set-Busy $false; $lblStatus.Text = L 'AiFailStatus' }
        return
    }
    switch ($state.Ai.Phase) {
        'extract' { $state.Ai.Phase = 'upscale'; Invoke-AiPhase }
        'upscale' { $state.Ai.Phase = 'encode';  Invoke-AiPhase }
    }
}

function Start-QueueItem {
    $in = $state.Queue[$state.Index]
    if (-not (Test-Path $in)) { Log ((L 'SkipMissing') -f $in); Skip-Next; return }
    $mi = Get-MediaInfo $in
    $state.Duration = $mi.Duration
    $script:CurFps = $mi.Fps
    $d = Split-Path $in -Parent
    $n = [IO.Path]::GetFileNameWithoutExtension($in)
    if ($cmbMode.SelectedItem -eq $AiModeName) {
        if ($cmbScale.SelectedItem -notmatch '^([234])x') { Log (L 'SkipAiScale'); Skip-Next; return }
        $s = [int]$Matches[1]
        $out = Join-Path $d ('{0}_ai{1}x_upscale.mkv' -f $n, $s)
        $lblStatus.Text = (L 'FileStatus') -f ($state.Index+1), $state.Queue.Count, (Split-Path $in -Leaf)
        Log ('--- [{0}/{1}] {2} ({3}x{4}, {5:N1} s) -> AI x{6}' -f ($state.Index+1), $state.Queue.Count, (Split-Path $in -Leaf), $mi.W, $mi.H, $mi.Duration, $s)
        Start-AiJob $in $out $null
        return
    }
    $chain = Get-ChainFile $cmbMode.SelectedItem
    $script:tgt = Resolve-Target $cmbScale.SelectedItem $mi.W $mi.H
    $rifeTag = ''
    if ($chkRife.Checked -and $script:Rife.Ok) { $rifeTag = '_rife' }
    $out = Join-Path $d ('{0}_{1}{2}_upscale.mkv' -f $n, $script:tgt.Tag, $rifeTag)
    $lblStatus.Text = (L 'FileStatus') -f ($state.Index+1), $state.Queue.Count, (Split-Path $in -Leaf)
    Log ('--- [{0}/{1}] {2} ({3}x{4}, {5:N1} s) -> {6} x {7}' -f ($state.Index+1), $state.Queue.Count, (Split-Path $in -Leaf), $mi.W, $mi.H, $mi.Duration, $script:tgt.W, $script:tgt.H)
    Start-Job2 $in $out $null $null $chain
}

function Skip-Next {
    $state.Index++
    if ($state.Index -lt $state.Queue.Count) { Start-QueueItem }
    else { Complete-Queue }
}

function Complete-Queue {
    Set-Busy $false
    $bar.Value = 100
    $lblStatus.Text = (L 'QueueDone') -f $state.Queue.Count
    Log (L 'QueueDoneLog')
    switch ($cmbFinish.SelectedIndex) {
        1 { [System.Media.SystemSounds]::Asterisk.Play() }
        2 { Log (L 'Sleeping'); & rundll32.exe powrprof.dll,SetSuspendState 0,1,0 }
        3 { Log (L 'Shutdown'); & shutdown.exe /s /t 30 }
    }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500

function Complete-File {
    $timer.Stop()
    if (Test-Path $state.ErrFile) {
        $errText = Get-Content $state.ErrFile -Raw -ErrorAction SilentlyContinue
        if ($errText -and $errText.Length -gt $state.ErrOffset) { Log ($errText.Substring($state.ErrOffset).Trim()) }
    }
    $code = $state.Proc.ExitCode
    $state.Proc = $null
    if ($state.AiActive) { Clear-AiTemp; $state.AiActive = $false }   # encode fazi bitti, gecici kareleri sil
    # ExitCode bos donerse (handle gec erisim) cikti dosyasi + progress=end'e bak
    if ($null -eq $code) {
        $prog = Get-Content $state.ProgFile -Raw -ErrorAction SilentlyContinue
        if ($prog -match 'progress=end' -and (Test-Path $state.OutPath)) { $code = 0 }
    }
    $ok = ($code -eq 0 -and (Test-Path $state.OutPath))
    if ($ok) {
        $mb = (Get-Item $state.OutPath).Length / 1MB
        Log ((L 'Done') -f $mb, $state.OutPath)
    } elseif ($code -eq -1 -or $state.Cancelled) {
        $state.Cancelled = $false
        Log (L 'Cancelled')
        Set-Busy $false; $lblStatus.Text = L 'Cancelled'
        return
    } else {
        $hint = L 'HintHw'
        if ($state.RifeJob) { $hint = L 'HintRife' }
        Log ((L 'ErrEncode') -f $code, $hint)
    }
    switch ($state.Kind) {
        'queue'   { Skip-Next }
        default   {
            Set-Busy $false
            if ($ok) { $lblStatus.Text = L 'ReadyShort'; Start-Process $state.OutPath }
            else     { $lblStatus.Text = L 'PrevFail' }
        }
    }
}

$timer.Add_Tick({
    if (Test-Path $state.ErrFile) {
        $errText = Get-Content $state.ErrFile -Raw -ErrorAction SilentlyContinue
        if ($errText -and $errText.Length -gt $state.ErrOffset) {
            Log ($errText.Substring($state.ErrOffset).Trim())
            $state.ErrOffset = $errText.Length
        }
    }
    if ($state.AiActive -and $state.Ai.Phase -eq 'upscale' -and $state.Ai.Total -gt 0) {
        # upscale fazinda ffmpeg -progress yok; cikti klasorundeki kare sayisini say
        $done = [IO.Directory]::GetFiles($state.Ai.OutDir, '*.png').Count
        $bar.Value = [Math]::Min(100, [int]($done / $state.Ai.Total * 100))
        $lblStatus.Text = (L 'AiPhase2Tick') -f $done, $state.Ai.Total
    }
    elseif (Test-Path $state.ProgFile) {
        $p = Get-Content $state.ProgFile -Raw -ErrorAction SilentlyContinue
        if ($p) {
            $t = [regex]::Matches($p, 'out_time_us=(\d+)')
            $s = [regex]::Matches($p, 'speed=\s*([\d.]+)x')
            if ($t.Count -gt 0 -and $state.Duration -gt 0) {
                $sec = [double]$t[$t.Count-1].Groups[1].Value / 1e6
                $pct = [Math]::Min(100, [int]($sec / $state.Duration * 100))
                $bar.Value = $pct
                $spd = if ($s.Count -gt 0) { $s[$s.Count-1].Groups[1].Value + 'x' } else { '?' }
                $eta = ''
                if ($s.Count -gt 0 -and [double]$s[$s.Count-1].Groups[1].Value -gt 0) {
                    $rem = ($state.Duration - $sec) / [double]$s[$s.Count-1].Groups[1].Value
                    $eta = ' - ' + (L 'Left') + ' ~' + [TimeSpan]::FromSeconds($rem).ToString('hh\:mm\:ss')
                }
                $pfx = ''
                if ($state.Kind -eq 'queue' -and $state.Queue.Count -gt 1) { $pfx = (L 'FilePrefix') -f ($state.Index+1), $state.Queue.Count }
                $lblStatus.Text = "$pfx%$pct  ($(L 'Speed'): $spd$eta)"
            }
        }
    }
    if ($state.Proc -and $state.Proc.HasExited) {
        if ($state.AiActive -and $state.Ai.Phase -ne 'encode') { Step-AiJob } else { Complete-File }
    }
})

$btnStart.Add_Click({
    try {
        if ($lst.Items.Count -eq 0) { throw (L 'QueueEmpty') }
        if (-not (Test-Path $FFmpeg)) { throw ((L 'FfmpegMissing') -f $FFmpeg) }
        $state.Queue.Clear()
        $lst.Items | ForEach-Object { [void]$state.Queue.Add($_) }
        $state.Index = 0
        $state.Kind = 'queue'
        Set-Busy $true
        Start-QueueItem
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, (L 'Error'), 'OK', 'Warning') | Out-Null
    }
})

# Onizleme/karsilastirma: secili (yoksa ilk) dosyanin ORTASINDAN 10 sn
function Get-SampleSource {
    if ($lst.Items.Count -eq 0) { throw (L 'PrevFirst') }
    $idx = $lst.SelectedIndex
    if ($idx -lt 0) { $idx = 0 }
    return $lst.Items[$idx]
}

$btnPrev.Add_Click({
    try {
        $in = Get-SampleSource
        $mi = Get-MediaInfo $in
        $state.Duration = [Math]::Min(10, $mi.Duration)
        $script:CurFps = $mi.Fps
        $mid = [Math]::Max(0, $mi.Duration/2 - 5)
        $state.Kind = 'preview'
        if ($cmbMode.SelectedItem -eq $AiModeName) {
            Set-Busy $true
            $lblStatus.Text = L 'AiPrevPrep'
            Log ((L 'AiPrevLog') -f (Split-Path $in -Leaf), $mid)
            Start-AiJob $in (Join-Path $TempDir 'preview_ai.mkv') @($mid, 10)
            return
        }
        $chain = Get-ChainFile $cmbMode.SelectedItem
        $script:tgt = Resolve-Target $cmbScale.SelectedItem $mi.W $mi.H
        Set-Busy $true
        $lblStatus.Text = L 'PrevPrep'
        Log ((L 'PrevLog') -f (Split-Path $in -Leaf), $mid)
        Start-Job2 $in (Join-Path $TempDir 'preview.mkv') @($mid, 10) $null $chain
    } catch {
        Set-Busy $false
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, (L 'Error'), 'OK', 'Warning') | Out-Null
    }
})

$btnCmp.Add_Click({
    try {
        if ($cmbMode.SelectedItem -eq $AiModeName) {
            throw (L 'CmpAiErr')
        }
        $in = Get-SampleSource
        $chain = Get-ChainFile $cmbMode.SelectedItem
        $mi = Get-MediaInfo $in
        if ($mi.W -le 0) { throw (L 'CmpNoRes') }
        $state.Duration = [Math]::Min(10, $mi.Duration)
        $tgt = Resolve-Target $cmbScale.SelectedItem $mi.W $mi.H
        $mid = [Math]::Max(0, $mi.Duration/2 - 5)
        # Sol: klasik lanczos, sag: shader zinciri - ayni boyutta yan yana
        $fc = ('[0:v]split=2[a][b];[b]scale={0}:{1}:flags=lanczos[pl];[a]libplacebo=w={0}:h={1}:custom_shader_path={2}[up];[pl][up]hstack=inputs=2' -f $tgt.NumW, $tgt.NumH, (Split-Path $chain -Leaf))
        $state.Kind = 'compare'
        Set-Busy $true
        $lblStatus.Text = L 'CmpPrep'
        if ($chkRife.Checked) { Log (L 'CmpNote') }
        Log ((L 'CmpLog') -f $cmbMode.SelectedItem)
        Start-Job2 $in (Join-Path $TempDir 'compare.mkv') @($mid, 10) $fc $chain
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, (L 'Error'), 'OK', 'Warning') | Out-Null
    }
})

$btnCancel.Add_Click({
    if ($state.Proc -and -not $state.Proc.HasExited) {
        $state.Queue.Clear(); $state.Index = 0
        $state.Cancelled = $true
        Stop-EncodeTree
    }
})

$form.Add_FormClosing({
    if ($state.Proc -and -not $state.Proc.HasExited) { $state.Cancelled = $true; Stop-EncodeTree }
    [void][Win32.Power]::SetThreadExecutionState($ES_CONTINUOUS)
})

# ================= Karanlik tema (uosc ile ayni palet) =================
$ClrBg      = [System.Drawing.Color]::FromArgb(0x1e,0x1e,0x2e)   # zemin
$ClrSurface = [System.Drawing.Color]::FromArgb(0x31,0x32,0x44)   # giris alanlari
$ClrBorder  = [System.Drawing.Color]::FromArgb(0x45,0x47,0x5a)   # kenar/hover
$ClrText    = [System.Drawing.Color]::FromArgb(0xcd,0xd6,0xf4)   # metin
$ClrMuted   = [System.Drawing.Color]::FromArgb(0xa6,0xad,0xc8)   # ikincil metin
$ClrAccent  = [System.Drawing.Color]::FromArgb(0x8b,0x5c,0xf6)   # mor vurgu
$ClrLogBg   = [System.Drawing.Color]::FromArgb(0x11,0x11,0x1b)   # log zemini

function Apply-Theme($ctrl) {
    foreach ($c in $ctrl.Controls) {
        switch ($c.GetType().Name) {
            'Label'         { $c.ForeColor = $ClrMuted }
            'CheckBox'      { $c.ForeColor = $ClrText }
            'TextBox'       { $c.BackColor = $ClrSurface; $c.ForeColor = $ClrText; $c.BorderStyle = 'FixedSingle' }
            'ListBox'       { $c.BackColor = $ClrSurface; $c.ForeColor = $ClrText; $c.BorderStyle = 'FixedSingle' }
            'ComboBox'      { $c.BackColor = $ClrSurface; $c.ForeColor = $ClrText; $c.FlatStyle = 'Flat' }
            'NumericUpDown' { $c.BackColor = $ClrSurface; $c.ForeColor = $ClrText; $c.BorderStyle = 'FixedSingle' }
            'Button'        {
                $c.FlatStyle = 'Flat'
                $c.BackColor = $ClrSurface; $c.ForeColor = $ClrText
                $c.FlatAppearance.BorderColor = $ClrBorder
                $c.FlatAppearance.MouseOverBackColor = $ClrBorder
            }
        }
        if ($c.Controls.Count -gt 0) { Apply-Theme $c }
    }
}

$form.BackColor = $ClrBg
Apply-Theme $form
# Vurgular
$btnStart.BackColor = $ClrAccent
$btnStart.ForeColor = $ClrBg
$btnStart.FlatAppearance.BorderColor = $ClrAccent
$btnStart.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xa7,0x8b,0xfa)
$btnStart.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$btnCancel.ForeColor = [System.Drawing.Color]::FromArgb(0xf3,0x8b,0xa8)
$txtLog.BackColor = $ClrLogBg
$txtLog.ForeColor = $ClrMuted
$txtLog.BorderStyle = 'FixedSingle'
$lblStatus.ForeColor = $ClrText

Log ((L 'RootLog') -f $Root)
if (-not $script:Rife.Ok) {
    $chkRife.Enabled = $false
    Log ((L 'RifeOff') -f $script:Rife.Reason)
}
if (-not $script:Ai.Ok) { Log ((L 'AiOff') -f $script:Ai.Reason) }
Log (L 'Ready')
[void]$form.ShowDialog()
