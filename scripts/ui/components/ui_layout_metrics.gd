class_name UiLayoutMetrics
extends RefCounted
## Shared native-container rhythm. Decorative maps, diagrams and keycaps keep their own dimensions.
const GAP_SMALL := 8
const GAP := 16
const SECTION_GAP := 24
const PANEL_PADDING := 24
const CONTENT_PADDING := 16
const CONTROL_HEIGHT := 48

static func apply(root: Node) -> void:
	configure(root)
	for child in root.get_children():
		if not child is SubViewport: apply(child)

static func configure(node: Node) -> void:
	if not node is Control or node.has_meta(&"layout_metrics_applied") or node.get_meta(&"layout_metrics_exempt", false): return
	node.set_meta(&"layout_metrics_applied", true)
	if node is BoxContainer:
		# Tight symbol/key groups remain tighter than independent content rows.
		var gap: int = node.get_theme_constant(&"separation")
		node.add_theme_constant_override(&"separation", clampi(gap, GAP_SMALL, SECTION_GAP))
	elif node is GridContainer:
		node.add_theme_constant_override(&"h_separation", GAP)
		node.add_theme_constant_override(&"v_separation", GAP)
	if node is Button and not node is CheckBox and not node is CheckButton:
		node.custom_minimum_size.y = maxf(node.custom_minimum_size.y, 44 if node is ExplainButton else CONTROL_HEIGHT)


static func fit_activity_tabs(panel: Control) -> void:
	# Native parent flows and UiRoot measure real content; activity tabs no longer impose arbitrary inner windows.
	for node in panel.find_children("*", "TabContainer", true, false):
		(node as TabContainer).custom_minimum_size.y = 0
