param([string]$Letter, [string]$Dir, [string]$Effort = "medium")
# Runs one Codex worker (astra model, fast tier) on a prompt file and keeps its log and final message.
$work = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Dir
$start = Get-Date
Get-Content -Raw (Join-Path $work "prompt$Letter.md") |
	& codex exec -m gpt-6-astra -c 'service_tier="fast"' -c "model_reasoning_effort=`"$Effort`"" -s workspace-write --skip-git-repo-check `
		-o (Join-Path $work "result$Letter.md") - *> (Join-Path $work "log$Letter.txt")
$secs = [int]((Get-Date) - $start).TotalSeconds
"worker $Letter exit=$LASTEXITCODE secs=$secs"
Get-Content (Join-Path $work "result$Letter.md") -ErrorAction SilentlyContinue
