param(
	[string[]]$Tests = @("test_saves", "test_session", "test_game_services", "test_collision", "test_life_support", "test_food",
		"test_science", "test_progression", "test_weather_data", "test_weather", "test_ui_framework", "test_sources", "test_hud_panels",
		"test_station_panels", "test_p07_panels", "test_player", "test_net", "test_net_game", "test_game_scene", "test_graphics_quality",
		"test_rover", "test_rover_drive", "test_voice", "test_tutorial", "test_scout", "test_crew_collision", "test_pdf_fixes",
		"test_repair_foundations", "test_task_panel", "test_repair_anchors", "test_perf",
		"test_cassettes", "test_cassette_ui", "test_cassette_assets", "test_survival", "test_wear_runtime", "test_survival_hud", "test_survival_net",
		"test_hardware_profile"),
	[string]$LogDir = "",
	[switch]$Import
)
# Runs the headless test scripts in tests\ and prints one summary line per test.
# -Import first refreshes Godot's class list (needed after adding or renaming a class_name script).
# -LogDir keeps each test's full output as <name>.txt.
$ErrorActionPreference = "Continue"
$project = Split-Path -Parent $PSScriptRoot
$godot = @("Downloads\Godot_v4.7.2-stable_win64.exe", "Downloads\Godot Installs\Godot_v4.7.2-stable_win64.exe") |
	ForEach-Object { Join-Path $env:USERPROFILE "$_\Godot_v4.7.2-stable_win64_console.exe" } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $godot) { throw "Godot 4.7.2 console executable not found under Downloads" }
if ($Import) {
	$out = & $godot --headless --path $project --import 2>&1 | ForEach-Object { "$_" }
	$bad = $out | Where-Object { $_ -match "SCRIPT ERROR|Parse Error" }
	"import: " + $(if ($bad) { "SCRIPT ERRORS`n" + ($bad -join "`n") } else { "ok" })
}
if ($LogDir -ne "") { New-Item -ItemType Directory -Force $LogDir | Out-Null }
$failed = 0
foreach ($t in $Tests) {
	$start = Get-Date
	$out = & $godot --headless --path $project --script "res://tests/$t.gd" 2>&1 | ForEach-Object { "$_" }
	$code = $LASTEXITCODE
	$secs = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
	if ($LogDir -ne "") { $out | Set-Content -Encoding utf8 (Join-Path $LogDir "$t.txt") }
	$result = ($out | Where-Object { $_ -match "^RESULT " } | Select-Object -Last 1)
	$fails = @($out | Where-Object { $_ -match "^FAIL |SCRIPT ERROR|Parse Error" })
	if ($code -ne 0 -or -not $result -or $fails.Count -gt 0) { $failed++ }
	"{0,-22} exit={1} {2} ({3} s)" -f $t, $code, $(if ($result) { $result } else { "NO RESULT LINE" }), $secs
	$fails | Select-Object -First 15 | ForEach-Object { "    $_" }
}
if ($failed -gt 0) { "FAILED TESTS: $failed"; exit 1 } else { "ALL TESTS PASSED"; exit 0 }
