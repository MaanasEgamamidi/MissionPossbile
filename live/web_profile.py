"""Browser-only export transformations, applied to a disposable staging copy."""
from pathlib import Path
import re


def replace_function(text, name, body):
    pattern = rf'(^static func {re.escape(name)}\([^\n]*\n).*?(?=\n(?:static func |func |##)|\Z)'
    return re.sub(pattern, lambda m: m.group(1) + body + '\n', text, count=1, flags=re.M | re.S)


def configure(stage: Path):
    quality = stage / 'scripts/ui/graphics_quality.gd'
    text = quality.read_text()
    text = replace_function(text, 'default_level', '\treturn clampi(int(JavaScriptBridge.eval(\'Number(localStorage.getItem("mars-browser-quality") || 0)\')), 0, 2)')
    text = replace_function(text, 'render_scale', '\tvar budget: float = [518400.0, 921600.0, 2073600.0][clampi(level, 0, 2)]\n\treturn clampf(minf(1.0, sqrt(budget / maxf(pixels, 1.0))), 0.35, 1.0)')
    text = replace_function(text, 'upscaler', '\treturn Viewport.SCALING_3D_MODE_BILINEAR')
    text = replace_function(text, '_apply_server', '\tRenderingServer.directional_shadow_atlas_set_size(2048 if level > 0 else 1024, false)\n\tRenderingServer.global_shader_parameter_set(\"browser_detail\", level >= 2)')
    # Browser profile preserves world geometry and gameplay, dropping expensive lighting effects.
    text = text.replace('level = clampi(level, 0, Level.ULTRA)', 'level = clampi(level, 0, Level.HIGH)')
    text = text.replace('vp.mesh_lod_threshold = value("lod_px", level)', 'vp.mesh_lod_threshold = [6.0, 3.0, 2.0][clampi(level, 0, 2)]')
    text = text.replace('vp.positional_shadow_atlas_size = value("pos_atlas", level)', 'vp.positional_shadow_atlas_size = 2048 if level >= 2 else 0\n\tEngine.max_fps = clampi(int(JavaScriptBridge.eval(\'Number(localStorage.getItem("mars-browser-fps") || 60)\')), 30, 120)')
    text = text.replace('static func _apply_sun(sun: DirectionalLight3D, level: int) -> void:', 'static func _apply_sun(sun: DirectionalLight3D, level: int) -> void:\n\tsun.shadow_enabled = level > Level.LOW')
    text = text.replace('var fade: float = value("fixture_fade", level)', 'var fade: float = [18.0, 28.0, 45.0][clampi(level, 0, 2)]')
    text = text.replace('bool(a.shadow) and value("fixture_shadows", level)', 'bool(a.shadow) and level >= Level.HIGH')
    quality.write_text(text)

    settings = stage / 'scripts/ui/game_settings.gd'
    text = settings.read_text().replace('v = clampi(v, GraphicsQuality.Level.LOW, GraphicsQuality.Level.ULTRA)', 'v = GraphicsQuality.default_level()')
    settings.write_text(text)

    # WebGL GPU timing is unavailable on some browsers. Keep a predictable fixed pixel budget.
    dynamic = stage / 'perf/dynamic_resolution.gd'
    text = dynamic.read_text().replace('func wanted() -> bool:', 'func wanted() -> bool:\n\tif OS.has_feature("web"):\n\t\treturn false')
    dynamic.write_text(text)

    # A shader global enables original material detail only for the Quality profile.
    shader = stage / 'materials/colony_surface.gdshader'
    text = shader.read_text().replace('uniform vec3 albedo', 'global uniform bool browser_detail;\n\nuniform vec3 albedo', 1)
    text = text.replace('if (bump > 0.0 && bump_gain > 0.0)', 'if (browser_detail && bump > 0.0 && bump_gain > 0.0)')
    text = text.replace('fbm(p * 1.3, 3, 0.5)', '(browser_detail ? fbm(p * 1.3, 3, 0.5) : hash13(p * 1.3))')
    text = text.replace('fbm(p * 5.0, 4, 0.6)', '(browser_detail ? fbm(p * 5.0, 4, 0.6) : hash13(p * 5.0))')
    text = text.replace('fbm(p * 2.2, 5, 0.65)', '(browser_detail ? fbm(p * 2.2, 5, 0.65) : hash13(p * 2.2))')
    shader.write_text(text)

    perf = stage / 'perf/perf_settings.gd'
    text = perf.read_text().replace('var background_max_fps := 10', 'var background_max_fps := 5')
    perf.write_text(text)

    # Keep browser pointer lock in sync with the game's existing menu stack.
    ui = stage / 'scripts/ui/ui_root.gd'
    text = ui.read_text().replace(
        '\tInput.mouse_mode = _mouse_mode',
        '\tJavaScriptBridge.eval("window.MarsBrowserMouse?.setGameplay(%s)" % ("true" if _mouse_mode == Input.MOUSE_MODE_CAPTURED else "false"))\n\tInput.mouse_mode = _mouse_mode'
    )
    ui.write_text(text)
