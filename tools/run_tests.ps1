param(
	[string[]]$Tests = @("test_saves", "test_session", "test_game_services", "test_collision", "test_player"),
	[string]$LogDir = "",
	[switch]$Import
)
# Runs the headless test scripts in tests\ and prints one summary line per test.
# -Import first refreshes Godot's class list (needed after adding or renaming a class_name script).
# -LogDir keeps each test's full output as <name>.txt.
$ErrorActionPreference = "Continue"
$project = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) { throw "Godot 4.7.2 console executable not found at $godot" }
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
