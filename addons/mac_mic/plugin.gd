@tool
extends EditorPlugin
## Before every Play from the editor, makes the Mac's built-in microphone the input (mac_mic.gd), so the game starts
## on it and needs no restart.

const MacMic := preload("res://addons/mac_mic/mac_mic.gd")


func _build() -> bool:
	var result := MacMic.ensure_builtin()
	if result.begins_with("switched"):
		print("MacMic: the Mac's input is now the built-in microphone (was %s)." % result.trim_prefix("switched ").get_slice("|", 0))
	return true
