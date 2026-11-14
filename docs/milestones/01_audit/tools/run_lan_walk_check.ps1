# Baseline check of the existing LAN Walk Godot prototype: one headless host + N headless clients on loopback,
# using the project's documented test flags (-- --host / --join=IP / --autowalk / --report). Logs go to -Out.
# Nothing in the project source is edited; Godot may refresh its own .godot cache folder.
param([string]$Project = "G:\nasa app\lan_walk", [int]$Clients = 3, [int]$Seconds = 12,
      [string]$Out = "G:\nasa app\mars_colony_godot\docs\milestones\01_audit\evidence\checks\lan_walk",
      [string]$Godot = "C:\Users\josev\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
New-Item -ItemType Directory -Force $Out | Out-Null
$procs = @()
function Launch($name, $extra) {
  $a = @('--headless', '--path', "`"$Project`"", '--') + $extra
  Start-Process -FilePath $Godot -ArgumentList $a -PassThru -NoNewWindow -RedirectStandardOutput "$Out\$name.out.txt" -RedirectStandardError "$Out\$name.err.txt"
}
$procs += Launch 'host' @('--host', '--autowalk', '--report')
Start-Sleep -Milliseconds 2500
for ($i = 1; $i -le $Clients; $i++) {
  $procs += Launch "client$i" @('--join=127.0.0.1', '--autowalk', '--report')
  Start-Sleep -Milliseconds 1200
}
$null = $procs | Wait-Process -Timeout $Seconds -ErrorAction SilentlyContinue
foreach ($p in $procs) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
# the console wrapper starts the real editor binary as a child; make sure no headless test instance is left behind
Get-CimInstance Win32_Process -Filter "Name like 'Godot%'" | Where-Object { $_.CommandLine -match '--headless' -and $_.CommandLine -match [regex]::Escape($Project) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-ChildItem $Out -Filter *.txt | ForEach-Object { "===== $($_.Name) ($($_.Length) bytes)"; Get-Content $_.FullName -Tail 9 }
