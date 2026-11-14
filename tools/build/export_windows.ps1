param(
	[string]$Out = "G:\nasa app\_build\MarsColony_windows",
	[string]$Stage = "G:\nasa app\_work\export_stage",
	[switch]$Debug
)
# Builds the Windows package (Prompt 17) with the pinned Godot 4.7.2 export templates kept inside the workspace
# (G:\nasa app\_tools\godot_4.7.2_templates, SHA-512 checked against the official SHA512-SUMS.txt when downloaded).
#  1. copies the project (no .git, saves, Blender sources, evidence) to a staging folder, so the editor's import cache
#     in the real project is never touched by the export;
#  2. imports and exports headless with the "Windows Desktop" preset (export_presets.cfg);
#  3. adds the player guide and the license notices next to the game;
#  4. lists the .pck and fails if a development file got in; writes MANIFEST.txt with every file's SHA-256.
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$godot = Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) { throw "Godot 4.7.2 console executable not found: $godot" }
$templates = "G:\nasa app\_tools\godot_4.7.2_templates\extracted\templates"
foreach ($t in "windows_release_x86_64.exe", "windows_debug_x86_64.exe") {
	if (-not (Test-Path (Join-Path $templates $t))) { throw "Export template missing: $t" }
}
if ((Get-Content (Join-Path $templates "version.txt")).Trim() -ne "4.7.2.stable") { throw "Templates are not 4.7.2.stable" }

"staging copy -> $Stage"
robocopy $project $Stage /MIR /XD .git _test_saves _test_weather assets_src evidence tmp /XF *.log /NFL /NDL /NJH /NJS /MT:16 | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item -ItemType Directory -Force $Out | Out-Null

& $godot --headless --path $Stage --import 2>&1 | Out-Null
$mode = if ($Debug) { "--export-debug" } else { "--export-release" }
$log = Join-Path $Stage "export_log.txt"
& $godot --headless --path $Stage $mode "Windows Desktop" (Join-Path $Out "MarsColony.exe") 2>&1 | Set-Content -Encoding utf8 $log
if (-not (Test-Path (Join-Path $Out "MarsColony.pck"))) { throw "Export failed; see $log" }

# Player guide and notices
$docs = Join-Path $project "docs\release"
foreach ($f in "PLAYER_GUIDE.md", "THIRD_PARTY_NOTICES.md") {
	if (Test-Path (Join-Path $docs $f)) { Copy-Item (Join-Path $docs $f) $Out }
}
New-Item -ItemType Directory -Force (Join-Path $Out "licenses") | Out-Null
Copy-Item (Join-Path $project "addons\twovoip\LICENSE.txt") (Join-Path $Out "licenses\TwoVoIP_LICENSE.txt")
Copy-Item (Join-Path $project "addons\twovoip\VERSION.txt") (Join-Path $Out "licenses\TwoVoIP_VERSION.txt")

# What went into the pack
$list = Join-Path $Out "pck_contents.json"
py -I (Join-Path $project "tools\build\pck_list.py") (Join-Path $Out "MarsColony.pck") --json $list
$files = (Get-Content $list -Raw | ConvertFrom-Json).files | ForEach-Object { $_.path }
$bad = $files | Where-Object { $_ -match "res://(tests|tools|docs|assets_src|_test_saves|_test_weather)/|/raw/|\.py$|\.md$|\.blend" }
if ($bad) { $bad | Select-Object -First 20; throw "Development files found in the pack" }
Remove-Item $list

$manifest = Join-Path $Out "MANIFEST.txt"
"Mars Colony Windows package. Built $(Get-Date -Format s) with Godot 4.7.2.stable templates ($mode)." | Set-Content -Encoding utf8 $manifest
Get-ChildItem $Out -Recurse -File | Where-Object { $_.Name -ne "MANIFEST.txt" } | ForEach-Object {
	"{0}  {1,12}  {2}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash, $_.Length, $_.FullName.Substring($Out.Length + 1)
} | Add-Content -Encoding utf8 $manifest
"package -> $Out"
Get-ChildItem $Out | Select-Object Name, Length | Format-Table -AutoSize | Out-String
