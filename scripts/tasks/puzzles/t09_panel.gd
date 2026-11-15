extends "res://scripts/tasks/puzzles/med_ui.gd"
## T09 Mixture mini-game (Med Bay, medical specialist). Stand the fallen tubes back in the rack, then sort the made-up
## practice liquids so every tube holds one kind. Select a tube, then the tube to pour into: one dose moves.
## Keyboard: Tab / arrows pick a tube, Enter / Space selects it and Enter on another tube pours. Mouse: click the tube
## picture or its button. Each liquid has a colour AND a shape (circle, triangle, square, diamond) and a name.
## Only sends moves; the host rule (t09_rule.gd) decides everything.

const Rule := preload("res://scripts/tasks/puzzles/t09_rule.gd")
## Liquid colours and shapes by reagent id (designer art values; names in Rule.REAGENTS).
const LIQUID := [Color("2ec4b6"), Color("ff70a6"), Color("ffb627"), Color("9b5de5")]
const LIQUID_SHAPE := [Shape.CIRCLE, Shape.TRIANGLE, Shape.SQUARE, Shape.DIAMOND]
const LIQUID_WORDS := ["teal, circles", "pink, triangles", "yellow, squares", "purple, diamonds"]
const RACK_BLUE := Color(0.33, 0.52, 0.82)

var tube_buttons: Array[Button] = []
var tube_boxes: Array[Control] = []
var selected := -1
var _legend: Label


func rule_script() -> Script:
	return Rule


func setup(p_services: GameServices) -> void:
	instructions = "Some test tubes fell out of the rack. Stand them back up first. Then sort the practice liquids so each tube holds just one kind: pick a tube to pour from, then the tube to pour into. One dose moves each time, onto the same kind or into an empty tube. These liquids are made up for practice, they are not real medicine."
	super.setup(p_services)
	name = "T09MixturePanel"


func build_game() -> void:
	_legend = _label("Legend", UiTheme.MUTED)
	play_area.add_child(_legend)
	var rack := HBoxContainer.new()
	rack.name = "Rack"
	rack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_area.add_child(rack)
	for i in Rule.TUBES:
		var column := VBoxContainer.new()
		column.name = "Tube%d" % (i + 1)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rack.add_child(column)
		var box := make_box("Picture", Vector2(80, 210), _paint_tube.bind(i), func(_b: Control, _p: Vector2) -> void: pick(i))
		column.add_child(box)
		tube_boxes.append(box)
		var button := make_button("Pick", "Tube %d" % (i + 1))
		button.pressed.connect(pick.bind(i))
		column.add_child(button)
		tube_buttons.append(button)


## Player picked tube i (button, picture click or keyboard).
func pick(i: int) -> void:
	if pending or succeeded or puzzle.is_empty():
		return
	var racked: Array = puzzle.racked
	var tubes: Array = puzzle.tubes
	if not racked.all(func(r: bool) -> bool: return r):
		if bool(racked[i]):
			hint("Tube %d is already standing in the rack. Pick a tube that is lying down." % (i + 1))
		else:
			send("rack", i)
		return
	if selected == -1:
		if (tubes[i] as Array).is_empty():
			hint("Tube %d is empty. Pick a tube with liquid to pour from." % (i + 1))
			return
		selected = i
		redraw()
		hint("Pouring %s from tube %d. Now pick the tube to pour into." % [Rule.reagent_name(int((tubes[i] as Array).back())), i + 1])
		return
	if selected == i:
		selected = -1
		redraw()
		hint("Pour cancelled. Pick a tube to pour from.")
		return
	var from := selected
	selected = -1
	send("pour", from * 10 + i)


func redraw() -> void:
	if puzzle.is_empty():
		return
	var tubes: Array = puzzle.tubes
	var racked: Array = puzzle.racked
	var words := PackedStringArray()
	var used := {}
	for t: Array in tubes:
		for d: int in t:
			used[d] = true
	for id: int in used.keys():
		words.append("%s = %s" % [Rule.reagent_name(id), LIQUID_WORDS[id]])
	words.sort()
	_legend.text = "Practice liquids: " + ", ".join(words) + "."
	for i in Rule.TUBES:
		var tube: Array = tubes[i]
		var text := "Tube %d: " % (i + 1)
		if not bool(racked[i]):
			text += "fallen, put it back"
		elif tube.is_empty():
			text += "empty"
		else:
			text += "%s on top (%d/%d)" % [Rule.reagent_name(int(tube.back())), tube.size(), Rule.CAPACITY]
		if i == selected:
			text += ", pouring from here"
		tube_buttons[i].text = text
		tube_boxes[i].queue_redraw()


func explain(move: Dictionary) -> String:
	var payload := int(move.get("value", 0))
	match String(move.get("move", "")):
		"rack":
			return "That tube is already standing in the rack."
		"pour":
			var tubes: Array = puzzle.get("tubes", [])
			var from := payload / 10
			var to := payload % 10
			if from >= tubes.size() or to >= tubes.size():
				return "Pick two tubes in the rack."
			var a: Array = tubes[from]
			var b: Array = tubes[to]
			if a.is_empty():
				return "Tube %d is empty. Pick a tube with liquid to pour from." % (from + 1)
			if b.size() >= Rule.CAPACITY:
				return "Tube %d is full: a tube holds %d doses. Pick another tube." % [to + 1, Rule.CAPACITY]
			if not b.is_empty() and int(b.back()) != int(a.back()):
				return "%s can only go onto %s or into an empty tube. Tube %d has %s on top." % [Rule.reagent_name(int(a.back())), Rule.reagent_name(int(a.back())), to + 1, Rule.reagent_name(int(b.back()))]
			return "That pour doesn't work. Pick a tube to pour from, then where it goes."
		"reset":
			return "Nothing to reset: the liquids are still where they started."
	return "That doesn't work here. Try something else."


func praise(move: Dictionary) -> String:
	var payload := int(move.get("value", 0))
	match String(move.get("move", "")):
		"rack":
			if (puzzle.racked as Array).all(func(r: bool) -> bool: return r):
				return "All tubes are back in the rack. Now sort the liquids: one kind per tube."
			return "Tube %d is back in the rack." % (payload + 1)
		"pour":
			var to := payload % 10
			var tube: Array = puzzle.tubes[to]
			return "Poured one dose of %s into tube %d." % [Rule.reagent_name(int(tube.back())), to + 1]
		"reset":
			return "The liquids are back where they started."
	return "Done."


func solved_text() -> String:
	return "Fixed! Every tube holds one kind of liquid and the rack is ready for the Med Bay again."


func _paint_tube(box: Control, i: int) -> void:
	if puzzle.is_empty() or i >= (puzzle.tubes as Array).size():
		return
	var pal := UiTheme.palette()
	var layers: Array = puzzle.tubes[i]
	var w := box.size.x
	var h := box.size.y
	var glass := Color(0.85, 0.92, 1.0, 0.16)
	if not bool(puzzle.racked[i]):
		# Lying on the counter, waiting to be put back.
		var r := Rect2(w * 0.08, h - 44.0, w * 0.84, 26.0)
		box.draw_rect(r, glass)
		var dose_w := r.size.x / float(Rule.CAPACITY)
		for d in layers.size():
			var id := int(layers[d])
			var cell := Rect2(r.position.x + dose_w * d + 1.0, r.position.y + 3.0, dose_w - 2.0, r.size.y - 6.0)
			box.draw_rect(cell, LIQUID[id])
			draw_shape(box, LIQUID_SHAPE[id], cell.get_center(), minf(cell.size.x, cell.size.y) * 0.3, Color(1, 1, 1, 0.9))
		box.draw_rect(r, pal.border, false, 2.0)
		draw_text_centered(box, "fallen", Vector2(w * 0.5, h - 70.0), 16, pal.warn)
		return
	var lift := 14.0 if i == selected else 0.0
	box.draw_rect(Rect2(0.0, h - 34.0, w, 12.0), RACK_BLUE)
	var tw := minf(w * 0.55, 62.0)
	var x0 := (w - tw) * 0.5
	var top := 18.0 - lift
	var bottom := h - 30.0 - lift
	var dose_h := (bottom - top - 6.0) / float(Rule.CAPACITY)
	box.draw_rect(Rect2(x0, top, tw, bottom - top), glass)
	for d in layers.size():
		var id := int(layers[d])
		var cell := Rect2(x0 + 3.0, bottom - 3.0 - dose_h * (d + 1), tw - 6.0, dose_h - 1.0)
		box.draw_rect(cell, LIQUID[id])
		draw_shape(box, LIQUID_SHAPE[id], cell.get_center(), minf(cell.size.x, cell.size.y) * 0.28, Color(1, 1, 1, 0.9))
	box.draw_rect(Rect2(x0, top, tw, bottom - top), pal.focus if i == selected else pal.border, false, 4.0 if i == selected else 2.0)
	if i == selected:
		draw_text_centered(box, "pour", Vector2(w * 0.5, top - 8.0 + lift * 0.5), 15, pal.focus)
