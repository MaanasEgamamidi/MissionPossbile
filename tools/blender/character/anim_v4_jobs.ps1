param(
    [Parameter(Mandatory=$true)][string]$OutJson,       # jobs file to write
    [Parameter(Mandatory=$true)][string]$ReportDir,     # per-clip reports go here
    [Parameter(Mandatory=$true)][string]$SummaryPath,   # candidates summary JSON
    [string]$LiveJumpStart = 'jump_start_mx', [string]$LiveJump = 'jump_mx', [string]$LiveLand = 'land_mx',
    [string]$LiveSprint = 'sprint_mx_medium'
)
# Writes the job list for retarget_mixamo_clip.py: every walk/sprint/jump candidate plus which ones play the live names.
$ErrorActionPreference = 'Stop'
$anims = 'G:\nasa app\mars_colony_godot\assets_src\characters\anims'
$q = "$anims\quaternius_ual1\Universal Animation Library[Standard]\Unreal-Godot\UAL1_Standard.glb"
function J($o) { $o }
$old = @{ sprint = 'sprint_handmade'; jump = 'jump_old'; land = 'land_old' }
$clips = @(
  @{ target='walk_q';        source=$q; action='Walk_Loop';        mode='loop'; rm_speed_m_s=0.975 },
  @{ target='walk_q_formal'; source=$q; action='Walk_Formal_Loop'; mode='loop'; rm_speed_m_s=0.975 },
  @{ target='sprint_mx_medium';   source="$anims\MediumRun.fbx";   mode='loop'; x_offset=0.04 },
  @{ target='sprint_mx_standard'; source="$anims\StandardRun.fbx"; mode='loop' },
  @{ target='sprint_q_jog'; source=$q; action='Jog_Fwd_Loop'; mode='loop'; rm_speed_m_s=5.357 },
  @{ target='sprint_q';     source=$q; action='Sprint_Loop';  mode='loop'; rm_speed_m_s=8.25 },
  @{ target='jump_start_mx'; source="$anims\Jump.fbx"; mode='once'; start=15; end=23; x_scale=0.65; deyaw='upper'; yaw_ref_deg=0 },
  @{ target='jump_mx'; source="$anims\Jump.fbx"; mode='air'; pingpong=@(30,34); period=36; legs=0.85; upper=0.5; clearance=0.02; x_scale=0.65; deyaw='all'; yaw_ref_deg=0 },
  @{ target='land_mx'; source="$anims\Jump.fbx"; mode='once'; start=41; end=56; blend_to_idle=5; x_scale=0.65; deyaw='upper'; yaw_ref_deg=0 },
  @{ target='jump_start_q'; source=$q; action='Jump_Start'; mode='once'; start=1; end=8; vertical='pin_up'; x_scale=0.6; deyaw='upper'; yaw_ref_deg=0; stand_frame=1 },
  @{ target='jump_q'; source=$q; action='Jump_Loop'; mode='air'; upper=0.55; clearance=0.02; x_scale=0.8; stand_action='Idle_Loop'; stand_frame=0; deyaw='all'; yaw_ref_deg=0 },
  @{ target='land_q'; source=$q; action='Jump_Land'; mode='once'; start=0; end=25; speed=1.5; legs=0.45; upper=0.55; x_scale=0.6; stand_frame=37; blend_to_idle=5; deyaw='upper'; yaw_ref_deg=0 }
)
foreach ($c in $clips) {
  $c.report = Join-Path $ReportDir ($c.target + '_report.json')
  $live = @()
  if ($c.target -eq $LiveSprint) { $live += 'sprint' }
  if ($c.target -eq $LiveJumpStart) { $live += 'jump_start' }
  if ($c.target -eq $LiveJump) { $live += 'jump' }
  if ($c.target -eq $LiveLand) { $live += 'land' }
  if ($live.Count) { $c.live = $live; $c.old_names = $old }
}
$spec = @{ copies = @(@{ from = 'walk'; target = 'walk_mixamo'; sheet = $true; info = @{ source = "$anims\Walking.fbx"; seconds = 1.0667; clip_ground_speed_m_s = 1.545; ankle_gap_m = @(0.15, 0.231); note = 'current live walk (walk_retarget_report.json)' } });
           clips = $clips; summary = $SummaryPath }
$spec | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 $OutJson


