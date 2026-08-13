# Third-party components / Ucuncu taraf bilesenler

DanaUpscale's own code (UpscaleGUI.ps1, rife_encode.vpy, setup.ps1) is MIT-licensed
(see LICENSE). It builds on the following third-party work:

| Component | Author | License | Source | How obtained |
|---|---|---|---|---|
| Anime4K shaders (`shaders/Anime4K_*.glsl`) | bloc97 | MIT | https://github.com/bloc97/Anime4K | committed in this repo |
| FSRCNNX shaders (`shaders/FSRCNNX_*.glsl`) | igv | LGPL-3.0 (per file header) | https://github.com/igv/FSRCNN-TensorFlow | committed in this repo |
| KrigBilateral (`shaders/KrigBilateral.glsl`) | Shiandow | LGPL-3.0 (per file header) | https://gist.github.com/igv | committed in this repo |
| adaptive-sharpen (`shaders/adaptive-sharpen.glsl`) | bacondither | BSD-2-Clause (per file header) | https://gist.github.com/igv | committed in this repo |
| FFmpeg (`bin/ffmpeg.exe`) | FFmpeg team / BtbN builds | GPL-3.0 | https://github.com/BtbN/FFmpeg-Builds | downloaded by the user via `setup.ps1` from the official BtbN releases (not redistributed here; sources available at the same page) |
| VapourSynth | Fredrik Mellbin | LGPL-2.1 | https://github.com/vapoursynth/vapoursynth | installed by the user via `pip install vapoursynth` (optional, RIFE only) |
| BestSource (`vapoursynth/bestsource.dll`) | vapoursynth project | MIT (statically links FFmpeg libraries; their sources at the upstream release page) | https://github.com/vapoursynth/bestsource | re-hosted in this repo's `deps-v1` release, fetched by `setup.ps1` |
| VapourSynth-RIFE-ncnn-Vulkan (`vapoursynth/librife_windows_x86-64.dll`) | styler00dollar / HolyWu / nihui | MIT | https://github.com/styler00dollar/VapourSynth-RIFE-ncnn-Vulkan | re-hosted in this repo's `deps-v1` release, fetched by `setup.ps1` |
| RIFE v4.6 model (`vapoursynth/models/rife-v4.6_ensembleFalse/`) | hzwer (Practical-RIFE) | MIT | https://github.com/hzwer/Practical-RIFE | re-hosted in this repo's `deps-v1` release, fetched by `setup.ps1` |

The full license texts of the committed shaders are embedded in each `.glsl`
file header and are preserved unchanged.
