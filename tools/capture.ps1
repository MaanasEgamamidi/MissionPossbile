# Capture reference-camera views from the Godot world (needs a GPU; opens a window while it runs).
#   & "G:\nasa app\mars_colony_godot\tools\capture.ps1" -Out <dir> [-Cams beauty|all|a,b] [-Size 1920x1080] [-Frames 90] [-Off zone_slug,...] [-Night]
param([Parameter(Mandatory)][string]$Out, [string]$Cams = "beauty", [string]$Size = "1920x1080", [int]$Frames = 90, [string]$Off = "", [switch]$Night,
      [string]$Project = "G:\nasa app\mars_colony_godot",
      [string]$Godot = "C:\Users\josev\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
New-Item -ItemType Directory -Force $Out | Out-Null
$a = @('--path', $Project, '--script', 'res://tools/godot/capture_views.gd', '--', '--out', $Out, '--cams', $Cams, '--size', $Size, '--frames', "$Frames")
if ($Off) { $a += @('--off', $Off) }
if ($Night) { $a += '--night' }
$t = Get-Date
& $Godot @a *> "$Out\capture.log"
"capture exit=$LASTEXITCODE secs=$([int]((Get-Date) - $t).TotalSeconds) files=$((Get-ChildItem $Out -Filter *.png | Measure-Object).Count)"
Select-String -Path "$Out\capture.log" -Pattern "ERROR|SCRIPT ERROR|Parse Error" | Select-Object -First 10 | ForEach-Object { $_.Line.Substring(0, [Math]::Min(240, $_.Line.Length)) }
