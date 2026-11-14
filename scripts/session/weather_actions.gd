class_name WeatherActions
extends RefCounted
## Weather actions (Prompt 09). The weather itself is run by WeatherSystem; players only answer a warning.
##   acknowledge_weather_warning  a crew member says they heard the dust warning. Every screen then shows who has
##                                heard it, so a team can check that everyone outside is on the way back.
## The action changes nothing in the simulation; it only adds the actor to state.weather.warning.acknowledged_by.


static func register(service: ActionService) -> void:
	var d := ActionService.Definition.new()
	d.id = &"acknowledge_weather_warning"
	d.check_distance = false
	d.allowed_while_paused = true
	d.check = _check
	d.apply = _apply
	service.register(d)


static func _check(ctx: ActionService.Context) -> ActionResult:
	var warning: Dictionary = (ctx.state.weather.get("warning", {}) as Dictionary)
	if warning.is_empty():
		return ActionResult.failure(ctx.request.request_id, &"missing_prerequisite")
	return null


static func _apply(ctx: ActionService.Context) -> Dictionary:
	var warning: Dictionary = ctx.state.weather.warning
	var by: Array = warning.get("acknowledged_by", [])
	var id := String(ctx.actor.id)
	if not by.has(id):
		by.append(id)
	warning["acknowledged_by"] = by
	var text := "%s has heard the dust warning." % ctx.actor.display_name
	return {"action": "acknowledge_weather_warning", "event_id": String(warning.get("event_id", "")), "acknowledged_by": by.duplicate(), "text": text}
