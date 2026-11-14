param([Parameter(Mandatory=$true)][string]$PoseDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..\..'))
$allowed = [IO.Path]::GetFullPath((Join-Path $root 'mars_colony_godot\docs\milestones\04_player\rig')) + [IO.Path]::DirectorySeparatorChar
$poses = [IO.Path]::GetFullPath($PoseDirectory)
if (-not $poses.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw 'Pose directory must be under the allowed rig folder' }
$clips = @('idle','walk','sprint','jump','carry','use','suit','seated')
foreach ($mode in @('crew','suit')) {
    foreach ($view in @('front','side')) {
        $target = Join-Path $poses "contact_${view}_${mode}.jpg"
        if (Test-Path -LiteralPath $target) { throw "Refusing overwrite: $target" }
        $canvas = New-Object Drawing.Bitmap 1280,850
        $graphics = [Drawing.Graphics]::FromImage($canvas)
        $graphics.Clear([Drawing.Color]::FromArgb(25,30,38))
        $font = New-Object Drawing.Font 'Arial',13
        for ($i=0;$i -lt $clips.Count;$i++) {
            $img = [Drawing.Image]::FromFile((Join-Path $poses ($clips[$i]+"_${view}_${mode}.png")))
            $x=($i%4)*320; $y=[math]::Floor($i/4)*425
            $graphics.DrawImage($img,$x,$y,320,400)
            $graphics.DrawString(($clips[$i]+" / $view / $mode"),$font,[Drawing.Brushes]::White,$x+5,$y+401)
            $img.Dispose()
        }
        $canvas.Save($target,[Drawing.Imaging.ImageFormat]::Jpeg)
        $font.Dispose();$graphics.Dispose();$canvas.Dispose()
    }
}
