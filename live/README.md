# Live game

All additions live in this directory. The source game's scripts, scenes, shaders, project settings, and original export presets are unchanged. `.gdignore` prevents Godot from importing this website or its build copies.

## Preview

After building, run from the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory live/dist
```

Open http://127.0.0.1:8765/. The page has the existing intro background, a web rendering of the game's ring logo, and two buttons. Browser play opens a limitations notice first. Downloads open a Windows/Mac chooser.

## Build

Use Godot **4.7.2 stable** and its matching official export templates. Extract `web_nothreads_release.zip`, `windows_release_x86_64.exe`, and `macos.zip` from the official template archive into a local directory, then run:

```sh
python3 live/build.py --templates live/.cache/templates
```

`--target web`, `--target windows`, or `--target macos` builds just one platform. `--godot /path/to/godot` selects the engine executable. Outputs are in ignored `live/dist/`; intermediate projects and logs are in ignored `live/.build/`. Only tracked source files are staged, so build from a checkout containing the game files.

The builder copies the project and changes export configuration in those temporary copies. Web uses Compatibility, 1280×720, a 75% 3D resolution target, no MSAA, and a single-threaded template to avoid special hosting headers. Mac enables ASTC texture imports. Browser and Mac omit TwoVoIP because the repository only includes Windows libraries. The existing VoiceService handles that omission. Windows retains TwoVoIP.

## Publish to GitHub Pages

Publication is **not enabled yet**. The connected GitHub account has push access but no repository administration access. A repository owner must enable **Settings → Pages → Build and deployment → Source: GitHub Actions**.

GitHub only discovers workflows under `.github/workflows/`. The sole required addition outside `live/` is deployment configuration, not game code:

```sh
mkdir -p .github/workflows
cp live/workflows/publish.yml .github/workflows/publish-live.yml
```

Commit the `live/` sources and workflow, push, and run **Actions → Publish game → Run workflow**. No automatic deployment occurs on ordinary pushes. The workflow builds in temporary copies, publishes desktop ZIPs as GitHub Release assets, and publishes the page plus browser game to Pages. Desktop files are kept out of Pages to stay below its 1 GB site limit. Build outputs must not be committed to Git.

Expected URL after successful deployment: https://maanasegamamidi.github.io/MissionPossible/

Add that URL to the repository's About → Website field if desired. This is an expected future URL, not a verified live deployment.

## Verification and limits

The home page, platform chooser, and browser warning were checked in the local browser. The browser export reaches the game menu, but emits errors about the WebGL shader instance buffer capacity; gameplay performance and visuals are not certified. Solving that may require a browser-specific material strategy beyond export settings. Browser LAN discovery, ENet multiplayer, and voice do not work. The warning makes this clear before launch.

Windows exports successfully; it has not been run on Windows here. Mac is ad-hoc signed, not Apple-notarized; Gatekeeper may prevent ordinary launch. No notarization credentials were supplied. Mac voice binaries are absent. Desktop multiplayer requires peers to use compatible game builds on the same LAN.

Official references:
- https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html
- https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits

## Browser frame

`play.html` hosts the export in a same-origin iframe. A 1920×1080 frame scales proportionally to fit the available browser window, with black bars on other aspect ratios. ResizeObserver updates its scale on resize. Fullscreen, gamepad and autoplay permissions are passed to the game. The build writes this wrapper to `dist/play/index.html` and keeps Godot's generated files intact under `dist/play/game/`.

## Browser performance profile

`web_profile.py` transforms only the staged browser copy: Low graphics, a fixed 1280×720 canvas, a maximum 960×540 3D pixel budget, bilinear scaling, no antialiasing or light shadows, shorter fixture-light fading, coarser mesh LOD, reduced procedural material detail, and a 60 FPS ceiling. Existing browser graphics preferences are clamped to Low. Desktop exports and original game source are unchanged. This trades graphics detail for lower browser rendering cost. No gameplay or performance verification was run for this profile, at the user's request.

Browser sizing adjustment: the authored logical layout stays at 1920×1080. The export draws to a separate 1280×720 canvas, stretched proportionally inside a responsive 16:9 iframe without CSS transforms. This keeps the original UI proportions while lowering rendering cost. Not visually verified, per user instruction.

Browser cursor handling: the staged UiRoot sends its existing menu/gameplay mouse mode to mouse-capture.js. Menus release pointer lock and show the cursor. The resume-mouse-look control is shown only during gameplay when capture is lost. Desktop source is unchanged. No interaction verification was run.

Browser controls: a Fullscreen/Exit fullscreen button works from the framed and direct game pages. The loading overlay shows download progress, waits for Godot startup, and remains visible for at least two seconds. Startup errors remain readable. Changes were not interactively tested.

Browser graphics settings: the corner Settings button offers Performance (720p output, 540p 3D budget), Balanced (900p output, 720p 3D budget), and Quality (1080p output and 3D budget), plus 30/60/120 FPS caps. Settings are saved in browser storage. Apply & restart reloads the browser game; save progress first. Quality restores procedural material detail and fixture shadows, Balanced adds sun shadows. Performance remains the default. Opening the settings dialog releases the cursor. These options are not gameplay/performance tested, per user instruction.

The Settings and Fullscreen controls are icon buttons in a dedicated 56px toolbar outside the game frame. The game fits the remaining space without controls overlapping it. The direct game URL also reserves toolbar space. Not visually verified.

Controls placement: no visible toolbar bar. The two icons sit vertically in the right-side black margin; symmetric narrow side margins keep them off the game image. Not visually verified.

## Prepared release deployment

`.github/workflows/publish-live.yml` publishes an already-built site from a GitHub Release. Run **Publish live game** with the release tag containing `game-site.zip`. Windows and Mac downloads are separate release assets. This deployment path does not rebuild or playtest the game. The separate `live/workflows/publish.yml` template remains available for rebuilding exports in Actions.

## Public hosting repository

The Pages site is configured at https://udaykamboj.github.io/mission-possible-live/ using the dedicated repository https://github.com/udaykamboj/mission-possible-live. That account has administration access there. The original game repository's Pages setting is still disabled. The hosting workflow publishes `game-site.zip` from the original repository's `live-web-20261115-v1` release; Windows and Mac downloads remain in that same release. Hosting identity is recorded in `live/hosting.json`.
