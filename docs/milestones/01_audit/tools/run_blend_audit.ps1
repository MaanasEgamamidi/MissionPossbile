# Read-only headless audit of one .blend (Prompt 01). Nothing is saved back into the .blend.
#   & "G:\nasa app\mars_colony_godot\docs\milestones\01_audit\tools\run_blend_audit.ps1" -Blend <path> -Label <name>
# --factory-startup keeps user add-ons (including the live MCP server) out of the background process;
# --disable-autoexec stops scripts stored inside the .blend from running.
param([Parameter(Mandatory)][string]$Blend, [Parameter(Mandatory)][string]$Label,
      [string]$Out = "G:\nasa app\mars_colony_godot\docs\milestones\01_audit\evidence\blend_reports",
      [string]$Script = "G:\nasa app\mars_colony_godot\docs\milestones\01_audit\tools\blend_audit.py")
$launcher = "$env:LOCALAPPDATA\Microsoft\WindowsApps\blender-launcher.exe"   # the Store build only starts through this alias
New-Item -ItemType Directory -Force $Out | Out-Null
Remove-Item "$Out\$Label.error.txt" -ErrorAction SilentlyContinue
$a = @('-b', '--factory-startup', '--disable-autoexec', "`"$Blend`"", '--python', "`"$Script`"", '--', '--out', "`"$Out`"", '--label', $Label)
$t = Get-Date
$p = Start-Process -FilePath $launcher -ArgumentList $a -PassThru -Wait -NoNewWindow -RedirectStandardOutput "$Out\$Label.stdout.txt" -RedirectStandardError "$Out\$Label.stderr.txt"
"[$Label] exit=$($p.ExitCode) secs=$([int]((Get-Date) - $t).TotalSeconds)"
if (Test-Path "$Out\$Label.error.txt") { "ERROR:"; Get-Content "$Out\$Label.error.txt" }
elseif (Test-Path "$Out\$Label.summary.json") { "summary written: $Out\$Label.summary.json" }
else { "no report - stdout tail:"; Get-Content "$Out\$Label.stdout.txt" -Tail 25 -ErrorAction SilentlyContinue; Get-Content "$Out\$Label.stderr.txt" -Tail 25 -ErrorAction SilentlyContinue }
