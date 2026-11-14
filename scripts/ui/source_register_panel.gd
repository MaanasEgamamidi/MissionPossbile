class_name SourceRegisterPanel
extends UiPanel
## STUB owned by worker B. Replace the body; keep the class name and public methods.


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	var label := Label.new()
	label.text = "Sources (not built yet)"
	add_child(label)


func panel_title() -> String:
	return "Sources"


## Opens the register at one source or one claim id (for example from an ExplainButton).
func show_entry(_id: String) -> void:
	pass
