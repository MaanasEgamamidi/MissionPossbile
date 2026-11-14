# Rebuild the Godot side from the exported data: materials -> import -> world scene.
#   & "G:\nasa app\mars_colony_godot\tools\build.ps1" [-SkipImport]
param([string]$Project = "G:\nasa app\mars_colony_godot", [switch]$SkipImport,
      [string]$Godot = "C:\Users\josev\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
      [string]$Log = "G:\nasa app\docs\milestones\02_import\evidence\build")
New-Item -ItemType Directory -Force $Log | Out-Null
py -I (Join-Path $Project "tools\gen_materials.py") $Project
if (-not $SkipImport) {
  $t = Get-Date
  & $Godot --headless --path $Project --import *> "$Log\import.log"
  "import exit=$LASTEXITCODE secs=$([int]((Get-Date) - $t).TotalSeconds)"
  Select-String -Path "$Log\import.log" -Pattern "ERROR|SCRIPT ERROR|Parse Error|Failed" | Select-Object -First 12 | ForEach-Object { $_.Line }
}
$t = Get-Date
& $Godot --headless --path $Project --script res://tools/godot/build_world.gd *> "$Log\build_world.log"
"build_world exit=$LASTEXITCODE secs=$([int]((Get-Date) - $t).TotalSeconds)"
Select-String -Path "$Log\build_world.log" -Pattern "ERROR|SCRIPT ERROR|Parse Error|build_world:" | Select-Object -First 12 | ForEach-Object { $_.Line }
