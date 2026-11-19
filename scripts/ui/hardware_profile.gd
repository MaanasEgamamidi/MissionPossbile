class_name HardwareProfile
extends RefCounted
## Fits the graphics to the computer the game is running on (owner 2026-11-15: "optimize the game for a laptop gpu
## 5050"). classify() rates the graphics card from its name against the RTX 4060 Ti the colony was measured on
## (score 1.0 = that card: 14-35 ms GPU per frame at 1080p High, docs/perf/benchmark_2026-11-14.md) and says what to run:
##
##   tier     score                          preset   3D render resolution
##   STRONG   0.90 and up                    High     the window's own, never changed (the authored look)
##   MID      0.50 to 0.90                   Medium   at most 1920x1200 pixels, then adaptive to hold 60 FPS
##   BASIC    under 0.50, integrated chips   Low      at most 1600x900 pixels, then adaptive to hold 60 FPS
##   UNKNOWN  name not recognised            nothing is changed (also every headless run: tests, build tools)
##
## An RTX 5050 Laptop GPU scores 0.70 (MID). The scores are estimates from public benchmark averages, not
## measurements of this game: they only pick the starting point, and the adaptive render resolution
## (perf/dynamic_resolution.gd) then measures the real GPU time on the machine itself.
## Used only while the player's "Fit to this computer" setting is on (GameSettings.graphics_auto).

enum Tier { UNKNOWN, BASIC, MID, STRONG }

const TIER_NAMES: PackedStringArray = ["Unknown", "Basic", "Mid-range", "Strong"]
## RenderingServer.get_video_adapter_type() values (RenderingDevice.DeviceType) that mean "no graphics card of its own".
const TYPE_INTEGRATED := 1
const TYPE_CPU := 4
const STRONG_SCORE := 0.9
const MID_SCORE := 0.5
## A laptop chip runs at lower power than the desktop card of the same name.
const LAPTOP_FACTOR := 0.9
const TARGET_FPS := 60.0
const INTEGRATED_TARGET_FPS := 30.0
const MID_MAX_PIXELS := 1920 * 1200
const BASIC_MAX_PIXELS := 1600 * 900

static var _current := {}


## The profile of this computer (worked out once).
static func current() -> Dictionary:
	if _current.is_empty():
		_current = classify(RenderingServer.get_video_adapter_name(), int(RenderingServer.get_video_adapter_type()))
	return _current


## The preset for this computer, or -1 when its graphics card is not recognised.
static func recommended_level() -> int:
	return int(current().get("level", -1))


## One line for the settings panel and the perf HUD, "" when the card is not recognised.
static func summary() -> String:
	var p := current()
	if int(p.get("tier", Tier.UNKNOWN)) == Tier.UNKNOWN:
		return ""
	return "%s (%s)" % [String(p.get("adapter", "")), String(p.get("tier_name", ""))]


## Rates a graphics card by its name. `device_type` is RenderingServer.get_video_adapter_type(), -1 = not known.
## Returns adapter, score, tier, tier_name, laptop, level (GraphicsQuality.Level or -1), dynamic (adaptive render
## resolution on), max_pixels (most 3D pixels drawn, 0 = no limit), min_scale and target_fps.
static func classify(adapter: String, device_type: int = -1) -> Dictionary:
	var label := adapter.strip_edges()
	var upper := label.to_upper()
	var laptop := upper.contains("LAPTOP") or upper.contains("MOBILE") or upper.contains("MAX-Q")
	var score := score_of(upper)
	if laptop and score > 0.0:
		score *= LAPTOP_FACTOR
	# A chip built into the processor (Intel UHD / Iris, Radeon 610M ...) shares the computer's memory: always Basic.
	# Apple's own chips report as integrated too, but are rated by name above.
	var integrated := device_type == TYPE_INTEGRATED or device_type == TYPE_CPU
	if integrated and not upper.contains("APPLE"):
		score = minf(score, 0.3) if score > 0.0 else 0.2
	var tier: int = Tier.UNKNOWN
	if score >= STRONG_SCORE:
		tier = Tier.STRONG
	elif score >= MID_SCORE:
		tier = Tier.MID
	elif score > 0.0:
		tier = Tier.BASIC
	var out := {
		"adapter": label, "score": score, "tier": tier, "tier_name": TIER_NAMES[tier], "laptop": laptop,
		"level": -1, "dynamic": false, "max_pixels": 0, "min_scale": 0.6, "target_fps": TARGET_FPS,
	}
	if tier == Tier.STRONG:
		out["level"] = GraphicsQuality.Level.HIGH
	elif tier == Tier.MID:
		out["level"] = GraphicsQuality.Level.MEDIUM
		out["dynamic"] = true
		out["max_pixels"] = MID_MAX_PIXELS
	elif tier == Tier.BASIC:
		out["level"] = GraphicsQuality.Level.LOW
		out["dynamic"] = true
		out["max_pixels"] = BASIC_MAX_PIXELS
		out["min_scale"] = 0.5
	if integrated and not upper.contains("APPLE") and tier != Tier.UNKNOWN:
		# Owner 2026-11-18: "30 fps low on any recent computer ... with a decent cpu and igpu". A chip in the processor
		# holds 30 FPS at a sharper picture instead of chasing 60 at the lowest render scale (docs/perf/ultra_60fps.md).
		out["target_fps"] = INTEGRATED_TARGET_FPS
	return out


## Speed of the card named in `upper` (upper case) next to an RTX 4060 Ti = 1.0; 0.0 when the name is not recognised.
static func score_of(upper: String) -> float:
	var re := RegEx.new()
	# NVIDIA GeForce: "RTX 5050", "RTX 4060 TI", "GTX 1660 SUPER"
	if re.compile("(RTX|GTX)\\s*(\\d{3,4})") == OK:
		var m := re.search(upper)
		if m != null:
			return _geforce(int(m.get_string(2)), upper)
	# AMD Radeon: "RX 7600", "RX 7600M XT", "RX 9070 XT"
	if re.compile("RX\\s*(\\d{3,4})(M?)") == OK:
		var m := re.search(upper)
		if m != null:
			var s := _radeon(int(m.get_string(1)), upper)
			return s * LAPTOP_FACTOR if m.get_string(2) == "M" else s
	# Intel Arc cards: "ARC(TM) A750", "ARC(TM) B580"
	if re.compile("ARC\\S*\\s+([AB])(\\d{3})") == OK:
		var m := re.search(upper)
		if m != null:
			return _arc(m.get_string(1), int(m.get_string(2)))
	# Apple: "APPLE M1", "APPLE M3 PRO", "APPLE M4 MAX"
	if re.compile("APPLE M(\\d)") == OK:
		var m := re.search(upper)
		if m != null:
			var s := 0.28 + 0.04 * float(int(m.get_string(1)) - 1)
			if upper.contains("ULTRA"):
				return s * 5.0
			if upper.contains("MAX"):
				return s * 3.0
			if upper.contains("PRO"):
				return s * 1.7
			return s
	return 0.0


## `model` 5050 = 50 series, class 50.
static func _geforce(model: int, upper: String) -> float:
	var series := floori(model / 100.0)
	var card_class := model % 100
	var base := 0.0
	match card_class:
		50:
			base = 0.62
		60:
			base = 0.8
		70:
			base = 1.3
		80:
			base = 1.9
		90:
			base = 2.6
		_:
			return 0.0
	var factor := 0.3
	match series:
		50:
			factor = 1.25
		40:
			factor = 1.0
		30:
			factor = 0.8
		20:
			factor = 0.65
		16:
			factor = 0.42
		10:
			factor = 0.33
	var s := base * factor
	if upper.contains(" TI") or upper.contains("SUPER"):
		s *= 1.2
	return s


## `model` 7600 = 7000 series, class 600; the newer 9070 = 9000 series, class 70 (rated like a 700).
static func _radeon(model: int, upper: String) -> float:
	var series := floori(model / 1000.0)
	var rest := model % 1000
	var card_class := rest if rest >= 100 else rest * 10
	var base := 0.0
	if card_class >= 900:
		base = 2.2
	elif card_class >= 800:
		base = 1.6
	elif card_class >= 700:
		base = 1.2
	elif card_class >= 600:
		base = 0.75
	elif card_class >= 500:
		base = 0.4
	else:
		return 0.0
	var factor := 0.3
	match series:
		9:
			factor = 1.3
		7:
			factor = 1.0
		6:
			factor = 0.8
		5:
			factor = 0.6
	var s := base * factor
	if upper.contains(" XT"):
		s *= 1.12
	return s


static func _arc(letter: String, model: int) -> float:
	if letter == "B":
		if model >= 700:
			return 1.0
		return 0.8 if model >= 500 else 0.5
	if model >= 700:
		return 0.68
	return 0.5 if model >= 500 else 0.3
