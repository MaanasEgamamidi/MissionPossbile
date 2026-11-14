extends SceneTree
## Run externally with --main-pack <export.pck> to verify exported texture remaps and local JSON.
func _initialize() -> void:
	var failures := 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cassette_briefings.json"))
	if not data is Dictionary or (data.get("cassettes", []) as Array).size() != 6:
		print("PACK FAIL briefing catalog")
		quit(1)
		return
	for record: Dictionary in data.cassettes:
		var texture := ResourceLoader.load(String(record.image_path)) as Texture2D
		var valid := texture != null and texture.get_width() >= 600 and (record.pages as Array).size() == 2
		var catalog: Script = load("res://scripts/cassettes/cassette_catalog.gd")
		valid = valid and not (catalog.metadata(String(record.id)) as Dictionary).is_empty()
		print("PACK PASS " if valid else "PACK FAIL ", record.id)
		if not valid: failures += 1
	print("PACK RESULT ", 6 - failures, "/6")
	quit(0 if failures == 0 else 1)
