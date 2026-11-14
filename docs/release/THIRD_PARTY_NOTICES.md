# Mars Colony — Third-party notices

Mars Colony is built on the software and data listed here. Each entry says where the licence statement was read.
**Only licences that could be checked from files on this computer are stated as fact. Anything else is marked
UNVERIFIED and listed under Open items.** Written 2026-11-14 for Prompt 17.

Mars Colony is not made, approved or endorsed by NASA, the Planetary Data System, LMD or any other source listed here.

## 1. Godot Engine 4.7.2-stable — MIT (Expat)

- Used for: the engine that runs the game (the Windows export template `windows_release_x86_64.exe`).
- Verified from: the Godot 4.7.2-stable binary itself (`Engine.get_license_text()`, version
  `4.7.2-stable (official)`, commit `ed1daf0bf001b61586d9930840f2f1394092c079`), read with the headless editor on 2026-11-14.
- Full licence text:

```
Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Godot's own third-party components

Godot includes third-party code under its own licences. The **full copyright lines and licence texts** are in
`GODOT_COPYRIGHT.txt` beside this file, generated from the same 4.7.2-stable binary (`Engine.get_copyright_info()` and
`Engine.get_license_info()`). The same information is in Godot's `COPYRIGHT.txt` at tag `4.7.2-stable` of the Godot
repository. The list comes from the editor build; the Windows export template contains a subset of it (for example the
Android, Wayland and editor-only parts are not used on Windows).

Components and licences as reported by the binary:

Bullet (Expat and Zlib); Linux AppStream metadata (CC0-1.0); Godot Engine logo (CC-BY-4.0); Betsy (Expat); Chipmunk2D
joint constraints (Expat); Open Dynamics Engine (BSD-3-clause); Jolt Physics (Expat); JNLM denoiser (Expat); Android Open
Source Project (Apache-2.0); ProcessPhoenix (Apache-2.0); Robert Penner's easing functions (Expat); FXAA 3.11 (BSD-3-clause
and Expat); Intel ASSAO (Expat); TAA resolve (Expat); SMAA (Expat); AccessKit (Expat); AMD FSR 1 and 2 (Expat); ANGLE
(BSD-3-clause); Arm ASTC Encoder (Apache-2.0); Basis Universal (Apache-2.0); Brotli (Expat); CA certificates (MPL-2.0);
Clipper2 (BSL-1.0); Convection Texture Tools kernels (Expat); D3D12 Memory Allocator (Expat); DirectX Headers (Expat);
doctest (Expat); dr_libs (Unlicense or MIT-0); Embree (Apache-2.0); ENet (Expat); etcpak (BSD-3-clause); DroidSans font
(Apache-2.0); Inter, JetBrains Mono, Noto Sans, Open Sans and Vazirmatn fonts (OFL-1.1); FreeType (FTL);
GamepadMotionHelpers (Expat); glad (CC0-1.0 and Apache-2.0); glslang (glslang); Graphite (Expat); Grisu2 (Expat and
Apache-2.0); HarfBuzz (HarfBuzz); ICU (Unicode); libbacktrace (BSD-3-clause); libjpeg-turbo (BSD-3-clause and IJG); KTX
(Apache-2.0); Ogg Vorbis (BSD-3-clause); libpng (Zlib); Ogg Theora (BSD-3-clause); WebP (BSD-3-clause); Manifold
(Apache-2.0); Mbed TLS (Apache-2.0); meshoptimizer (Expat); metal-cpp (Apache-2.0); mingw-std-threads (BSD-2-clause);
MiniUPnP (BSD-3-clause); MiniZip (Zlib); bcdec (Expat); fast filtering of reflection probes (Expat); FastLZ (Expat);
FastNoise Lite (Expat); libjingle (BSD-3-clause); tangent-space normal maps (Zlib); NVAPI excerpt (Expat); OK Lab (Expat);
PCG32 (Apache-2.0); PolyPartition (Expat); QOA (Expat); r128 (Unlicense); SMAZ (BSD-3-clause); SMOL-V (Unlicense or
Expat); stb (Unlicense or Expat); YUV2RGB (BSD-2-clause); msdfgen (Expat); OpenXR Loader (Apache-2.0); PCRE2
(BSD-3-clause); Recast (Zlib); RVO2 (Apache-2.0); SDL (Zlib); hidapi (BSD-3-clause); SPIRV-Cross (Apache-2.0 or Expat);
SPIRV-Headers (Expat); SPIRV-Reflect (Apache-2.0); Swappy (Apache-2.0); ThorVG (Expat); TinyEXR (BSD-3-clause); ufbx
(Expat); V-HACD (BSD-3-clause); volk (Expat); Vulkan Headers (Apache-2.0); Vulkan Memory Allocator (Expat); Wayland core
protocol and Wayland protocols (Expat); Mesa Wayland protocols (X11); Wslay (Expat); xatlas (Expat); zlib (Zlib);
Zstandard (BSD-3-clause).

The game uses Godot's built-in default font for its interface; no other font file is bundled (none is listed in
`data/credits.json` and no `.ttf`/`.otf` file is in `assets/`).

## 2. TwoVoIP 6.1 (GDExtension) — MIT

- Used for: voice chat (Opus encoding and decoding, microphone capture), `addons/twovoip/`.
- Source: https://github.com/goatchurchprime/two-voip-godot-4/releases/tag/v6.1, release asset `TwoVoIP.zip`,
  SHA-256 `01825E1FB99B483FE6EF3B43A4578F6E5CF029AE6F39C292D99EB8AF3DD0D098` (recorded in `addons/twovoip/VERSION.txt`;
  the kept archive `G:\nasa app\_tools\twovoip_6.1\TwoVoIP_v6.1.zip` was re-hashed on 2026-11-14 and matches).
- Shipped library: `libtwovoip.windows.template_release.x86_64.dll`, SHA-256
  `C9F47DF2221B5EF196E1ECFA57E7C9289556D832441F2E6FA64E2E9B86FDFCBF` (6,465,024 bytes).
- Verified from: `addons/twovoip/LICENSE.txt` (copied into the package as `licenses/TwoVoIP_LICENSE.txt`). Full text:

```
MIT License

Copyright (c) 2024 Julian Todd
Copyright (c) 2023 K. S. Ernest (iFire) Lee
Copyright (c) 2023 Gordon MacPherson
Copyright (c) 2023 Marc Weber

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 3. Libraries inside the TwoVoIP binaries — Opus, SpeexDSP, RNNoise (BSD-style) — texts UNVERIFIED locally

`addons/twovoip/VERSION.txt` states that the TwoVoIP libraries bundle **libopus**, **speexdsp** and **rnnoise** under
BSD-style licences, with the notices in the TwoVoIP project repository's third-party files. **No copy of these three
licence texts exists on this computer** (searched `addons/twovoip/` and `G:\nasa app\_tools\twovoip_6.1\`, which holds only
the TwoVoIP MIT `LICENSE.txt` and the release zip). Their exact copyright lines and licence texts must be taken from the
TwoVoIP v6.1 repository (or the upstream Opus, SpeexDSP and RNNoise projects) and added to `licenses/` before release.
See Open item 1.

## 4. Science data

### 4.1 NASA Mars 2020 MEDA (Mars Environmental Dynamics Analyzer), via the NASA Planetary Data System

- Used for: the bundled Jezero crater weather records (`data/weather/bundle/meda_*.csv`), derived and calibrated products.
- Terms as recorded in `docs/milestones/09_weather/WEATHER_DATA.md`: PDS archive data (public). The PDS Atmospheres MEDA
  page asks for this citation, reproduced here:
  J.A. Rodriguez-Manfredi et al. (2021), The Mars Environmental Dynamics Analyzer, MEDA, NASA Planetary Data System,
  DOI 10.17189/1522849.
- No other licence text was found on the pages read (per that record).

### 4.2 LMD Mars dust climatology (kriged column dust optical depth maps, dataset v2) — CC BY-SA 3.0

- Used for: dust opacity (`data/weather/bundle/lmd_cdod_my35.csv`, `lmd_cdod_my36.csv`).
- Licence: Creative Commons Attribution-ShareAlike 3.0 Unported, stated in each source file's `copyright` attribute and on
  the LMD page (per `WEATHER_DATA.md`). Credit: Montabone et al., Laboratoire de Météorologie Dynamique.
- Changes: the files were cut to the Jezero site and converted to CSV; every change is listed in the `transform` field of
  `data/weather/bundle/manifest.json`. As required by CC BY-SA 3.0, these adapted data files are shared under the same
  licence: https://creativecommons.org/licenses/by-sa/3.0/
- The full CC BY-SA 3.0 legal code is not stored locally; the URL above is the reference (Open item 3).

### 4.3 NASA and PDS reference pages

Facts shown in the game (Mars gravity, ISS water recovery, MOXIE, plant growth and others) come from NASA (NSSDCA, GISS,
JPL) and PDS pages listed with what was read in `docs/source_register.md` and in the in-game source register
(Shift + Backspace). `data/credits.json` records these as "Public information". The game's numbers for rates and balance
are game design, not NASA values.

## 5. Credits from `data/credits.json`

| Credit | By | Licence as recorded | Status |
| --- | --- | --- | --- |
| ASTRA, Junior Astronaut Mission Trainer (UI design reference only; no code or images copied) | Hamza Ali | MIT | Recorded in `credits.json`; the licence file of that repository was not read locally. Independent NASA Space Apps project, not a NASA product. |
| Godot Engine 4.7.2 | Godot Engine contributors | MIT | Verified (section 1). |
| Blender 5.3 (tool only; not part of the game) | Blender Foundation | GPL | Tool used to make models; nothing from Blender is shipped. |
| Human Base Meshes 1.4.1 (body mesh of crew version 1) | Blender Studio and community | **UNVERIFIED: CC0 (README) vs CC BY 4.0 (licence block)** | Open issue C-19 / I-12. `credits.json` says the current crew (version 2) is built from PlayerCharacter.fbx. |
| PlayerCharacter.fbx (simple-low-poly-character.zip), base of all four crew and suits | Supplied by the owner; maker not recorded | **UNKNOWN** | Open item 4. |
| Walking.fbx (Mixamo), walking animation | Mixamo; supplied by the owner | **UNKNOWN** (no licence text recorded) | Open item 4. |
| NASA and PDS science pages | NASA, PDS nodes | Public information | See section 4. |

The colony, rover, base and terrain models are the owner's own Blender work (`grand_colony.blend`, see `SOURCE_MANIFEST.md`).

## 6. Open items before public release

1. Add the full Opus, SpeexDSP and RNNoise copyright and licence texts (from the TwoVoIP v6.1 repository) to `licenses/` (issue I-57).
2. Ship `GODOT_COPYRIGHT.txt` in the package (the current `tools/build/export_windows.ps1` copies only `PLAYER_GUIDE.md`,
   `THIRD_PARTY_NOTICES.md` and the TwoVoIP licence and version files).
3. Optionally include the CC BY-SA 3.0 legal code text with the weather data.
4. Settle the licences of PlayerCharacter.fbx, Walking.fbx (Mixamo) and Human Base Meshes 1.4.1 with the owner before
   any distribution beyond private use.
5. Confirm the ASTRA repository's MIT licence from its own licence file (only the credit record was read).
