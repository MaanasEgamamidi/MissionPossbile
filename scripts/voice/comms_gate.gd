extends RefCounted
## Tutorial comms gate (owner 2026-11-14): at the start of the tutorial the crew radio is down, so only Mission Control
## talks to the crew (its lines arrive as messages). Crew voice chat (talking and hearing, both routes) is unavailable
## until the T01 radio signal is fixed, with one clear line on the voice HUD. Outside tutorial mode, and once T01 is
## fixed, voice works exactly as before. Each machine reads the replicated state, so host and clients agree.
## Loaded by path (no class_name): const CommsGate := preload("res://scripts/voice/comms_gate.gd")

const MESSAGE := "Crew radio is down. Lock the Relay in the Command Room to talk to your crew."


## True while crew voice chat is off in this colony.
static func voice_down(state: ColonyState) -> bool:
	return state != null and TutorialSystem.crew_radio_down(state)
