extends Node
## Autoload, first in the list: on a Mac, makes the built-in microphone the input before voice chat starts. When the
## Mac's input had to be switched, the game restarts once at once, because Godot only reads the input it found at launch
## (see mac_mic.gd). Runs before the menus load, so the restart is a quick blink.

const MacMic := preload("res://addons/mac_mic/mac_mic.gd")

const RESTARTED_ENV := "MARS_COLONY_MIC_RESTARTED"


func _enter_tree() -> void:
	if OS.get_name() != "macOS" or DisplayServer.get_name() == "headless" or Engine.is_editor_hint():
		return
	var result := MacMic.ensure_builtin()
	print("MacMic: ", result if result != "" else "helper not run")
	if not result.begins_with("switched") or OS.get_environment(RESTARTED_ENV) == "1":
		return
	# the restarted game inherits this, so a Mac that keeps switching back cannot cause a restart loop
	OS.set_environment(RESTARTED_ENV, "1")
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit.call_deferred()
