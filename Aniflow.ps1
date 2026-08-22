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

# ================= Ayarlar / Settings =================
# Tum kalici tercihler %APPDATA%\Aniflow.settings.json dosyasinda tutulur.
$CfgFile = Join-Path $env:APPDATA 'Aniflow.settings.json'
$script:Cfg = @{
    Lang = 'en'            # en | tr
    Container = 'mkv'      # mkv | mp4
    Suffix = '_upscale'    # cikti dosya adi eki
    OutDir = ''            # bos = kaynak dosyanin yanina
    CpuPreset = 'medium'   # libx264/libx265 preset
    AiModel = 'realesr-animevideov3'
    AiTile = 0             # 0 = otomatik; dusuk deger = az VRAM
    AiGpu = 0
    TempRoot = ''          # bos = sistem TEMP; AI kareleri icin buyuk disk secilebilir
    KeepTemp = $false
    RifeModel = 'rife-v4.6_ensembleFalse'
    RifeGpuThread = 2
}
function Load-Config {
    if (Test-Path $CfgFile) {
        try {
            $j = Get-Content $CfgFile -Raw | ConvertFrom-Json
            foreach ($k in @($script:Cfg.Keys)) {
                if ($null -ne $j.$k) { $script:Cfg[$k] = $j.$k }
            }
        } catch {}
    } else {
        # eski tek satirlik dil dosyasindan gecis
        $old = Join-Path $env:APPDATA 'Aniflow.lang'
        if (Test-Path $old) {
            $lc = (Get-Content $old -TotalCount 1 -ErrorAction SilentlyContinue)
            if ($lc -and $lc.Trim() -in @('en','tr')) { $script:Cfg.Lang = $lc.Trim() }
        }
    }
    if ($script:Cfg.Lang -notin @('en','tr')) { $script:Cfg.Lang = 'en' }
    if ($script:Cfg.Container -notin @('mkv','mp4')) { $script:Cfg.Container = 'mkv' }
}
function Save-Config {
    try { $script:Cfg | ConvertTo-Json | Set-Content -Path $CfgFile -Encoding UTF8 } catch {}
}
Load-Config
$script:LangCode = $script:Cfg.Lang

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
    Settings='Settings...'
    SetTitle='Aniflow Settings'
    SetGeneral='General'; SetLang='Language:'
    SetOut='Output folder:'; SetOutSrc='Next to the source file'; SetOutCustom='Custom folder:'
    SetSuffix='Filename suffix:'; SetContainer='Container:'
    SetEncoding='Encoding'; SetPreset='x264/x265 preset:'
    SetAiHead='AI Upscale'; SetAiModel='AI model:'; SetAiTile='Tile size (lower = less VRAM):'
    SetAiGpu='GPU index:'; SetTempDir='Temp folder for AI frames (empty = system temp):'
    SetKeepTemp='Keep temp frames after job (debugging)'
    SetRifeHead='RIFE'; SetRifeModel='RIFE model:'; SetRifeThreads='GPU threads:'
    OKBtn='OK'; CancelBtn='Cancel'; TileAuto='Auto'
    Ai4xOnly='This AI model is 4x only - pick 4x as output resolution.'
    Mp4Note='MP4 container: attachments are dropped and subtitles converted to mov_text.'
    KeepTempLog='Temp frames kept: {0}'
    CtxTop='Move to top'; CtxUp='Move up'; CtxDown='Move down'; CtxBottom='Move to bottom'
    CtxRemove='Remove'; CtxOpenSrc='Open source folder'; CtxOpenDst='Open output folder'
    SubDropNote='MP4: {0} bitmap subtitle stream(s) (PGS/VobSub) cannot be stored in MP4, dropped.'
    AudioFallback='MP4: "{0}" audio cannot be copied into MP4 - re-encoding to AAC 192k.'
    OutExists='Output already exists, writing to: {0}'
    AiStartFail='AI job could not start: {0}'
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
    Settings='Ayarlar...'
    SetTitle='Aniflow Ayarlari'
    SetGeneral='Genel'; SetLang='Dil:'
    SetOut='Cikti klasoru:'; SetOutSrc='Kaynak dosyanin yanina'; SetOutCustom='Ozel klasor:'
    SetSuffix='Dosya adi eki:'; SetContainer='Kapsayici:'
    SetEncoding='Kodlama'; SetPreset='x264/x265 preset:'
    SetAiHead='AI Upscale'; SetAiModel='AI modeli:'; SetAiTile='Tile boyutu (dusuk = az VRAM):'
    SetAiGpu='GPU sirasi:'; SetTempDir='AI kareleri icin gecici klasor (bos = sistem TEMP):'
    SetKeepTemp='Is bitince gecici kareleri sakla (hata ayiklama)'
    SetRifeHead='RIFE'; SetRifeModel='RIFE modeli:'; SetRifeThreads='GPU is parcacigi:'
    OKBtn='Tamam'; CancelBtn='Iptal'; TileAuto='Otomatik'
    Ai4xOnly='Bu AI modeli yalniz 4x calisir - cikti cozunurlugu olarak 4x secin.'
    Mp4Note='MP4 kapsayici: ek dosyalar atlanir, altyazilar mov_text formatina cevrilir.'
    KeepTempLog='Gecici kareler saklandi: {0}'
    CtxTop='En uste tasi'; CtxUp='Yukari tasi'; CtxDown='Asagi tasi'; CtxBottom='En alta tasi'
    CtxRemove='Kaldir'; CtxOpenSrc='Kaynak klasoru ac'; CtxOpenDst='Cikti klasorunu ac'
    SubDropNote='MP4: {0} bitmap altyazi akisi (PGS/VobSub) MP4 icinde tasinamaz, atlandi.'
    AudioFallback='MP4: "{0}" ses akisi MP4 icine kopyalanamaz - AAC 192k olarak yeniden kodlaniyor.'
    OutExists='Cikti dosyasi zaten var, suraya yazilacak: {0}'
    AiStartFail='AI isi baslatilamadi: {0}'
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
    { param($q) @('-c:v','libx264','-crf',"$q",'-preset',$script:Cfg.CpuPreset) }
    { param($q) @('-c:v','libx265','-crf',"$q",'-preset',$script:Cfg.CpuPreset) }
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
        if (-not (Test-Path -LiteralPath (Join-Path $Shaders $f))) {
            throw "Shader missing: $f (folder: $Shaders)"
        }
    }
    $safe  = ($modeName -replace '[^\w]+','_').Trim('_')
    $name  = "_chain_$safe.glsl"
    $src   = foreach ($f in $files) { Get-Item -LiteralPath (Join-Path $Shaders $f) }
    $newest = ($src | Measure-Object -Property LastWriteTime -Maximum).Maximum
    foreach ($dir in @($Shaders, $TempDir)) {
        $chain = Join-Path $dir $name
        try {
            if (-not (Test-Path -LiteralPath $chain) -or (Get-Item -LiteralPath $chain).LastWriteTime -lt $newest) {
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

# Girdinin ses/altyazi kodeklerini listeler (mp4 uyumluluk kararlari icin).
# TextSubs: metin altyazilarin goreli s-indeksleri; BitmapSubs: atlanacak akis sayisi
function Get-StreamCodecs([string]$path) {
    $ErrorActionPreference = 'Continue'
    $info = & $FFmpeg -hide_banner -i $path 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    $r = @{ Audio = @(); TextSubs = @(); BitmapSubs = 0 }
    $textCodecs = 'subrip|srt|ass|ssa|mov_text|webvtt|text'
    $si = 0
    foreach ($m in [regex]::Matches($info, 'Stream #\d+:\d+[^\r\n]*?:\s*(Audio|Subtitle):\s*(\w+)')) {
        $kind = $m.Groups[1].Value; $codec = $m.Groups[2].Value
        if ($kind -eq 'Audio') { $r.Audio += $codec }
        else {
            if ($codec -match "^($textCodecs)$") { $r.TextSubs += $si } else { $r.BitmapSubs++ }
            $si++
        }
    }
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
    # once setup.ps1'in kurdugu tasinabilir VapourSynth, sonra sistemdeki vspipe
    $portable = Join-Path $VapourDir 'portable\Lib\site-packages\vapoursynth\vspipe.exe'
    if (Test-Path -LiteralPath $portable) { $r.Vspipe = $portable }
    else {
        $vs = Get-Command vspipe.exe -ErrorAction SilentlyContinue
        if (-not $vs) { $r.Reason = 'vspipe.exe missing (re-run setup.ps1 - it installs portable VapourSynth)'; return $r }
        $r.Vspipe = $vs.Source
    }
    # RIFE eklentisi/modeli: once proje klasoru, sonra mpv kurulumu
    foreach ($d in @($VapourDir, (Join-Path $env:APPDATA 'mpv\vapoursynth'))) {
        $dll = Join-Path $d 'librife_windows_x86-64.dll'
        $mod = Join-Path $d 'models\rife-v4.6_ensembleFalse'
        if ((Test-Path -LiteralPath $dll) -and (Test-Path -LiteralPath $mod)) { $r.RifeDll = $dll; $r.ModelDir = Join-Path $d 'models'; break }
    }
    if (-not $r.RifeDll) { $r.Reason = 'RIFE plugin/model not found (run setup.ps1)'; return $r }
    $bs = Join-Path $VapourDir 'bestsource.dll'
    if (-not (Test-Path -LiteralPath $bs)) { $r.Reason = 'bestsource.dll missing (run setup.ps1)'; return $r }
    $r.SourceDll = $bs
    if (-not (Test-Path -LiteralPath $VpyScript)) { $r.Reason = 'rife_encode.vpy missing'; return $r }
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
    if (-not (Test-Path -LiteralPath $AiExe)) { $r.Reason = 'realesrgan-ncnn-vulkan.exe missing (run setup.ps1)'; return $r }
    if (-not (Test-Path -LiteralPath (Join-Path $AiDir 'models\realesr-animevideov3-x2.param'))) {
        $r.Reason = 'animevideov3 model missing (run setup.ps1)'; return $r
    }
    $r.Ok = $true
    return $r
}
$script:Ai = Find-AiSupport

if ($SelfTest) {
    'ffmpeg: ' + (Test-Path -LiteralPath $FFmpeg)
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
$form.Text = 'Aniflow 1.1 - Anime4K / FSRCNNX Video Upscaler - Daily Dana'
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

# --- Kuyruk sag tik menusu ---
$ctxMenu   = New-Object System.Windows.Forms.ContextMenuStrip
$ctxTop    = New-Object System.Windows.Forms.ToolStripMenuItem
$ctxUp     = New-Object System.Windows.Forms.ToolStripMenuItem
$ctxDown   = New-Object System.Windows.Forms.ToolStripMenuItem
$ctxBottom = New-Object System.Windows.Forms.ToolStripMenuItem
$ctxRemove = New-Object System.Windows.Forms.ToolStripMenuItem
$ctxOpenSrc = New-Object System.Windows.Forms.ToolStripMenuItem
$ctxOpenDst = New-Object System.Windows.Forms.ToolStripMenuItem
[void]$ctxMenu.Items.AddRange(@($ctxTop, $ctxUp, $ctxDown, $ctxBottom,
    (New-Object System.Windows.Forms.ToolStripSeparator), $ctxRemove,
    (New-Object System.Windows.Forms.ToolStripSeparator), $ctxOpenSrc, $ctxOpenDst))
$lst.ContextMenuStrip = $ctxMenu

# sag tiklanan ogeyi sec; bos alana tiklandiysa menuyu acma
$lst.Add_MouseDown({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $i = $lst.IndexFromPoint($_.Location)
        if ($i -ge 0) { $lst.SelectedIndex = $i }
    }
})
$ctxMenu.Add_Opening({ if ($lst.SelectedIndex -lt 0) { $_.Cancel = $true } })

function Move-QueueItem([int]$to) {
    $i = $lst.SelectedIndex
    if ($i -lt 0) { return }
    $item = $lst.Items[$i]
    $lst.Items.RemoveAt($i)
    if ($to -lt 0) { $to = 0 }
    if ($to -gt $lst.Items.Count) { $to = $lst.Items.Count }
    $lst.Items.Insert($to, $item)
    $lst.SelectedIndex = $to
}
$ctxTop.Add_Click({ Move-QueueItem 0 })
$ctxUp.Add_Click({ $i = $lst.SelectedIndex; if ($i -gt 0) { Move-QueueItem ($i - 1) } })
$ctxDown.Add_Click({ $i = $lst.SelectedIndex; if ($i -ge 0 -and $i -lt ($lst.Items.Count - 1)) { Move-QueueItem ($i + 1) } })
$ctxBottom.Add_Click({ Move-QueueItem ($lst.Items.Count - 1) })
$ctxRemove.Add_Click({ if ($lst.SelectedIndex -ge 0) { $lst.Items.RemoveAt($lst.SelectedIndex) } })
$ctxOpenSrc.Add_Click({
    $i = $lst.SelectedIndex
    if ($i -ge 0 -and (Test-Path -LiteralPath $lst.Items[$i])) {
        Start-Process explorer.exe "/select,`"$($lst.Items[$i])`""
    }
})
$ctxOpenDst.Add_Click({
    $i = $lst.SelectedIndex
    if ($i -lt 0) { return }
    $d = Split-Path $lst.Items[$i] -Parent
    if ($script:Cfg.OutDir -and (Test-Path -LiteralPath $script:Cfg.OutDir)) { $d = $script:Cfg.OutDir }
    if (Test-Path -LiteralPath $d) { Start-Process explorer.exe "`"$d`"" }
})

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

# Ayarlar dugmesi / settings button
$btnSettings = New-Object System.Windows.Forms.Button
$btnSettings.Location = New-Object System.Drawing.Point(575, 140)
$btnSettings.Size = New-Object System.Drawing.Size(85, 28)
$btnSettings.Anchor = 'Top,Right'
$form.Controls.Add($btnSettings)

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
    $btnSettings.Text = L 'Settings'
    $ctxTop.Text = L 'CtxTop'; $ctxUp.Text = L 'CtxUp'; $ctxDown.Text = L 'CtxDown'; $ctxBottom.Text = L 'CtxBottom'
    $ctxRemove.Text = L 'CtxRemove'; $ctxOpenSrc.Text = L 'CtxOpenSrc'; $ctxOpenDst.Text = L 'CtxOpenDst'
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

# ================= Ayarlar penceresi =================
function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = L 'SetTitle'
    $dlg.ClientSize = New-Object System.Drawing.Size(465, 640)
    $dlg.FormBorderStyle = 'FixedDialog'; $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.StartPosition = 'CenterParent'
    $dlg.Font = $form.Font

    function Add-DlgLabel($text, $x, $y, [bool]$head) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.AutoSize = $true
        if ($head) { $l.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10); $l.Tag = 'head' }
        $dlg.Controls.Add($l); return $l
    }

    # --- Genel ---
    $hd = Add-DlgLabel (L 'SetGeneral') 15 12 $true
    $hd.ForeColor = $ClrAccent
    Add-DlgLabel (L 'SetLang') 15 42 $false | Out-Null
    $dLang = New-Object System.Windows.Forms.ComboBox
    $dLang.Location = New-Object System.Drawing.Point(230, 39); $dLang.Size = New-Object System.Drawing.Size(120, 24)
    $dLang.DropDownStyle = 'DropDownList'
    @('English','Turkce') | ForEach-Object { [void]$dLang.Items.Add($_) }
    $dLang.SelectedIndex = $(if ($script:Cfg.Lang -eq 'tr') { 1 } else { 0 })
    $dlg.Controls.Add($dLang)

    Add-DlgLabel (L 'SetOut') 15 74 $false | Out-Null
    $rbSrc = New-Object System.Windows.Forms.RadioButton
    $rbSrc.Text = L 'SetOutSrc'; $rbSrc.Location = New-Object System.Drawing.Point(25, 96); $rbSrc.AutoSize = $true
    $dlg.Controls.Add($rbSrc)
    $rbCustom = New-Object System.Windows.Forms.RadioButton
    $rbCustom.Text = L 'SetOutCustom'; $rbCustom.Location = New-Object System.Drawing.Point(25, 120); $rbCustom.AutoSize = $true
    $dlg.Controls.Add($rbCustom)
    $dOut = New-Object System.Windows.Forms.TextBox
    $dOut.Location = New-Object System.Drawing.Point(160, 118); $dOut.Size = New-Object System.Drawing.Size(240, 24)
    $dOut.Text = $script:Cfg.OutDir
    $dlg.Controls.Add($dOut)
    $dOutBtn = New-Object System.Windows.Forms.Button
    $dOutBtn.Text = '...'; $dOutBtn.Location = New-Object System.Drawing.Point(408, 116); $dOutBtn.Size = New-Object System.Drawing.Size(40, 26)
    $dlg.Controls.Add($dOutBtn)
    if ($script:Cfg.OutDir) { $rbCustom.Checked = $true } else { $rbSrc.Checked = $true }
    $dOutBtn.Add_Click({
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($fb.ShowDialog() -eq 'OK') { $dOut.Text = $fb.SelectedPath; $rbCustom.Checked = $true }
    })

    Add-DlgLabel (L 'SetSuffix') 15 156 $false | Out-Null
    $dSuffix = New-Object System.Windows.Forms.TextBox
    $dSuffix.Location = New-Object System.Drawing.Point(230, 153); $dSuffix.Size = New-Object System.Drawing.Size(120, 24)
    $dSuffix.Text = $script:Cfg.Suffix
    $dlg.Controls.Add($dSuffix)

    Add-DlgLabel (L 'SetContainer') 15 188 $false | Out-Null
    $dCont = New-Object System.Windows.Forms.ComboBox
    $dCont.Location = New-Object System.Drawing.Point(230, 185); $dCont.Size = New-Object System.Drawing.Size(120, 24)
    $dCont.DropDownStyle = 'DropDownList'
    @('mkv','mp4') | ForEach-Object { [void]$dCont.Items.Add($_) }
    $dCont.SelectedIndex = $(if ($script:Cfg.Container -eq 'mp4') { 1 } else { 0 })
    $dlg.Controls.Add($dCont)

    # --- Kodlama ---
    $hd = Add-DlgLabel (L 'SetEncoding') 15 224 $true
    $hd.ForeColor = $ClrAccent
    Add-DlgLabel (L 'SetPreset') 15 252 $false | Out-Null
    $dPreset = New-Object System.Windows.Forms.ComboBox
    $dPreset.Location = New-Object System.Drawing.Point(230, 249); $dPreset.Size = New-Object System.Drawing.Size(120, 24)
    $dPreset.DropDownStyle = 'DropDownList'
    $presets = @('ultrafast','veryfast','fast','medium','slow','veryslow')
    $presets | ForEach-Object { [void]$dPreset.Items.Add($_) }
    $pi = $presets.IndexOf([string]$script:Cfg.CpuPreset)
    $dPreset.SelectedIndex = $(if ($pi -ge 0) { $pi } else { 3 })
    $dlg.Controls.Add($dPreset)

    # --- AI ---
    $hd = Add-DlgLabel (L 'SetAiHead') 15 288 $true
    $hd.ForeColor = $ClrAccent
    Add-DlgLabel (L 'SetAiModel') 15 316 $false | Out-Null
    $dAiModel = New-Object System.Windows.Forms.ComboBox
    $dAiModel.Location = New-Object System.Drawing.Point(230, 313); $dAiModel.Size = New-Object System.Drawing.Size(220, 24)
    $dAiModel.DropDownStyle = 'DropDownList'
    $aiModels = @('realesr-animevideov3')
    foreach ($m in @('realesrgan-x4plus-anime','realesrgan-x4plus','realesrnet-x4plus')) {
        if (Test-Path -LiteralPath (Join-Path $AiDir "models\$m.param")) { $aiModels += $m }
    }
    $aiModels | ForEach-Object { [void]$dAiModel.Items.Add($_) }
    $mi = $aiModels.IndexOf([string]$script:Cfg.AiModel)
    $dAiModel.SelectedIndex = $(if ($mi -ge 0) { $mi } else { 0 })
    $dlg.Controls.Add($dAiModel)

    Add-DlgLabel (L 'SetAiTile') 15 348 $false | Out-Null
    $dTile = New-Object System.Windows.Forms.ComboBox
    $dTile.Location = New-Object System.Drawing.Point(230, 345); $dTile.Size = New-Object System.Drawing.Size(120, 24)
    $dTile.DropDownStyle = 'DropDownList'
    $tiles = @(0, 128, 256, 512)
    $tiles | ForEach-Object { [void]$dTile.Items.Add($(if ($_ -eq 0) { L 'TileAuto' } else { "$_" })) }
    $ti = $tiles.IndexOf([int]$script:Cfg.AiTile)
    $dTile.SelectedIndex = $(if ($ti -ge 0) { $ti } else { 0 })
    $dlg.Controls.Add($dTile)

    Add-DlgLabel (L 'SetAiGpu') 15 380 $false | Out-Null
    $dGpu = New-Object System.Windows.Forms.NumericUpDown
    $dGpu.Location = New-Object System.Drawing.Point(230, 377); $dGpu.Size = New-Object System.Drawing.Size(60, 24)
    $dGpu.Minimum = 0; $dGpu.Maximum = 3; $dGpu.Value = [Math]::Min(3, [Math]::Max(0, [int]$script:Cfg.AiGpu))
    $dlg.Controls.Add($dGpu)

    Add-DlgLabel (L 'SetTempDir') 15 412 $false | Out-Null
    $dTemp = New-Object System.Windows.Forms.TextBox
    $dTemp.Location = New-Object System.Drawing.Point(15, 436); $dTemp.Size = New-Object System.Drawing.Size(385, 24)
    $dTemp.Text = $script:Cfg.TempRoot
    $dlg.Controls.Add($dTemp)
    $dTempBtn = New-Object System.Windows.Forms.Button
    $dTempBtn.Text = '...'; $dTempBtn.Location = New-Object System.Drawing.Point(408, 434); $dTempBtn.Size = New-Object System.Drawing.Size(40, 26)
    $dlg.Controls.Add($dTempBtn)
    $dTempBtn.Add_Click({
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($fb.ShowDialog() -eq 'OK') { $dTemp.Text = $fb.SelectedPath }
    })

    $dKeep = New-Object System.Windows.Forms.CheckBox
    $dKeep.Text = L 'SetKeepTemp'; $dKeep.Location = New-Object System.Drawing.Point(15, 470); $dKeep.AutoSize = $true
    $dKeep.Checked = [bool]$script:Cfg.KeepTemp
    $dlg.Controls.Add($dKeep)

    # --- RIFE ---
    $hd = Add-DlgLabel (L 'SetRifeHead') 15 504 $true
    $hd.ForeColor = $ClrAccent
    Add-DlgLabel (L 'SetRifeModel') 15 532 $false | Out-Null
    $dRifeModel = New-Object System.Windows.Forms.ComboBox
    $dRifeModel.Location = New-Object System.Drawing.Point(230, 529); $dRifeModel.Size = New-Object System.Drawing.Size(220, 24)
    $dRifeModel.DropDownStyle = 'DropDownList'
    $rifeModels = @()
    if ($script:Rife.Ok) {
        $rifeModels = @(Get-ChildItem -LiteralPath $script:Rife.ModelDir -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)
    }
    if (-not $rifeModels) { $rifeModels = @([string]$script:Cfg.RifeModel) }
    $rifeModels | ForEach-Object { [void]$dRifeModel.Items.Add($_) }
    $ri = $rifeModels.IndexOf([string]$script:Cfg.RifeModel)
    $dRifeModel.SelectedIndex = $(if ($ri -ge 0) { $ri } else { 0 })
    $dlg.Controls.Add($dRifeModel)

    Add-DlgLabel (L 'SetRifeThreads') 15 564 $false | Out-Null
    $dRifeThr = New-Object System.Windows.Forms.NumericUpDown
    $dRifeThr.Location = New-Object System.Drawing.Point(230, 561); $dRifeThr.Size = New-Object System.Drawing.Size(60, 24)
    $dRifeThr.Minimum = 1; $dRifeThr.Maximum = 4; $dRifeThr.Value = [Math]::Min(4, [Math]::Max(1, [int]$script:Cfg.RifeGpuThread))
    $dlg.Controls.Add($dRifeThr)

    # --- OK / Iptal ---
    $dOk = New-Object System.Windows.Forms.Button
    $dOk.Text = L 'OKBtn'; $dOk.Location = New-Object System.Drawing.Point(255, 600); $dOk.Size = New-Object System.Drawing.Size(90, 30)
    $dOk.DialogResult = 'OK'
    $dlg.Controls.Add($dOk)
    $dCancel = New-Object System.Windows.Forms.Button
    $dCancel.Text = L 'CancelBtn'; $dCancel.Location = New-Object System.Drawing.Point(358, 600); $dCancel.Size = New-Object System.Drawing.Size(90, 30)
    $dCancel.DialogResult = 'Cancel'
    $dlg.Controls.Add($dCancel)
    $dlg.AcceptButton = $dOk; $dlg.CancelButton = $dCancel

    $dlg.BackColor = $ClrBg
    Apply-Theme $dlg

    if ($dlg.ShowDialog($form) -eq 'OK') {
        $script:Cfg.Lang = @('en','tr')[$dLang.SelectedIndex]
        $script:Cfg.OutDir = $(if ($rbCustom.Checked -and $dOut.Text.Trim()) { $dOut.Text.Trim() } else { '' })
        $sfx = $dSuffix.Text.Trim()
        $script:Cfg.Suffix = ($sfx -replace '[\\/:*?"<>|]','')   # dosya adinda gecersiz karakterleri ayikla
        $script:Cfg.Container = $dCont.SelectedItem
        $script:Cfg.CpuPreset = $dPreset.SelectedItem
        $script:Cfg.AiModel = $dAiModel.SelectedItem
        $script:Cfg.AiTile = $tiles[$dTile.SelectedIndex]
        $script:Cfg.AiGpu = [int]$dGpu.Value
        $script:Cfg.TempRoot = $dTemp.Text.Trim()
        $script:Cfg.KeepTemp = $dKeep.Checked
        $script:Cfg.RifeModel = $dRifeModel.SelectedItem
        $script:Cfg.RifeGpuThread = [int]$dRifeThr.Value
        Save-Config
        $script:LangCode = $script:Cfg.Lang
        Set-UiLanguage
    }
    $dlg.Dispose()
}
$btnSettings.Add_Click({ Show-SettingsDialog })

# --- Durum ---
$state = @{
    Proc = $null; Duration = 0; ProgFile = Join-Path $TempDir 'progress.txt'
    ErrFile = Join-Path $TempDir 'stderr.txt'; ErrOffset = 0; OutPath = ''; UsedOuts = @{}
    Queue = New-Object System.Collections.ArrayList; Index = 0
    Kind = 'queue'   # queue | preview | compare
    Cancelled = $false; RifeJob = $false
    Ai = $null; AiActive = $false   # AI modu faz durumu (extract | upscale | encode)
}

function Add-Files($paths) {
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            Get-ChildItem -LiteralPath $p -File | Where-Object Extension -match '\.(mkv|mp4|avi|webm|mov|ts|m2ts|wmv)$' |
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

# Cikti yolunu ayarlara gore kur: klasor (kaynak yani / ozel) + ek + kapsayici
function Get-OutPath([string]$srcDir, [string]$baseName, [string]$tag) {
    $d = $srcDir
    if ($script:Cfg.OutDir -and (Test-Path -LiteralPath $script:Cfg.OutDir)) { $d = $script:Cfg.OutDir }
    # Ayni yola cozulen ciktilar (ozel cikti klasorunde ayni adli bolumler, onceki
    # kosudan kalan dosya) ffmpeg -y ile sessizce ezilmesin: doluysa _2, _3... eki
    $p = Join-Path $d ('{0}_{1}{2}.{3}' -f $baseName, $tag, $script:Cfg.Suffix, $script:Cfg.Container)
    $k = 2
    while ((Test-Path -LiteralPath $p) -or $state.UsedOuts.ContainsKey($p)) {
        $p = Join-Path $d ('{0}_{1}{2}_{4}.{3}' -f $baseName, $tag, $script:Cfg.Suffix, $script:Cfg.Container, $k)
        $k++
    }
    if ($k -gt 2) { Log ((L 'OutExists') -f $p) }
    $state.UsedOuts[$p] = $true
    return $p
}

# Akis eslemeleri YAZILACAK dosyanin kabina gore (global ayara gore degil:
# onizleme/karsilastirma ciktilari her zaman mkv'dir). mkv veri akisi (d)
# tasiyamaz; mp4 ek dosya tasiyamaz ve altyazida yalniz metin -> mov_text
# cevrimi mumkundur, bitmap altyazilar (PGS/VobSub) atlanir.
function Get-StreamArgs([int]$srcInput, [string]$outPath, $codecs) {
    $i = "$srcInput"
    $a = @('-map','0:v:0','-map',"${i}:a?")
    if ([IO.Path]::GetExtension($outPath) -eq '.mp4') {
        foreach ($s in $codecs.TextSubs) { $a += @('-map',"${i}:s:$s") }
        if ($codecs.BitmapSubs -gt 0) { Log ((L 'SubDropNote') -f $codecs.BitmapSubs) }
        $c = if (@($codecs.TextSubs).Count -gt 0) { @('-c:s','mov_text') } else { @() }
    } else {
        $a += @('-map',"${i}:s?",'-map',"${i}:t?")
        $c = @('-c:s','copy','-c:t','copy')
    }
    if ($srcInput -eq 1) { $a += @('-map_metadata','1','-map_chapters','1') }
    return @{ Maps = $a; Codecs = $c }
}

# Ses secenegini kapla bagdastirir: mp4'e kopyalanamayan kodekler AAC'ye duser,
# Opus mp4'te deneysel bayrak ister
function Get-AudioArgs([string]$outPath, $codecs) {
    $sel = $AudioCmds[$cmbAudio.SelectedIndex]
    if ([IO.Path]::GetExtension($outPath) -ne '.mp4') { return $sel }
    if ($cmbAudio.SelectedIndex -eq 2) { return $sel + @('-strict','experimental') }
    if ($cmbAudio.SelectedIndex -eq 0) {
        $bad = @($codecs.Audio) | Where-Object { $_ -notmatch '^(aac|mp3|mp2|ac3|eac3|alac|dts)$' } | Select-Object -First 1
        if ($bad) { Log ((L 'AudioFallback') -f $bad); return @('-c:a','aac','-b:a','192k') }
    }
    return $sel
}

function Set-Busy([bool]$busy) {
    $btnStart.Enabled = -not $busy; $btnPrev.Enabled = -not $busy; $btnCmp.Enabled = -not $busy
    # is surerken ayar degisikligi yasak: AI fazlari Cfg'yi canli okur, dil
    # yenilemesi de calisan isin kullandigi combobox indekslerini kaydirir
    $btnSettings.Enabled = -not $busy
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
    $state.RifeJob = $useRife

    $ffArgs = @('-y','-hide_banner','-loglevel','warning','-init_hw_device','vulkan')
    if ($useRife) {
        $ffArgs += @('-i','pipe:0')
        if ($trim) { $ffArgs += @('-ss',"$($trim[0])",'-t',"$($trim[1])") }   # ses girdisini ayni araliga kirpar
        # dosya yolu cmd satirina %VAR% olarak girer (asagida ANIFLOW_IN'e bakin)
        $ffArgs += @('-i', '"%ANIFLOW_IN%"')
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
        $codecs = Get-StreamCodecs $in
        if ([IO.Path]::GetExtension($out) -eq '.mp4') { Log (L 'Mp4Note') }
        $sa = Get-StreamArgs $(if ($useRife) { 1 } else { 0 }) $out $codecs
        $ffArgs += $sa.Maps
        $ffArgs += & $EncoderCmds[$cmbEnc.SelectedIndex] ([int]$numQ.Value)
        $ffArgs += Get-AudioArgs $out $codecs
        $ffArgs += $sa.Codecs
        $ffArgs += Split-ExtraArgs $txtExtra.Text
    }
    $ffArgs += @('-progress', $state.ProgFile, $(if ($useRife) { '"%ANIFLOW_OUT%"' } else { $out }))

    $state.ErrOffset = 0
    Remove-Item $state.ProgFile, $state.ErrFile -ErrorAction SilentlyContinue
    $state.OutPath = $out
    if ($useRife) {
        # Girdi/cikti yollari cmd satirina ham yazilmaz: % & ^ ! iceren adlar cmd'yi
        # bozar. Bunun yerine ortam degiskeni kullanilir; cmd %VAR%'i tirnak icinde
        # acar ve acilan degeri yeniden ayristirmaz, bu yuzden tum karakterler guvenli.
        $env:ANIFLOW_IN = $in
        $env:ANIFLOW_OUT = $out
        $vsArgs = @($script:Rife.Vspipe,'-c','y4m',
            '-a','"input=%ANIFLOW_IN%"',
            '-a',"rife_dll=$($script:Rife.RifeDll)",
            '-a',"source_dll=$($script:Rife.SourceDll)",
            '-a',"model_dir=$($script:Rife.ModelDir)")
        if ($script:CurFps -gt 0) {
            $vsArgs += @('-a',"fps_num=$([int][Math]::Round($script:CurFps*1000))",'-a','fps_den=1000')
        }
        if ($trim) { $vsArgs += @('-a',"start_sec=$($trim[0])",'-a',"dur_sec=$($trim[1])") }
        # ayarlardan model ve GPU is parcacigi (rife_encode.vpy bu adlari okur)
        $vsArgs += @('-a',"model=$($script:Cfg.RifeModel)",'-a',"gpu_thread=$($script:Cfg.RifeGpuThread)")
        $vsArgs += @($VpyScript,'-')
        # Iki sureci tek cmd altinda borula: tek tutamac, cikis kodu = ffmpeg'inki,
        # iki surecin stderr'i de ayni dosyaya akar (mevcut log/timer duzeni bozulmaz)
        # /v:off: gecikmeli acilim kayitta acik olsa bile ! isareti ozel sayilmasin
        $cmdLine = '/v:off /s /c "' + ((Quote-Args $vsArgs) -join ' ') + ' | ' + ((Quote-Args (@($FFmpeg) + $ffArgs)) -join ' ') + '"'
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

# Klasoru joker acilimsiz ve hizli siler: Remove-Item hem koseli parantezli
# yollari desen sayar (yanlis klasoru silebilir) hem on binlerce dosyada
# cok yavastir; [IO.Directory] her yolu harfiyen alir
function Remove-DirTree([string]$d) {
    if ($d -and [IO.Directory]::Exists($d)) { try { [IO.Directory]::Delete($d, $true) } catch {} }
}

function Clear-AiTemp {
    if ($state.Ai) {
        if ($script:Cfg.KeepTemp) {
            Log ((L 'KeepTempLog') -f (Split-Path $state.Ai.InDir -Parent))
            return
        }
        Remove-DirTree $state.Ai.InDir
        Remove-DirTree $state.Ai.OutDir
    }
}

function Start-AiJob([string]$in, [string]$out, $trim) {
    $fps = $script:CurFps
    if ($fps -le 0) { $fps = 23.976 }
    $sel = $cmbScale.SelectedItem
    if ($sel -notmatch '^([234])x') { throw (L 'AiScaleErr') }
    $aiScale = [int]$Matches[1]
    # animevideov3 disindaki modeller yalniz 4x calisir
    if ($script:Cfg.AiModel -ne 'realesr-animevideov3' -and $aiScale -ne 4) { throw (L 'Ai4xOnly') }
    $tempBase = $TempDir
    if ($script:Cfg.TempRoot -and (Test-Path -LiteralPath $script:Cfg.TempRoot)) { $tempBase = $script:Cfg.TempRoot }
    $state.Ai = @{
        Phase = 'extract'; In = $in; Out = $out; Fps = $fps; Scale = $aiScale
        InDir = Join-Path $tempBase 'ai_in'; OutDir = Join-Path $tempBase 'ai_out'
        Trim = $trim; Total = 0; Done = 0
    }
    foreach ($d in @($state.Ai.InDir, $state.Ai.OutDir)) {
        Remove-DirTree $d
        New-Item -ItemType Directory -Path $d | Out-Null
    }
    $state.AiActive = $true
    if ($chkRife.Checked) { Log (L 'RifeIgnored') }
    $dur = if ($trim) { [double]$trim[1] } else { $state.Duration }
    $frames = [int]($dur * $fps)
    # kaba tahmin (PNG, 1080p temel): giris ~2.5 MB/kare, cikis ~2.5*olcek^2
    $estGB = [Math]::Round($frames * 2.5 * (1 + $state.Ai.Scale * $state.Ai.Scale) / 1024, 1)
    Log ((L 'AiDiskLog') -f $state.Ai.Scale, $frames, $estGB, $tempBase)
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
            $a = @('-i',$ai.InDir,'-o',$ai.OutDir,'-n',$script:Cfg.AiModel,'-s',"$($ai.Scale)",'-f','png','-g',"$($script:Cfg.AiGpu)")
            if ([int]$script:Cfg.AiTile -gt 0) { $a += @('-t',"$($script:Cfg.AiTile)") }
            $lblStatus.Text = (L 'AiPhase2') -f $ai.Total
            Log ('realesrgan ' + ((Quote-Args $a) -join ' '))
            $state.Proc = Start-Process -FilePath $AiExe -ArgumentList (Quote-Args $a) `
                -WorkingDirectory $AiDir -WindowStyle Hidden -PassThru -RedirectStandardError $state.ErrFile
        }
        'encode' {
            $a = @('-y','-hide_banner','-loglevel','warning','-framerate',"$($ai.Fps)",'-i',(Join-Path $ai.OutDir 'f%08d.png'))
            if ($ai.Trim) { $a += @('-ss',"$($ai.Trim[0])",'-t',"$($ai.Trim[1])") }   # ses girdisini ayni araliga kirpar
            $a += @('-i',$ai.In)
            $codecs = Get-StreamCodecs $ai.In
            if ([IO.Path]::GetExtension($ai.Out) -eq '.mp4') { Log (L 'Mp4Note') }
            $sa = Get-StreamArgs 1 $ai.Out $codecs
            $a += $sa.Maps
            $a += & $EncoderCmds[$cmbEnc.SelectedIndex] ([int]$numQ.Value)
            # PNG (RGB) -> standart tv-range bt709 YUV; kaynak matris tahmini gerekmez.
            # trc/primaries de bt709 etiketlenir (PNG'nin sRGB etiketi sizmasin)
            $a += @('-vf','scale=out_range=tv:out_color_matrix=bt709,format=yuv420p',
                    '-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709')
            $a += Get-AudioArgs $ai.Out $codecs
            $a += $sa.Codecs
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
        'upscale' {
            $state.Ai.Phase = 'encode'
            # kodlama yalniz cikti karelerini okur; giris PNG'lerini simdi silmek
            # encode boyunca ~O(video) fazladan disk tutulmasini onler
            if (-not $script:Cfg.KeepTemp) { Remove-DirTree $state.Ai.InDir }
            Invoke-AiPhase
        }
    }
}

function Start-QueueItem {
    $in = $state.Queue[$state.Index]
    if (-not (Test-Path -LiteralPath $in)) { Log ((L 'SkipMissing') -f $in); Skip-Next; return }
    $mi = Get-MediaInfo $in
    $state.Duration = $mi.Duration
    $script:CurFps = $mi.Fps
    $d = Split-Path $in -Parent
    $n = [IO.Path]::GetFileNameWithoutExtension($in)
    if ($cmbMode.SelectedItem -eq $AiModeName) {
        if ($cmbScale.SelectedItem -notmatch '^([234])x') { Log (L 'SkipAiScale'); Skip-Next; return }
        $s = [int]$Matches[1]
        if ($script:Cfg.AiModel -ne 'realesr-animevideov3' -and $s -ne 4) { Log (L 'Ai4xOnly'); Skip-Next; return }
        $out = Get-OutPath $d $n ('ai{0}x' -f $s)
        $lblStatus.Text = (L 'FileStatus') -f ($state.Index+1), $state.Queue.Count, (Split-Path $in -Leaf)
        Log ('--- [{0}/{1}] {2} ({3}x{4}, {5:N1} s) -> AI x{6}' -f ($state.Index+1), $state.Queue.Count, (Split-Path $in -Leaf), $mi.W, $mi.H, $mi.Duration, $s)
        # timer tick'inden (Skip-Next) gelindiginde firlatan bir istisna WinForms
        # dongusunden kacip kuyrugu sessizce durdurur; burada yakala ve atla
        try { Start-AiJob $in $out $null }
        catch { Log ((L 'AiStartFail') -f $_.Exception.Message); Skip-Next }
        return
    }
    $chain = Get-ChainFile $cmbMode.SelectedItem
    $script:tgt = Resolve-Target $cmbScale.SelectedItem $mi.W $mi.H
    $rifeTag = ''
    if ($chkRife.Checked -and $script:Rife.Ok) { $rifeTag = '_rife' }
    $out = Get-OutPath $d $n "$($script:tgt.Tag)$rifeTag"
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
        if ($prog -match 'progress=end' -and (Test-Path -LiteralPath $state.OutPath)) { $code = 0 }
    }
    $ok = ($code -eq 0 -and (Test-Path -LiteralPath $state.OutPath))
    if ($ok) {
        $mb = (Get-Item -LiteralPath $state.OutPath).Length / 1MB
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
        # upscale fazinda ffmpeg -progress yok; kareler sirali uretildigi icin son
        # sayilan indeksten ileri yokla (klasoru bastan numaralandirmak on binlerce
        # dosyada tick basina 10-100 ms tutup arayuzu tiketiyordu)
        $done = $state.Ai.Done
        while ([IO.File]::Exists((Join-Path $state.Ai.OutDir ('f{0:d8}.png' -f ($done + 1))))) { $done++ }
        $state.Ai.Done = $done
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
        if (-not (Test-Path -LiteralPath $FFmpeg)) { throw ((L 'FfmpegMissing') -f $FFmpeg) }
        $state.Queue.Clear()
        $state.UsedOuts = @{}
        $lst.Items | ForEach-Object { [void]$state.Queue.Add($_) }
        $state.Index = 0
        $state.Kind = 'queue'
        Set-Busy $true
        Start-QueueItem
    } catch {
        Set-Busy $false
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
        Set-Busy $false
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
    # AI isi ortasinda kapatilirsa temizlik timer'a kalir, timer da form ile
    # olur: onlarca GB PNG yetim kalmasin diye burada da temizle
    if ($state.AiActive) { $state.AiActive = $false; Clear-AiTemp }
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
            'Label'         { if ($c.Tag -ne 'head') { $c.ForeColor = $ClrMuted } }
            'CheckBox'      { $c.ForeColor = $ClrText }
            'RadioButton'   { $c.ForeColor = $ClrText }
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
# sag tik menusu karanlik tema
$ctxMenu.BackColor = $ClrSurface
$ctxMenu.ForeColor = $ClrText
foreach ($mi in $ctxMenu.Items) { $mi.BackColor = $ClrSurface; $mi.ForeColor = $ClrText }

Log ((L 'RootLog') -f $Root)
if (-not $script:Rife.Ok) {
    $chkRife.Enabled = $false
    Log ((L 'RifeOff') -f $script:Rife.Reason)
}
if (-not $script:Ai.Ok) { Log ((L 'AiOff') -f $script:Ai.Reason) }
Log (L 'Ready')
[void]$form.ShowDialog()
