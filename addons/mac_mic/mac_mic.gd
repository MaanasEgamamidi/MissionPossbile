@tool
extends RefCounted
## Keeps voice chat on the Mac's built-in microphone (2026-11-15). Godot 4.7 on macOS fixes the microphone's sample
## rate from the Mac's default input at launch, so a Bluetooth speaker or headset as that input (8 kHz call mode)
## made voice silent, and switching inside the game cannot fix it. The `mac_mic` helper (mac_mic.c, built universal)
## makes the built-in microphone the Mac's input: the editor runs it before Play (plugin.gd), the game at launch
## (launch_check.gd, restarting once when it had to switch).

const HELPER_RES := "res://addons/mac_mic/mac_mic"


## The helper's path on disk: in the project folder, or next to the executable in an exported game. "" when missing.
static func helper_path() -> String:
	var p := ProjectSettings.globalize_path(HELPER_RES)
	if FileAccess.file_exists(p):
		return p
	p = OS.get_executable_path().get_base_dir().path_join("mac_mic")
	return p if FileAccess.file_exists(p) else ""


## Makes the built-in microphone the Mac's input. Returns "already <name>", "switched <old>|<new>", "none" (no
## built-in microphone), or "" when not on a Mac or the helper is missing or failed.
static func ensure_builtin() -> String:
	if OS.get_name() != "macOS":
		return ""
	var helper := helper_path()
	if helper == "":
		return ""
	var out: Array = []
	var code := OS.execute(helper, ["builtin"], out, true)
	var text := String(out[0]).strip_edges() if not out.is_empty() else ""
	if code != 0 and code != 2:
		push_warning("MacMic: %s builtin failed (%d): %s" % [helper, code, text])
		return ""
	return text
