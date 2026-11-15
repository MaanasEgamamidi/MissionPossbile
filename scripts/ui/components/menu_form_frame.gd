class_name MenuFormFrame
extends PanelContainer
## A game panel with open diagonal corner marks in the accent colour (from the options-screen reference).
func _draw() -> void:
	var ink: Color = UiTheme.palette().accent
	var length := 28.0
	draw_line(Vector2(1, length), Vector2(1, 1), ink, 2)
	draw_line(Vector2(1, 1), Vector2(length, 1), ink, 2)
	draw_line(size - Vector2(length, 1), size - Vector2.ONE, ink, 2)
	draw_line(size - Vector2.ONE, size - Vector2(1, length), ink, 2)
