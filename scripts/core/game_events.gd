class_name GameEvents
extends Node
## Signals the rest of the game listens to. UI and presentation observe these instead of polling state every frame.

## Any authoritative state change; `reason` is the action id or "tick".
signal state_changed(reason: StringName)
signal objective_changed(objective_id: StringName)
signal weather_changed(event: Dictionary)
signal upgrade_eligibility_changed(upgrade_id: StringName)
## A character was claimed or released. `peer_id` 0 = nobody.
signal crew_ownership_changed(character_id: StringName, peer_id: int)
signal zone_power_changed(zone: String, powered: bool)
signal sol_settings_changed(sol_minutes: float)
signal pause_changed(paused: bool)
signal sol_started(sol_index: int)
signal action_resolved(result: ActionResult)
## A colony system changed in a way the players should hear about at once, with its cause in words
## ("Water pump off: no power. The recycler has stopped."). level: &"info", &"warn" or &"urgent".
signal system_alert(alert_id: StringName, level: StringName, text: String)
## A character reached zero condition and was brought back to the hub. `info` holds the cost and the cache location.
signal character_recovered(character_id: StringName, info: Dictionary)
## The suit check began; it takes `seconds` real seconds and can still be cancelled.
signal suit_check_started(character_id: StringName, seconds: float)
## The suit check ended. `completed` false = cancelled, nothing changed. Tank charge is never changed by a check.
signal suit_check_finished(character_id: StringName, suit_on: bool, completed: bool)
signal game_saved(path: String, reason: StringName)
signal game_loaded(source: String)
