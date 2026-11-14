# Create-only rebuild. Existing assets, evidence, scripts and source files are never overwritten.
# Default: build a fresh dated revision. Populate canonical paths only when all are absent.
# -ReuseRun publishes an already tested run without invoking Blender again.
param([string]$RunName = '', [string]$ReuseRun = '')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$rigRoot = Join-Path $root 'mars_colony_godot\docs\milestones\04_player\rig'
$sourceRoot = Join-Path $root 'mars_colony_godot\assets_src\characters'
$assetRoot = Join-Path $root 'mars_colony_godot\assets\characters'
function Write-NewText([string]$Path,[string]$Text) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $writer = New-Object IO.StreamWriter($stream,(New-Object Text.UTF8Encoding($false)))
    try { $writer.Write($Text) } finally { $writer.Dispose() }
}
if ($ReuseRun) { $RunName = $ReuseRun }
if (-not $RunName) { $RunName = 'build_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,6) }
if ($RunName -notmatch '^[A-Za-z0-9_-]+$') { throw 'RunName must contain only letters, digits, underscore and hyphen.' }
$run = Join-Path $rigRoot $RunName
$reportPath = Join-Path $run 'report.json'
$body = Join-Path $root 'grand_colony\work\_downloads\human_base_meshes\extracted\human-base-meshes-bundle-v1.4.1\human_base_meshes_bundle.blend'
$suit = Join-Path $root 'grand_colony\grand_colony.blend'
$before = @{}; foreach ($file in @($body,$suit)) { $before[$file] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash }
if (-not $ReuseRun) {
    foreach ($dir in @($run,(Join-Path $sourceRoot $RunName),(Join-Path $assetRoot $RunName))) {
        if (Test-Path -LiteralPath $dir) { throw "Run already exists; refusing to change it: $dir" }
    }
    $launcher = "$env:LOCALAPPDATA\Microsoft\WindowsApps\blender-launcher.exe"
    $script = Join-Path $PSScriptRoot 'build_character.py'
    $arguments = @('-b','--factory-startup','--disable-autoexec','--python',('"'+$script+'"'),'--','--root',('"'+$root+'"'),'--tag',$RunName)
    $launch = @{run=$RunName;command='blender-launcher.exe -b --factory-startup --disable-autoexec --python build_character.py';started_utc=[DateTime]::UtcNow.ToString('o')}
    try {
        $process = Start-Process -FilePath $launcher -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
        $launch.exit_code = $process.ExitCode
    } catch { $launch.error = $_.Exception.Message; throw }
    finally { Write-NewText (Join-Path $rigRoot ($RunName+'_launcher.json')) ($launch | ConvertTo-Json -Depth 5) }
}
if (-not (Test-Path -LiteralPath $reportPath)) { throw 'Blender produced no report. Do not treat this run as tested or complete.' }
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
if ($report.status -eq 'failed') { throw $report.error }
foreach ($file in @($body,$suit)) {
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $before[$file]) { throw "Source hash changed: $file" }
}
$glb = Join-Path (Join-Path $assetRoot $RunName) 'astronaut.glb'
$blend = Join-Path (Join-Path $sourceRoot $RunName) 'astronaut.blend'
$hash = (Get-FileHash -LiteralPath $glb -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne $report.glb_sha256) { throw 'GLB differs from its verified report.' }
if (-not $report.checks.bone_names -or -not $report.checks.animation_names -or -not $report.checks.source_hashes_unchanged) { throw 'Required verification did not pass.' }
$reviewPath = Join-Path $rigRoot 'visual_review.json'
$review = $null
if (Test-Path -LiteralPath $reviewPath) {
    $candidate = Get-Content -LiteralPath $reviewPath -Raw | ConvertFrom-Json
    if ($candidate.glb_sha256 -eq $hash) {
        $review = $candidate
        $report.visual_review = $review.summary
        $report.status = 'verified_with_documented_limitations'
        $report.defects = @($review.defects)
        $report | Add-Member -NotePropertyName visual_evidence_review -NotePropertyValue $review -Force
    }
}
$canonicalGlb = Join-Path $assetRoot 'astronaut.glb'
$canonicalBlend = Join-Path $sourceRoot 'astronaut.blend'
$canonicalReport = Join-Path $rigRoot 'report.json'
$canonicalProvenance = Join-Path $rigRoot 'PROVENANCE.md'
$canonicalPoses = Join-Path $rigRoot 'poses'
$destinations = @($canonicalGlb,$canonicalBlend,$canonicalReport,$canonicalProvenance,$canonicalPoses)
$existing = @($destinations | Where-Object { Test-Path -LiteralPath $_ })
if ($existing.Count -eq 0) {
    [IO.File]::Copy($glb,$canonicalGlb,$false)
    [IO.File]::Copy($blend,$canonicalBlend,$false)
    $report | Add-Member -NotePropertyName canonical_outputs -NotePropertyValue @{glb=$canonicalGlb;blend=$canonicalBlend;poses=$canonicalPoses} -Force
    Write-NewText $canonicalReport ($report | ConvertTo-Json -Depth 30)
    $provenance = Get-Content -LiteralPath (Join-Path $run 'PROVENANCE.md') -Raw
    if ($review) {
        $provenance = $provenance.Replace('Visual review: Not yet reviewed',('Visual review: '+$review.summary))
        $provenance = $provenance.Replace('Status: built_pending_visual_review','Status: verified_with_documented_limitations')
        $provenance += "`n## Final visual review and accepted limitations`n`n" + $review.summary + "`n`n"
        foreach ($defect in $review.defects) { $provenance += '- '+$defect+"`n" }
    }
    Write-NewText $canonicalProvenance $provenance
    [IO.Directory]::CreateDirectory($canonicalPoses) | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $run 'poses') -File) { [IO.File]::Copy($file.FullName,(Join-Path $canonicalPoses $file.Name),$false) }
    Write-Output "Created canonical asset: $canonicalGlb"
} else {
    Write-Output 'Canonical outputs already exist and were preserved. Fresh revision outputs:'
    Write-Output $glb; Write-Output $blend; Write-Output $reportPath
}
Write-Output ("Body triangles: {0}; suit triangles: {1}; clips: {2}; bones: {3}" -f $report.body_triangles,$report.suit_triangles,$report.glb_animations.Count,$report.bone_names.Count)
Write-Output ("Status: {0}" -f $report.status)
