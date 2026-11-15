class_name StormOutlook
extends RefCounted
## Plain words about the dust weather for the HUD, read from state.weather and state.weather_queue (WeatherSystem).
## The storms are archive observations from Jezero played faster, not a forecast for this colony: every count the HUD
## shows says "expected in the game", never "forecast".

const SOL := GameConfig.SOL_HOURS


## {"phase": "calm" | "warned" | "storm", "hours": game hours until it starts (warned) or ends (storm), "text": short
## chip words, "severity": 0..1}.
static func now(state: ColonyState) -> Dictionary:
	var w := state.weather
	var phase := String(w.get("phase", "calm"))
	if phase == "warned":
		var warning: Dictionary = w.get("warning", {})
		var h := maxf(0.0, float(warning.get("starts_at_hours", state.sim_hours)) - state.sim_hours)
		return {"phase": "warned", "hours": h, "text": "Dust storm in %s" % _h(h), "severity": float(warning.get("severity", 0.0))}
	if phase in ["rising", "peak", "falling"]:
		var id := String(w.get("event_id", ""))
		for e: Dictionary in state.weather_queue:
			if String(e.get("id", "")) == id:
				var end := float(e.get("at_hours", 0.0)) + float(e.get("duration_hours", 0.0))
				var left := maxf(0.0, end - state.sim_hours)
				return {"phase": "storm", "hours": left, "text": "Dust storm · %s left" % _h(left), "severity": float(e.get("severity", 0.0))}
		return {"phase": "storm", "hours": 0.0, "text": "Dust storm", "severity": 0.0}
	return {"phase": "calm", "hours": 0.0, "text": "", "severity": 0.0}


## Storms the game has lined up to start within the next `sols` sols (not counting one already warned or running).
static func expected(state: ColonyState, sols: float) -> int:
	var n := 0
	var until := state.sim_hours + sols * SOL
	for e: Dictionary in state.weather_queue:
		var at := float(e.get("at_hours", -1.0))
		if at > state.sim_hours and at <= until and not bool(e.get("warned", false)):
			n += 1
	return n


## The Mission Control card's title for a warning, five words at most: "Dust storm in 6 h".
static func warning_title(state: ColonyState) -> String:
	var n := now(state)
	return String(n.text) if String(n.phase) == "warned" else "Dust storm coming"


## The ONE thing to do when a warning comes in, for the HUD (nine words at most). The whole advice (warning_advice)
## stays readable in the Power & life support drawer's message list.
static func warning_line(_state: ColonyState) -> String:
	return "Go inside. Charge the battery."


## What to tell the crew when a warning comes in: how long, what it does, what to do, and how many more are lined up.
## Too long for the HUD: the card shows warning_title() and warning_line(), this is kept for the message list.
static func warning_advice(state: ColonyState) -> String:
	var n := now(state)
	var more := expected(state, 5.0)
	var sev := float(n.get("severity", 0.0))
	var size := "A small" if sev < 0.35 else ("A strong" if sev > 0.7 else "A")
	var text := "%s dust storm starts in about %s. Dust will darken the sky and the solar panels will make less power. Get everyone outside back in, charge the battery while the Sun is up, and switch off what you do not need." % [
		size, _h(float(n.get("hours", 0.0)))]
	if more > 0:
		text += " After it, %d more dust storm%s %s lined up in the next 5 sols." % [more, "" if more == 1 else "s", "is" if more == 1 else "are"]
	text += " (Jezero archive patterns played faster, not a forecast.)"
	return text


static func _h(hours: float) -> String:
	if hours >= SOL:
		return "%.1f sols" % (hours / SOL)
	return "%d h" % maxi(1, ceili(hours - 0.05))
