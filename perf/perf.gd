class_name Perf
extends RefCounted
## Access to the PerfSettings autoload that also works in `--script` runs (headless tests, benchmark tools): a script
## compiled before the autoload is registered cannot name it, so every perf system reads its switches through
## Perf.cfg(). Returns the autoload node (untyped, so its properties are read dynamically), or a fallback with the
## same defaults when the autoload is missing.

static var _fallback: Node = null


static func cfg():
	var tree := Engine.get_main_loop() as SceneTree
	var node: Node = tree.root.get_node_or_null("PerfSettings") if tree != null else null
	if node != null:
		return node
	if _fallback == null:
		_fallback = (load("res://perf/perf_settings.gd") as GDScript).new()
	return _fallback
