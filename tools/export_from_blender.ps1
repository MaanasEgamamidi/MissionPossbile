# Reproducible derivative export: source .blend -> assets/colony/*.glb + data/*.json. The source file is never saved.
#   & "G:\nasa app\mars_colony_godot\tools\export_from_blender.ps1" [-Blend <path>] [-Report <dir>]
param([string]$Blend = "G:\nasa app\grand_colony\grand_colony.blend",
      [string]$Project = "G:\nasa app\mars_colony_godot",
      [string]$Report = "G:\nasa app\mars_colony_godot\docs\milestones\02_import\evidence\export")
$launcher = "$env:LOCALAPPDATA\Microsoft\WindowsApps\blender-launcher.exe"   # the Store build only starts through this alias
$script = Join-Path $Project "tools\blender\export_colony_glb.py"
New-Item -ItemType Directory -Force $Report | Out-Null
Remove-Item "$Report\export_report.json" -ErrorAction SilentlyContinue
$before = (Get-FileHash $Blend -Algorithm SHA256).Hash
$a = @('-b', '--factory-startup', '--disable-autoexec', "`"$Blend`"", '--python', "`"$script`"", '--', '--out', "`"$Project`"", '--report', "`"$Report`"")
$t = Get-Date
$p = Start-Process -FilePath $launcher -ArgumentList $a -PassThru -Wait -NoNewWindow -RedirectStandardOutput "$Report\export.stdout.txt" -RedirectStandardError "$Report\export.stderr.txt"
$after = (Get-FileHash $Blend -Algorithm SHA256).Hash
"exit=$($p.ExitCode) secs=$([int]((Get-Date) - $t).TotalSeconds) source_unchanged=$($before -eq $after)"
if (Test-Path "$Report\export_report.json") {
  $r = Get-Content "$Report\export_report.json" -Raw | ConvertFrom-Json
  if ($r.error) { "ERROR:"; $r.error } else { "ok=$($r.ok) detail=$($r.detail) colony_objects=$($r.colony.objects) colony_tris=$($r.colony.tris_instanced) unique_tris=$($r.colony.tris_unique) env_objects=$($r.environment.exported_objects) env_tris=$($r.environment.exported_tris)"; $r.exports | ForEach-Object { "  $($_.path)  $([int]($_.bytes / 1MB)) MB  $($_.secs)s  $($_.result)" } }
} else { "no report; stderr tail:"; Get-Content "$Report\export.stderr.txt" -Tail 20 }
