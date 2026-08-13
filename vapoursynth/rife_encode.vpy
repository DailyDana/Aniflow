# DanaUpscale - RIFE 2x offline interpolation script (Daily Dana)
# Cagiran: UpscaleGUI.ps1 -> vspipe -c y4m -a key=value ... rife_encode.vpy - | ffmpeg ...
# Tum parametreler -a ile gelir; bu dosya asla yeniden yazilmaz.
import os
import vapoursynth as vs

core = vs.core

# ---- vspipe -a argumanlari (hepsi string, hepsinin varsayilani var) ----
inp        = globals().get('input', '')
rife_dll   = globals().get('rife_dll', '')
source_dll = globals().get('source_dll', '')
model_dir  = globals().get('model_dir', '')
model_name = globals().get('model', 'rife-v4.6_ensembleFalse')
start_sec  = float(globals().get('start_sec', '-1'))
dur_sec    = float(globals().get('dur_sec', '-1'))
fps_num    = int(globals().get('fps_num', '0'))    # VFR yedegi: kapsayicinin ort. fps'i
fps_den    = int(globals().get('fps_den', '1'))
gpu_thread = int(globals().get('gpu_thread', '2'))

for dll in (source_dll, rife_dll):
    if dll and os.path.exists(dll):
        try:
            core.std.LoadPlugin(dll)
        except vs.Error:
            pass  # zaten yuklu

if not inp:
    # SelfTest: video olmadan iki DLL'in yuklenip RIFE'in GPU'da kurulabildigini kanitla
    clip = core.std.BlankClip(width=640, height=360, format=vs.YUV420P8,
                              fpsnum=24000, fpsden=1001, length=48)
else:
    clip = core.bs.VideoSource(inp)
    if clip.fps_num == 0:
        # VFR kaynak: CFR olarak yeniden ac (BestSource kare cogaltip/atarak A/V senkronu korur)
        n, d = (fps_num, fps_den) if fps_num > 0 else (24000, 1001)
        clip = core.bs.VideoSource(inp, fpsnum=n, fpsden=d)

if start_sec >= 0:
    # Onizleme kirpmasi burada: tum dosyayi bastan cozmek gerekmez
    f0 = int(start_sec * clip.fps_num / clip.fps_den)
    fn = clip.num_frames if dur_sec <= 0 else min(clip.num_frames, f0 + int(dur_sec * clip.fps_num / clip.fps_den))
    clip = clip[f0:fn]

bits = clip.format.bits_per_sample
matrix = clip.get_frame(0).props.get('_Matrix', 2)
if matrix in (0, 2):
    # rgb/belirsiz: cozunurlukten tahmin (SD -> 470bg, HD -> 709)
    matrix = 5 if clip.height <= 576 else 1
    clip = core.std.SetFrameProps(clip, _Matrix=matrix)

# RIFE RGBS float bekler; kaynak cozunurlukte calisir (720p kucultme YOK - offline is)
rgb = core.resize.Bicubic(clip, format=vs.RGBS)
inter = core.rife.RIFE(rgb, factor_num=2, factor_den=1,
                       model_path=os.path.join(model_dir, model_name),
                       gpu_thread=gpu_thread, sc=True)
# 10-bit kaynaklar 10-bit kalir (y4m P10 destekler); digerleri 8-bit
outfmt = vs.YUV420P10 if bits > 8 else vs.YUV420P8
out = core.resize.Bicubic(inter, format=outfmt, matrix=matrix)
out.set_output()
