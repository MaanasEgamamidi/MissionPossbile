class_name CreditsPanel
extends UiPanel
## STUB owned by worker B. Replace the body; keep the class name and public methods.


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	var label := Label.new()
	label.text = "Credits (not built yet)"
	add_child(label)


func panel_title() -> String:
	return "Credits"
