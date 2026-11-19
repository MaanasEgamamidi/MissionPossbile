# Graphics options and presets (2026-11-18)

Owner request: every graphics feature of a big PC game's settings menu (the reference was a set of Spider-Man 2 PC
screenshots) as its own setting; Low, Medium, High and Ultra presets set them all; changing any one makes the
settings **Custom**; and no preset turns everything to its best, so the game is only fully maxed when the player
does it by hand.

Code: `scripts/ui/graphics_quality.gd` (`OPTIONS` table: choices + the pick of each preset; `apply()` puts them into
effect), `scripts/ui/game_settings.gd` (`graphics_custom`, `set_graphics_option`, `choose_preset`, display values),
`scripts/ui/display_settings.gd` (window, monitor, frame cap, VSync, HDR), `scripts/ui/settings_panel.gd` (the
tabs), `scripts/ui/motion_blur.gd` + `materials/motion_blur.gdshader`, film grain and sharpening in
`materials/post_fx.gdshader`.

## How Custom works

- `GameSettings.graphics_quality` stays the preset the player started from; `graphics_custom` holds only the options
  changed from it (key -> choice index or slider number). Not empty = Custom (the fifth preset button). Each changed
  option shows a `*` next to its value, like the reference menu.
- Setting an option back to the preset's own value removes it from the list. Picking a preset clears the list.
  Changing anything by hand turns "Fit to this computer" off (as picking a preset already did).
- Other systems that ask "is this Low?" (`GraphicsQuality.applied_level`: half the tape sparkles, light view hops)
  still read the base preset. FSR 2 and adaptive resolution are read from the options
  (`GraphicsQuality.is_temporal` / `is_adaptive`), so DynamicResolution follows the player's own choice.
- The four presets give exactly the same engine settings as before this change (same shadows, AO, SSIL, SSR, fog,
  LOD, fixture fades, MSAA/FXAA/FSR 2, render scale), with two additions: texture filtering (anisotropic, see below)
  and Low's texture quality at Medium.

## Graphics tab

| Option | Choices (worst to best) | Low | Medium | High | Ultra |
|---|---|---|---|---|---|
| Anti-aliasing | Off, FXAA, TAA, MSAA 2x/4x/8x, FSR 2 | Off | FXAA | MSAA 2x | FSR 2 |
| Render resolution | 50-100 % | 75 | 100 | 100 | 77 |
| Adaptive resolution | Off, On | Off | Off | Off | On |
| Sharpness | 0-10 | 0 | 0 | 0 | 0 |
| Texture quality | Low, Medium, High (mip bias +1 / +0.5 / 0) | Medium | High | High | High |
| Texture filtering | Off, 2x, 4x, 8x, 16x anisotropic | 2x | 4x | 8x | 8x |
| Shadow quality | Low, Medium, High, Ultra, Max | Low | Medium | High | Ultra |
| Room light distance | Near (15 m), Medium (40 m), Full | Near | Medium | Full | Full |
| Ambient occlusion | Off, Low, Medium, High, Ultra | Off | Low | Medium | High |
| Indirect light (SSIL) | Off, Low, Medium, High, Ultra | Off | Off | Medium | High |
| Reflections (SSR) | Off, Low, Medium, High, Ultra | Off | Off | Medium | High |
| Global illumination (SDFGI) | Off, On | Off | Off | Off | Off |
| Dust haze (volumetric fog) | Off, Low, High, Ultra | Off | Off | Off | High |
| Level of detail | Low, Medium, High, Max | Low | Medium | Medium | High |
| Weather particles | Low, Medium, High | Low | Medium | High | High |
| Fullscreen effects | Off, On | On | On | On | On |
| Chromatic aberration | Off, On | On | On | On | On |
| Vignette | Off, On | On | On | On | On |
| Bloom | Off, On, High | Off | On | On | On |
| Depth of field | Off, Low, High | Off | Off | Off | Off |
| Motion blur | 0-10 (off with Less motion) | 0 | 0 | 0 | 0 |
| Film grain | 0-10 | 0 | 0 | 0 | 0 |

Ultra leaves 14 of the 22 options below their best (100 % resolution, Max shadows, Ultra AO / SSIL / reflections /
haze, global illumination, 16x filtering, Max detail, High bloom, depth of field, motion blur, film grain,
sharpness). Chromatic aberration and vignette are part of the authored look (the world's PostFX pass, 0.006 / 0.22)
and stay on in every preset; Fullscreen effects off removes that whole pass.

Notes:
- **Shadow quality Max**: Ultra's 8K atlases with the engine's "soft ultra" filtering and the sun's shadows to 300 m.
- **Texture filtering** works by switching every standard material that uses plain mipmapped filtering to the
  anisotropic kind (and back when Off). The colony's own shader materials sample no textures.
- **Global illumination** is Godot's SDFGI (real-time bounced light), the closest thing Godot has to the reference's
  ray-traced lighting. Heavy, and it changes how rooms look; no preset uses it.
- **Motion blur** is camera motion blur: a full-screen pass that reprojects each pixel with the previous frame's
  camera. Moving objects are not blurred; teleports and camera cuts are skipped. It exists only while above 0.

## Display tab (Screen)

Monitor (with more than one screen), Window mode (Windowed / Maximized / Fullscreen / Exclusive), Window size
(windowed only; fullscreen always uses the screen's own resolution, the 3D resolution is Render resolution), Aspect
ratio (Auto, 16:9, 16:10, 21:9, 4:3: black bars around the picture), Frame rate limit (Unlimited, 30, 60, 120, 144,
the monitor's refresh rate), VSync (Off, On, Adaptive, Fast = mailbox), Low latency, HDR and HDR peak brightness
(Godot 4.7's HDR output; greyed out when Windows HDR is off), Brightness and Contrast (Environment adjustments, 50 =
as lit). Display values are applied only when they change, so the perf benches keep their own VSync and frame cap.

## Not available in this game or in Godot

- **NVIDIA Reflex**: not in Godot. "Low latency" is the engine-agnostic version: with VSync on, frames are capped 3 FPS
  under the refresh rate so they never queue.
- **Refresh rate**: a game cannot switch the monitor's mode in Godot (fullscreen uses the desktop mode). The frame
  rate limit offers the monitor's rate instead.
- **Ray-traced reflections / shadows / interiors / AO, DLSS Ray Reconstruction, ray tracing range**: Godot has no
  hardware ray tracing. SDFGI and the screen-space options are the stand-ins.
- **Traffic density, crowd density, hair quality**: the colony has no traffic, crowds or hair strands.
- **Screen shake**: the game has no camera shake (only small shakes inside puzzle panels, which are puzzle feedback).
- **Field of view**: already a setting (Controls > View width).

## Checked

- Live in the game through the Godot MCP (2026-11-18): Graphics tab lists every option; choosing MSAA 4x on Low made
  the preset row Custom with "1 option changed from Low (marked *)" and put the window on 4x MSAA; motion blur 8 and
  film grain 5 created the blur pass and grain; the save loaded and the camera turned with them on; no new engine,
  script or shader errors in the log.
- `tools/perf/probe_graphics_options.gd` turns each option to its best one at a time (and all at once) and prints the
  frame and GPU time. Not measured yet: the GPU was busy with another game during the session.
- `tests/test_graphics_quality.gd` updated (Custom, five preset buttons, no preset at best everywhere, save/load of
  custom options). Not run here (the owner runs the test suites).
