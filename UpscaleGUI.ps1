# Aniflow — Anime4K / FSRCNNX Video Upscaler GUI (TASINABILIR SURUM)
# Yazar: Daily Dana
# Tum bagimliliklar bu klasorde: bin\ffmpeg.exe + shaders\*.glsl
# Windows PowerShell 5.1+ (Windows'ta yerlesik) ile calisir, kurulum istemez.
# Istege bagli RIFE 2x kare interpolasyonu: vspipe (Python + VapourSynth) gerektirir.
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Root    = $PSScriptRoot
$FFmpeg  = Join-Path $Root 'bin\ffmpeg.exe'
$Shaders = Join-Path $Root 'shaders'
$TempDir = Join-Path $env:TEMP 'UpscaleGUI'
if (-not (Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir | Out-Null }

# Kodlama surerken sistemin uykuya gecmesini engellemek icin
Add-Type -Namespace Win32 -Name Power -MemberDefinition `
    '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
$ES_CONTINUOUS = [uint32]'0x80000000'; $ES_SYSTEM_REQUIRED = [uint32]'0x00000001'

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

# --- Kodlayicilar: CPU'lar her makinede calisir; donanim olanlar GPU'ya bagli,
# uyumsuz GPU'da ffmpeg hata verir ve log penceresinde gorunur ---
$Encoders = [ordered]@{
    'x264 (CPU, her yerde calisir)'  = { param($q) @('-c:v','libx264','-crf',"$q",'-preset','medium') }
    'x265 (CPU, her yerde calisir)'  = { param($q) @('-c:v','libx265','-crf',"$q",'-preset','medium') }
    'H.264 QSV (Intel GPU)'          = { param($q) @('-c:v','h264_qsv','-global_quality',"$q") }
    'HEVC QSV (Intel GPU)'           = { param($q) @('-c:v','hevc_qsv','-global_quality',"$q") }
    'AV1 QSV (Intel Arc)'            = { param($q) @('-c:v','av1_qsv','-global_quality',"$q") }
    'H.264 NVENC (NVIDIA GPU)'       = { param($q) @('-c:v','h264_nvenc','-rc','vbr','-cq',"$q",'-b:v','0') }
    'HEVC NVENC (NVIDIA GPU)'        = { param($q) @('-c:v','hevc_nvenc','-rc','vbr','-cq',"$q",'-b:v','0') }
    'H.264 AMF (AMD GPU)'            = { param($q) @('-c:v','h264_amf','-quality','quality','-rc','cqp','-qp_i',"$q",'-qp_p',"$q") }
    'HEVC AMF (AMD GPU)'             = { param($q) @('-c:v','hevc_amf','-quality','quality','-rc','cqp','-qp_i',"$q",'-qp_p',"$q") }
}

$AudioOpts = [ordered]@{
    'Kopyala (kayipsiz)'   = @('-c:a','copy')
    'AAC 192k'             = @('-c:a','aac','-b:a','192k')
    'Opus 160k'            = @('-c:a','libopus','-b:a','160k')
}

$FinishOpts = @('Hicbir sey yapma','Ses cal','Bilgisayari uyut','Bilgisayari kapat (30 sn)')

# Zincir dosyasini birlestir. Shaders klasoru yazilabilirse oraya, degilse
# (salt okunur USB vb.) TEMP'e yazar. Donus: zincirin tam yolu.
function Get-ChainFile([string]$modeName) {
    $files = $Modes[$modeName]
    foreach ($f in $files) {
        if (-not (Test-Path (Join-Path $Shaders $f))) {
            throw "Shader eksik: $f (klasor: $Shaders)"
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
    throw 'Zincir dosyasi hicbir klasore yazilamadi.'
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
        if ($inW -le 0 -or $inH -le 0) { throw 'Girdi cozunurlugu okunamadi; katsayi (2x/3x/4x) secin.' }
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

# --- RIFE 2x kare interpolasyonu (istege bagli) ---
# Video once vspipe+VapourSynth'te RIFE ile 2x fps'e cikarilir, y4m olarak
# ffmpeg'e borulanir; shader zinciri ve kodlama ffmpeg tarafinda ayni kalir.
$VapourDir = Join-Path $Root 'vapoursynth'
$VpyScript = Join-Path $VapourDir 'rife_encode.vpy'

function Find-RifeSupport {
    $r = @{ Ok = $false; Vspipe = ''; RifeDll = ''; ModelDir = ''; SourceDll = ''; Reason = '' }
    $vs = Get-Command vspipe.exe -ErrorAction SilentlyContinue
    if (-not $vs) { $r.Reason = 'vspipe.exe PATH''te yok (Python + "pip install vapoursynth" gerekir)'; return $r }
    $r.Vspipe = $vs.Source
    # RIFE eklentisi/modeli: once proje klasoru, sonra mpv kurulumu
    foreach ($d in @($VapourDir, (Join-Path $env:APPDATA 'mpv\vapoursynth'))) {
        $dll = Join-Path $d 'librife_windows_x86-64.dll'
        $mod = Join-Path $d 'models\rife-v4.6_ensembleFalse'
        if ((Test-Path $dll) -and (Test-Path $mod)) { $r.RifeDll = $dll; $r.ModelDir = Join-Path $d 'models'; break }
    }
    if (-not $r.RifeDll) { $r.Reason = 'RIFE eklentisi/modeli bulunamadi (setup.ps1 calistirin)'; return $r }
    $bs = Join-Path $VapourDir 'bestsource.dll'
    if (-not (Test-Path $bs)) { $r.Reason = 'bestsource.dll eksik (setup.ps1 calistirin)'; return $r }
    $r.SourceDll = $bs
    if (-not (Test-Path $VpyScript)) { $r.Reason = 'rife_encode.vpy eksik'; return $r }
    $r.Ok = $true
    return $r
}
$script:Rife = Find-RifeSupport
$script:CurFps = 0.0

if ($SelfTest) {
    'ffmpeg: ' + (Test-Path $FFmpeg)
    foreach ($m in $Modes.Keys) {
        $c = Get-ChainFile $m
        '{0} -> {1} ({2:N0} KB)' -f $m, $c, ((Get-Item $c).Length/1KB)
    }
    foreach ($s in @('2x (girdinin 2 kati)','4x (cift modlar tam guc)','1080p (Full HD)','1440p (QHD)','2160p (4K)')) {
        $t = Resolve-Target $s 1920 1080
        '{0} [1920x1080] -> w={1} h={2} tag={3}' -f $s, $t.W, $t.H, $t.Tag
    }
    'rife-destek: {0}{1}' -f $script:Rife.Ok, $(if (-not $script:Rife.Ok) { ' (' + $script:Rife.Reason + ')' } else { '' })
    if ($script:Rife.Ok) {
        # input verilmeyince vpy 48 karelik BlankClip uretir; "Frames: 96" gorunmesi
        # iki DLL'in yuklendigini ve RIFE'in GPU'da 2x kurulabildigini kanitlar
        $ErrorActionPreference = 'Continue'
        $o = & $script:Rife.Vspipe --info -a "rife_dll=$($script:Rife.RifeDll)" -a "source_dll=$($script:Rife.SourceDll)" -a "model_dir=$($script:Rife.ModelDir)" $VpyScript 2>&1 | Out-String
        $ErrorActionPreference = 'Stop'
        'rife-vpy: ' + $(if ($o -match 'Frames:\s*96') { 'OK (48 kare -> 96)' } else { 'HATA: ' + $o.Trim() })
    }
    exit 0
}

# ================= GUI =================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Aniflow - Anime4K / FSRCNNX Video Upscaler - Daily Dana'
$form.Size = New-Object System.Drawing.Size(690, 720)
$form.MinimumSize = $form.Size
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

function Add-Label($text, $x, $y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.AutoSize = $true; $form.Controls.Add($l); return $l
}

# --- Kuyruk ---
Add-Label 'Kuyruk (dosyalari buraya surukleyin, ciktilar kaynak klasore yazilir):' 15 15 | Out-Null
$lst = New-Object System.Windows.Forms.ListBox
$lst.Location = New-Object System.Drawing.Point(15, 38)
$lst.Size = New-Object System.Drawing.Size(550, 112)
$lst.Anchor = 'Top,Left,Right'
$lst.AllowDrop = $true
$lst.HorizontalScrollbar = $true
$form.Controls.Add($lst)

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = 'Ekle...'; $btnAdd.Location = New-Object System.Drawing.Point(575, 38)
$btnAdd.Size = New-Object System.Drawing.Size(85, 28); $btnAdd.Anchor = 'Top,Right'
$form.Controls.Add($btnAdd)
$btnDel = New-Object System.Windows.Forms.Button
$btnDel.Text = 'Kaldir'; $btnDel.Location = New-Object System.Drawing.Point(575, 72)
$btnDel.Size = New-Object System.Drawing.Size(85, 28); $btnDel.Anchor = 'Top,Right'
$form.Controls.Add($btnDel)
$btnClr = New-Object System.Windows.Forms.Button
$btnClr.Text = 'Temizle'; $btnClr.Location = New-Object System.Drawing.Point(575, 106)
$btnClr.Size = New-Object System.Drawing.Size(85, 28); $btnClr.Anchor = 'Top,Right'
$form.Controls.Add($btnClr)

# --- Mod / kodlayici / kalite ---
Add-Label 'Shader modu:' 15 162 | Out-Null
$cmbMode = New-Object System.Windows.Forms.ComboBox
$cmbMode.Location = New-Object System.Drawing.Point(15, 185)
$cmbMode.Size = New-Object System.Drawing.Size(250, 24)
$cmbMode.DropDownStyle = 'DropDownList'
$Modes.Keys | ForEach-Object { [void]$cmbMode.Items.Add($_) }
$cmbMode.SelectedIndex = 0
$form.Controls.Add($cmbMode)

Add-Label 'Kodlayici:' 285 162 | Out-Null
$cmbEnc = New-Object System.Windows.Forms.ComboBox
$cmbEnc.Location = New-Object System.Drawing.Point(285, 185)
$cmbEnc.Size = New-Object System.Drawing.Size(215, 24)
$cmbEnc.DropDownStyle = 'DropDownList'
$Encoders.Keys | ForEach-Object { [void]$cmbEnc.Items.Add($_) }
$cmbEnc.SelectedIndex = 0
$form.Controls.Add($cmbEnc)

Add-Label 'Kalite (dusuk = iyi):' 520 162 | Out-Null
$numQ = New-Object System.Windows.Forms.NumericUpDown
$numQ.Location = New-Object System.Drawing.Point(520, 185)
$numQ.Size = New-Object System.Drawing.Size(70, 24)
$numQ.Minimum = 1; $numQ.Maximum = 51; $numQ.Value = 18
$form.Controls.Add($numQ)

# --- Cozunurluk / ses / bitince ---
Add-Label 'Cikti cozunurlugu:' 15 220 | Out-Null
$cmbScale = New-Object System.Windows.Forms.ComboBox
$cmbScale.Location = New-Object System.Drawing.Point(15, 243)
$cmbScale.Size = New-Object System.Drawing.Size(250, 24)
$cmbScale.DropDownStyle = 'DropDownList'
@('2x (girdinin 2 kati)','3x (girdinin 3 kati)','4x (girdinin 4 kati - cift modlar tam guc)',
  '1080p (Full HD)','1440p (QHD)','2160p (4K)') | ForEach-Object { [void]$cmbScale.Items.Add($_) }
$cmbScale.SelectedIndex = 0
$form.Controls.Add($cmbScale)

Add-Label 'Ses:' 285 220 | Out-Null
$cmbAudio = New-Object System.Windows.Forms.ComboBox
$cmbAudio.Location = New-Object System.Drawing.Point(285, 243)
$cmbAudio.Size = New-Object System.Drawing.Size(150, 24)
$cmbAudio.DropDownStyle = 'DropDownList'
$AudioOpts.Keys | ForEach-Object { [void]$cmbAudio.Items.Add($_) }
$cmbAudio.SelectedIndex = 0
$form.Controls.Add($cmbAudio)

Add-Label 'Bitince:' 455 220 | Out-Null
$cmbFinish = New-Object System.Windows.Forms.ComboBox
$cmbFinish.Location = New-Object System.Drawing.Point(455, 243)
$cmbFinish.Size = New-Object System.Drawing.Size(205, 24)
$cmbFinish.DropDownStyle = 'DropDownList'
$FinishOpts | ForEach-Object { [void]$cmbFinish.Items.Add($_) }
$cmbFinish.SelectedIndex = 0
$form.Controls.Add($cmbFinish)

# --- Ek filtreler ---
$chkDeband = New-Object System.Windows.Forms.CheckBox
$chkDeband.Text = 'Deband (renk bantlari)'
$chkDeband.Location = New-Object System.Drawing.Point(15, 280)
$chkDeband.AutoSize = $true
$form.Controls.Add($chkDeband)
$chkDenoise = New-Object System.Windows.Forms.CheckBox
$chkDenoise.Text = 'Denoise (hqdn3d)'
$chkDenoise.Location = New-Object System.Drawing.Point(210, 280)
$chkDenoise.AutoSize = $true
$form.Controls.Add($chkDenoise)
$chkRife = New-Object System.Windows.Forms.CheckBox
$chkRife.Text = 'RIFE 2x kare interpolasyonu'
$chkRife.Location = New-Object System.Drawing.Point(405, 280)
$chkRife.AutoSize = $true
$form.Controls.Add($chkRife)

# --- Dugmeler ---
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = 'Baslat'
$btnStart.Location = New-Object System.Drawing.Point(15, 312)
$btnStart.Size = New-Object System.Drawing.Size(115, 32)
$form.Controls.Add($btnStart)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Iptal'
$btnCancel.Location = New-Object System.Drawing.Point(140, 312)
$btnCancel.Size = New-Object System.Drawing.Size(115, 32)
$btnCancel.Enabled = $false
$form.Controls.Add($btnCancel)

$btnPrev = New-Object System.Windows.Forms.Button
$btnPrev.Text = 'Onizleme (10 sn)'
$btnPrev.Location = New-Object System.Drawing.Point(285, 312)
$btnPrev.Size = New-Object System.Drawing.Size(150, 32)
$form.Controls.Add($btnPrev)

$btnCmp = New-Object System.Windows.Forms.Button
$btnCmp.Text = 'Karsilastir (yan yana)'
$btnCmp.Location = New-Object System.Drawing.Point(445, 312)
$btnCmp.Size = New-Object System.Drawing.Size(170, 32)
$form.Controls.Add($btnCmp)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = New-Object System.Drawing.Point(15, 356)
$bar.Size = New-Object System.Drawing.Size(645, 22)
$bar.Anchor = 'Top,Left,Right'
$form.Controls.Add($bar)

$lblStatus = Add-Label 'Hazir.' 15 384

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(15, 410)
$txtLog.Size = New-Object System.Drawing.Size(645, 250)
$txtLog.Anchor = 'Top,Bottom,Left,Right'
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($txtLog)

function Log([string]$msg) {
    $txtLog.AppendText(('[{0:HH:mm:ss}] {1}{2}' -f (Get-Date), $msg, [Environment]::NewLine))
}

# --- Durum ---
$state = @{
    Proc = $null; Duration = 0; ProgFile = Join-Path $TempDir 'progress.txt'
    ErrFile = Join-Path $TempDir 'stderr.txt'; ErrOffset = 0; OutPath = ''
    Queue = New-Object System.Collections.ArrayList; Index = 0
    Kind = 'queue'   # queue | preview | compare
    Cancelled = $false; RifeJob = $false
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
    $dlg.Filter = 'Video|*.mkv;*.mp4;*.avi;*.webm;*.mov;*.ts;*.m2ts;*.wmv|Tum dosyalar|*.*'
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
        Log 'UYARI: dosya adinda % & ^ ! var - RIFE bu dosya icin atlandi (cmd kisiti).'
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
            $ffArgs += @('-map','0:v:0','-map','1:a?','-map','1:s?','-map','1:t?','-map_metadata','1','-map_chapters','1')
        } else {
            $ffArgs += @('-map','0:v:0','-map','0:a?','-map','0:s?','-map','0:t?')
        }
        $ffArgs += & $Encoders[$cmbEnc.SelectedItem] ([int]$numQ.Value)
        $ffArgs += $AudioOpts[$cmbAudio.SelectedItem]
        $ffArgs += @('-c:s','copy','-c:t','copy')
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

function Start-QueueItem {
    $in = $state.Queue[$state.Index]
    if (-not (Test-Path $in)) { Log "ATLANDI (bulunamadi): $in"; Skip-Next; return }
    $chain = Get-ChainFile $cmbMode.SelectedItem
    $mi = Get-MediaInfo $in
    $state.Duration = $mi.Duration
    $script:CurFps = $mi.Fps
    $script:tgt = Resolve-Target $cmbScale.SelectedItem $mi.W $mi.H
    $d = Split-Path $in -Parent
    $n = [IO.Path]::GetFileNameWithoutExtension($in)
    $rifeTag = ''
    if ($chkRife.Checked -and $script:Rife.Ok) { $rifeTag = '_rife' }
    $out = Join-Path $d ('{0}_{1}{2}_upscale.mkv' -f $n, $script:tgt.Tag, $rifeTag)
    $lblStatus.Text = 'Dosya {0}/{1}: {2}' -f ($state.Index+1), $state.Queue.Count, (Split-Path $in -Leaf)
    Log ('--- [{0}/{1}] {2} ({3}x{4}, {5:N1} sn) -> {6} x {7}' -f ($state.Index+1), $state.Queue.Count, (Split-Path $in -Leaf), $mi.W, $mi.H, $mi.Duration, $script:tgt.W, $script:tgt.H)
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
    $lblStatus.Text = 'Kuyruk tamamlandi ({0} dosya).' -f $state.Queue.Count
    Log '=== KUYRUK TAMAMLANDI ==='
    switch ($cmbFinish.SelectedItem) {
        'Ses cal'                     { [System.Media.SystemSounds]::Asterisk.Play() }
        'Bilgisayari uyut'            { Log 'Uyku moduna geciliyor...'; & rundll32.exe powrprof.dll,SetSuspendState 0,1,0 }
        'Bilgisayari kapat (30 sn)'   { Log 'KAPATMA 30 sn icinde! Iptal: shutdown /a'; & shutdown.exe /s /t 30 }
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
    # ExitCode bos donerse (handle gec erisim) cikti dosyasi + progress=end'e bak
    if ($null -eq $code) {
        $prog = Get-Content $state.ProgFile -Raw -ErrorAction SilentlyContinue
        if ($prog -match 'progress=end' -and (Test-Path $state.OutPath)) { $code = 0 }
    }
    $ok = ($code -eq 0 -and (Test-Path $state.OutPath))
    if ($ok) {
        $mb = (Get-Item $state.OutPath).Length / 1MB
        Log ('TAMAM ({0:N1} MB) -> {1}' -f $mb, $state.OutPath)
    } elseif ($code -eq -1 -or $state.Cancelled) {
        $state.Cancelled = $false
        Log 'Iptal edildi.'
        Set-Busy $false; $lblStatus.Text = 'Iptal edildi.'
        return
    } else {
        $hint = "Donanim kodlayici sectiyseniz bu GPU desteklemiyor olabilir; x264'u deneyin."
        if ($state.RifeJob) { $hint = "RIFE hattinda hata olabilir - log'daki vspipe satirlarina bakin." }
        Log "HATA: kodlama $code kodu ile bitti. $hint"
    }
    switch ($state.Kind) {
        'queue'   { Skip-Next }
        default   {
            Set-Busy $false
            if ($ok) { $lblStatus.Text = 'Hazir.'; Start-Process $state.OutPath }
            else     { $lblStatus.Text = 'Onizleme/karsilastirma basarisiz - log''a bakin.' }
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
    if (Test-Path $state.ProgFile) {
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
                    $eta = ' - kalan ~' + [TimeSpan]::FromSeconds($rem).ToString('hh\:mm\:ss')
                }
                $pfx = ''
                if ($state.Kind -eq 'queue' -and $state.Queue.Count -gt 1) { $pfx = 'Dosya {0}/{1} - ' -f ($state.Index+1), $state.Queue.Count }
                $lblStatus.Text = "$pfx%$pct  (hiz: $spd$eta)"
            }
        }
    }
    if ($state.Proc -and $state.Proc.HasExited) { Complete-File }
})

$btnStart.Add_Click({
    try {
        if ($lst.Items.Count -eq 0) { throw 'Kuyruk bos - dosya ekleyin.' }
        if (-not (Test-Path $FFmpeg)) { throw "ffmpeg bulunamadi: $FFmpeg" }
        $state.Queue.Clear()
        $lst.Items | ForEach-Object { [void]$state.Queue.Add($_) }
        $state.Index = 0
        $state.Kind = 'queue'
        Set-Busy $true
        Start-QueueItem
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Hata', 'OK', 'Warning') | Out-Null
    }
})

# Onizleme/karsilastirma: secili (yoksa ilk) dosyanin ORTASINDAN 10 sn
function Get-SampleSource {
    if ($lst.Items.Count -eq 0) { throw 'Once kuyruga dosya ekleyin.' }
    $idx = $lst.SelectedIndex
    if ($idx -lt 0) { $idx = 0 }
    return $lst.Items[$idx]
}

$btnPrev.Add_Click({
    try {
        $in = Get-SampleSource
        $chain = Get-ChainFile $cmbMode.SelectedItem
        $mi = Get-MediaInfo $in
        $state.Duration = [Math]::Min(10, $mi.Duration)
        $script:CurFps = $mi.Fps
        $script:tgt = Resolve-Target $cmbScale.SelectedItem $mi.W $mi.H
        $mid = [Math]::Max(0, $mi.Duration/2 - 5)
        $state.Kind = 'preview'
        Set-Busy $true
        $lblStatus.Text = 'Onizleme hazirlaniyor...'
        Log ('--- Onizleme: {0} (orta nokta {1:N0}. sn)' -f (Split-Path $in -Leaf), $mid)
        Start-Job2 $in (Join-Path $TempDir 'onizleme.mkv') @($mid, 10) $null $chain
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Hata', 'OK', 'Warning') | Out-Null
    }
})

$btnCmp.Add_Click({
    try {
        $in = Get-SampleSource
        $chain = Get-ChainFile $cmbMode.SelectedItem
        $mi = Get-MediaInfo $in
        if ($mi.W -le 0) { throw 'Girdi cozunurlugu okunamadi.' }
        $state.Duration = [Math]::Min(10, $mi.Duration)
        $tgt = Resolve-Target $cmbScale.SelectedItem $mi.W $mi.H
        $mid = [Math]::Max(0, $mi.Duration/2 - 5)
        # Sol: klasik lanczos, sag: shader zinciri - ayni boyutta yan yana
        $fc = ('[0:v]split=2[a][b];[b]scale={0}:{1}:flags=lanczos[pl];[a]libplacebo=w={0}:h={1}:custom_shader_path={2}[up];[pl][up]hstack=inputs=2' -f $tgt.NumW, $tgt.NumH, (Split-Path $chain -Leaf))
        $state.Kind = 'compare'
        Set-Busy $true
        $lblStatus.Text = 'Karsilastirma hazirlaniyor...'
        if ($chkRife.Checked) { Log 'Not: karsilastirma RIFE olmadan yapilir.' }
        Log ('--- Karsilastirma: sol=lanczos, sag={0}' -f $cmbMode.SelectedItem)
        Start-Job2 $in (Join-Path $TempDir 'karsilastirma.mkv') @($mid, 10) $fc $chain
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Hata', 'OK', 'Warning') | Out-Null
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

Log "Kok klasor: $Root"
if (-not $script:Rife.Ok) {
    $chkRife.Enabled = $false
    Log "RIFE devre disi: $($script:Rife.Reason)"
}
Log 'Hazir. Kuyruga video ekleyin; Onizleme/Karsilastir tek dosyayla, Baslat tum kuyrukla calisir.'
[void]$form.ShowDialog()
