extends SceneTree
## C03/C04: local, traceable photographs and honest preview copy, without network access.
var passed := 0
var total := 0

func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cassette_photos.json"))
	var briefs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CassetteCatalog.DATA_PATH))
	var seen := {}
	_check("six photographs and briefings", manifest.photos.size() == 6 and briefs.cassettes.size() == 6)
	for record: Dictionary in briefs.cassettes:
		var id := String(record.id)
		var matches: Array = manifest.photos.filter(func(p: Dictionary) -> bool: return String(p.room_id) == String(record.room_id))
		_check("one source per cassette " + id, matches.size() == 1)
		if matches.size() != 1: continue
		var photo: Dictionary = matches[0]
		seen[String(photo.sha256)] = true
		_check("offline texture " + id, ResourceLoader.exists(String(record.image_path)) and load(String(record.image_path)) is Texture2D)
		var hash_context := HashingContext.new()
		hash_context.start(HashingContext.HASH_SHA256)
		var bytes := FileAccess.get_file_as_bytes(String(photo.local_path))
		hash_context.update(bytes)
		_check("verified bytes " + id, bytes.size() == int(photo.bytes) and hash_context.finish().hex_encode() == String(photo.sha256))
		var source := SourceLibrary.source(String(record.source_id))
		_check("citable official source " + id, SourceLibrary.is_citable(source) and String(source.url) == String(record.source_url) and String(source.url).begins_with("https://www.nasa.gov/"))
		_check("visible matching credit and caption " + id, String(record.credit) == String(photo.credit) and String(record.caption) == String(photo.caption) and not String(record.credit).is_empty())
		_check("source credits integrated " + id, SourceLibrary.credits().any(func(credit: Dictionary) -> bool: return (credit.get("source_ids", []) as Array).has(String(record.source_id))))
		var text := " ".join(record.pages as Array)
		var words := text.split(" ", false).size()
		# UI overhaul (2026-11-15): the tapes are short and written for the players (ages 9-12): what the room is for and
		# its repairs by their action titles. No developer words, no key list (the player's buttons are pictures).
		_check("short ready briefing (30-70 words) " + id, words >= 30 and words <= 70 and String(record.briefing_status) == "ready", str(words))
		var names_repairs := true
		for task_id: String in RepairCatalog.ROOMS[String(record.room_id)].tasks:
			if PuzzleRegistry.TITLES.has(task_id) and not text.contains(String(PuzzleRegistry.TITLES[task_id])):
				names_repairs = false
		var developer_words := false
		for word: String in ["build", "installed", "preview", "puzzle", "T0", "T1", "host"]:
			if text.contains(word):
				developer_words = true
		_check("names the room's repairs, no developer words " + id, names_repairs and not developer_words)
		_check("photo no crop and sufficient resolution " + id, photo.crop == "none" and mini(int(photo.dimensions[0]), int(photo.dimensions[1])) >= 600)
	_check("six distinct actual photo files", seen.size() == 6)
	_check("ground prototype caption honest", String((briefs.cassettes as Array).filter(func(r: Dictionary) -> bool: return r.room_id == "green_dome")[0].caption).contains("ground prototype"))
	print("RESULT %d/%d" % [passed, total])
	quit(0 if passed == total else 1)

func _check(label: String, ok: bool, detail := "") -> void:
	total += 1
	if ok: passed += 1
	print("PASS " if ok else "FAIL ", label, " ", detail)
