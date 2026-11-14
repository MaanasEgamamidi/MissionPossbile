# Save a screenshot of the Godot editor window that has this project open (visual proof of what is in the editor).
#   & "G:\nasa app\mars_colony_godot\tools\capture_editor_window.ps1" -Out <file.png> [-WaitSeconds 120]
param([Parameter(Mandatory)][string]$Out, [int]$WaitSeconds = 120, [string]$TitleMatch = "Mars Colony")
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinCap {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[WinCap]::SetProcessDPIAware() | Out-Null
$deadline = (Get-Date).AddSeconds($WaitSeconds)
$win = $null
while ((Get-Date) -lt $deadline) {
  $win = Get-Process | Where-Object { $_.ProcessName -like 'Godot*' -and $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match $TitleMatch -and $_.MainWindowTitle -match 'Godot Engine' } | Select-Object -First 1
  if ($win) { break }
  Start-Sleep -Milliseconds 1500
}
if (-not $win) { "no editor window titled like '$TitleMatch' found"; exit 1 }
"window: $($win.MainWindowTitle) (pid $($win.Id))"
if ([WinCap]::IsIconic($win.MainWindowHandle)) { [WinCap]::ShowWindow($win.MainWindowHandle, 9) | Out-Null }
[WinCap]::SetForegroundWindow($win.MainWindowHandle) | Out-Null
Start-Sleep -Seconds 6          # let the viewport finish drawing the scene
$r = New-Object WinCap+RECT
[WinCap]::GetWindowRect($win.MainWindowHandle, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size $w, $h))
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"saved $Out ($w x $h)"
