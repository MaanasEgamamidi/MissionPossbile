# Publish only the reviewed PDF repairs. Run in the user's normal PowerShell.
$ErrorActionPreference = 'Stop'
function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw 'Git stopped. Resolve the reported issue before continuing; no force push is used.' }
}
$paths = @(
    '.gitattributes', 'materials/colony_surface.gdshader',
    'scripts/core/layers.gd', 'scripts/game/game_hud.gd', 'scripts/game/game_main.gd',
    'scripts/player/player_camera_rig.gd', 'scripts/player/player_controller.gd', 'scripts/player/player_visual.gd',
    'scripts/session/builtin_actions.gd', 'scripts/session/session_service.gd', 'scripts/state/character_state.gd',
    'scripts/world/climbable_ladder.gd', 'scripts/world/climbable_ladder.gd.uid',
    'scripts/world/habitat_finish.gd', 'scripts/world/habitat_finish.gd.uid',
    'scripts/world/prop_collision.gd', 'scripts/world/suit_displays.gd', 'scripts/world/world_collision.gd',
    'tests/test_player.gd', 'tests/test_game_scene.gd', 'tests/test_pdf_fixes.gd', 'tests/test_pdf_fixes.gd.uid',
    'tests/test_crew_collision.gd.uid',
    'tools/godot/diag_pdf_assets.gd', 'tools/godot/diag_pdf_assets.gd.uid',
    'tools/godot/verify_pdf_walkthrough.gd', 'tools/godot/verify_pdf_walkthrough.gd.uid',
    'docs/milestones/pdf_bugfixes/HANDOFF.md', 'tools/publish_pdf_fixes.ps1'
)
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $remote = (& git remote get-url origin).Trim().TrimEnd('/').Replace('.git', '')
    if ($remote -ne 'https://github.com/MaanasEgamamidi/mars_colony_godot') { throw 'origin is not the approved Maanas repository.' }
    if ((& git branch --show-current).Trim() -ne 'main') { throw 'Switch to main before publishing this change set.' }
    $staged = @(& git diff --cached --name-only)
    foreach ($path in $staged) {
        if ($path -and $path -notin $paths) { throw "Unrelated file already staged: $path. Preserve it separately before publishing these repairs." }
    }
    Invoke-Git fetch origin main
    $present = @($paths | Where-Object { Test-Path -LiteralPath $_ })
    Invoke-Git add -- @present
    & git diff --cached --quiet
    if ($LASTEXITCODE -eq 1) {
        Invoke-Git commit -m 'Fix reported habitat visuals, ladder climbing, suit lifecycle and camera clipping'
    } elseif ($LASTEXITCODE -ne 0) { throw 'Could not inspect staged changes.' }
    Invoke-Git rebase origin/main
    Invoke-Git push origin main
    Invoke-Git log -1 --oneline
} finally {
    Pop-Location
}
