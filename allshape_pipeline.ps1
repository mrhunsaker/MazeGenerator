#Requires -Version 5
<#
.SYNOPSIS
    allshape_pipeline.ps1 - Generate square, circle, and hexagon mazes per seed.
.DESCRIPTION
    For each selected seed, runs:
      1) labyrinth.lua (square)
      2) roundlabyrinth.lua (circle)
      3) hexlabyrinth.lua (hexagon)

    Then exports PNG/BMP (Inkscape), traces BMP -> SVG (potrace),
    and generates STL (OpenSCAD) using the traced SVG.

    Naming convention for every shape:
      maze_0100_square.*
      maze_0100_circle.*
      maze_0100_hexagon.*

.EXAMPLE
    .\allshape_pipeline.ps1
.EXAMPLE
    .\allshape_pipeline.ps1 -Seeds 100,101,102
#>

param(
    [Parameter(Mandatory=$false)]
    [int[]]$Seeds
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MazesDir = Join-Path $ScriptDir 'mazes'
$StlDir = Join-Path $MazesDir 'stl_files'

$SquareScript = Join-Path $ScriptDir 'labyrinth.lua'
$CircleScript = Join-Path $ScriptDir 'roundlabyrinth.lua'
$HexScript = Join-Path $ScriptDir 'hexlabyrinth.lua'
$ScadFile = Join-Path $ScriptDir 'maze_3d.scad'

foreach ($required in @($SquareScript, $CircleScript, $HexScript, $ScadFile)) {
    if (-not (Test-Path $required)) {
        Write-Error "Missing required file: $required"
        exit 1
    }
}

if (-not (Test-Path $MazesDir)) {
    New-Item -Path $MazesDir -ItemType Directory | Out-Null
}
if (-not (Test-Path $StlDir)) {
    New-Item -Path $StlDir -ItemType Directory | Out-Null
}

function Find-Executable {
    param(
        [string[]]$Candidates
    )
    foreach ($cmd in $Candidates) {
        if (Test-Path $cmd) { return $cmd }
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) { return $found.Source }
    }
    return $null
}

$LuaExe = Find-Executable -Candidates @(
    'lua', 'lua5.4', 'lua5.3', 'lua5.2', 'luajit',
    'C:\Program Files\Lua\lua.exe',
    'C:\Lua\lua.exe',
    (Join-Path $env:USERPROFILE 'scoop\shims\lua.exe')
)
if (-not $LuaExe) {
    Write-Error 'Lua interpreter not found. Install Lua first.'
    exit 1
}

$InkscapeExe = Find-Executable -Candidates @(
    'inkscape',
    'C:\Program Files\Inkscape\bin\inkscape.exe',
    'C:\Program Files (x86)\Inkscape\bin\inkscape.exe'
)
if (-not $InkscapeExe) {
    Write-Error 'Inkscape not found. Required for PNG/BMP output.'
    exit 1
}

$PotraceExe = Find-Executable -Candidates @('potrace')
if (-not $PotraceExe) {
    Write-Error 'potrace not found. Install with: scoop install potrace'
    exit 1
}

$OpenScadExe = Find-Executable -Candidates @(
    'openscad',
    'C:\Program Files\OpenSCAD\openscad.exe',
    'C:\Program Files (x86)\OpenSCAD\openscad.exe',
    'C:\Program Files\OpenSCAD (Nightly)\openscad.exe'
)
if (-not $OpenScadExe) {
    Write-Error 'OpenSCAD not found. Required for STL output.'
    exit 1
}

if (-not $Seeds -or $Seeds.Count -eq 0) {
    $usedSeedSet = @{}
    Get-ChildItem -Path $MazesDir -Filter 'maze_*_*.svg' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '_solution|_traced' } |
        ForEach-Object {
            if ($_.Name -match '^maze_(\d+)_') {
                $usedSeedSet[[int]$matches[1]] = $true
            }
        }

    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host '  All-Shape Maze Pipeline' -ForegroundColor Cyan
    Write-Host '============================================' -ForegroundColor Cyan

    while ($true) {
        $countInput = Read-Host 'How many seed values to generate'
        if ($countInput -match '^\d+$' -and [int]$countInput -gt 0) {
            $mazeCount = [int]$countInput
            break
        }
        Write-Host 'Please enter a valid positive integer.' -ForegroundColor Yellow
    }

    $unusedSeeds = @()
    $candidate = 100
    while ($unusedSeeds.Count -lt $mazeCount -and $candidate -le 2147483647) {
        if (-not $usedSeedSet.ContainsKey($candidate)) {
            $unusedSeeds += $candidate
        }
        $candidate++
    }

    $auto = Read-Host "Use next $mazeCount available seed values? (Y/N)"
    if ($auto -match '^(Y|y)$') {
        $Seeds = $unusedSeeds | Select-Object -First $mazeCount
    }
    else {
        while ($true) {
            $seedInput = Read-Host "Enter exactly $mazeCount seed values (comma-separated)"
            $parsed = $seedInput -split '[, ]+' |
                Where-Object { $_ -match '^\d{3,}$' } |
                ForEach-Object {
                    $v = [double]$_
                    if ($v -gt 2147483647) { 2147483647 }
                    elseif ($v -ge 100) { [int][math]::Floor($v) }
                }
            if ($parsed.Count -eq $mazeCount) {
                $Seeds = $parsed
                break
            }
            Write-Host "Please enter exactly $mazeCount valid seed values." -ForegroundColor Yellow
        }
    }
}

$Shapes = @(
    @{ Name = 'square';  Script = $SquareScript  },
    @{ Name = 'circle';  Script = $CircleScript  },
    @{ Name = 'hexagon'; Script = $HexScript     }
)

$stlParameters = @{
    plinth_height = 2.0
    maze_height = 3.5
    round_top_edges = 1
    edge_radius = 0.5
    plinth_style = 0
    corner_radius = 3.0
    svg_scale = 1.0
    show_solution = 0
}

function Convert-SvgToPng {
    param([string]$SvgPath, [string]$PngPath)
    $p = Start-Process -FilePath $InkscapeExe -ArgumentList @(
        $SvgPath,
        '--export-type=png',
        "--export-filename=$PngPath",
        '--export-dpi=300'
    ) -NoNewWindow -Wait -PassThru
    return ($p.ExitCode -eq 0 -and (Test-Path $PngPath))
}

function Convert-PngToBmp {
    param([string]$PngPath, [string]$BmpPath)
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile($PngPath)
    try {
        $img.Save($BmpPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
    }
    finally {
        $img.Dispose()
    }
    return (Test-Path $BmpPath)
}

Write-Host ''
Write-Host "Using Lua      : $LuaExe" -ForegroundColor Green
Write-Host "Using Inkscape : $InkscapeExe" -ForegroundColor Green
Write-Host "Using potrace  : $PotraceExe" -ForegroundColor Green
Write-Host "Using OpenSCAD : $OpenScadExe" -ForegroundColor Green
Write-Host ''
Write-Host "Seeds: $($Seeds -join ', ')" -ForegroundColor Cyan
Write-Host "Shapes per seed: square, circle, hexagon" -ForegroundColor Cyan
Write-Host ''

$totalJobs = $Seeds.Count * $Shapes.Count
$okJobs = 0
$failedJobs = 0

foreach ($seed in $Seeds) {
    foreach ($shape in $Shapes) {
        $shapeName = $shape.Name
        $luaScript = $shape.Script
        $baseName = ('maze_{0:D4}_{1}' -f $seed, $shapeName)

        $svgPath = Join-Path $MazesDir "$baseName.svg"
        $solutionSvgPath = Join-Path $MazesDir "${baseName}_solution.svg"
        $jsonPath = Join-Path $MazesDir "$baseName.json"

        $pngPath = Join-Path $MazesDir "$baseName.png"
        $bmpPath = Join-Path $MazesDir "$baseName.bmp"
        $solutionPngPath = Join-Path $MazesDir "${baseName}_solution.png"
        $solutionBmpPath = Join-Path $MazesDir "${baseName}_solution.bmp"

        $tracedSvgPath = Join-Path $MazesDir "${baseName}_traced.svg"
        $stlPath = Join-Path $StlDir "$baseName.stl"

        Write-Host '--------------------------------------------' -ForegroundColor White
        Write-Host "Seed $seed  |  Shape $shapeName" -ForegroundColor White

        try {
            $seedInput = "$seed`n"
            $luaOutput = $seedInput | & $LuaExe $luaScript 2>&1
            $luaOutput | ForEach-Object { Write-Host $_ }

            if (-not (Test-Path $svgPath) -or -not (Test-Path $solutionSvgPath) -or -not (Test-Path $jsonPath)) {
                throw "Generator did not produce expected files for $baseName"
            }

            if (-not (Convert-SvgToPng -SvgPath $svgPath -PngPath $pngPath)) {
                throw "PNG export failed for $($svgPath)"
            }
            if (-not (Convert-PngToBmp -PngPath $pngPath -BmpPath $bmpPath)) {
                throw "BMP conversion failed for $($pngPath)"
            }

            if (-not (Convert-SvgToPng -SvgPath $solutionSvgPath -PngPath $solutionPngPath)) {
                throw "Solution PNG export failed for $($solutionSvgPath)"
            }
            if (-not (Convert-PngToBmp -PngPath $solutionPngPath -BmpPath $solutionBmpPath)) {
                throw "Solution BMP conversion failed for $($solutionPngPath)"
            }

            & $PotraceExe -s --flat -o $tracedSvgPath $bmpPath
            if (-not (Test-Path $tracedSvgPath)) {
                throw "potrace failed to create $tracedSvgPath"
            }

            $mazeSvgDefine = 'maze_svg_file="' + ("mazes/" + (Split-Path $tracedSvgPath -Leaf).Replace('\\', '/')) + '"'
            $openScadArgs = @(
                '-o', $stlPath,
                '-D', "maze_seed=$seed",
                '-D', $mazeSvgDefine,
                '-D', "plinth_height=$($stlParameters.plinth_height)",
                '-D', "maze_height=$($stlParameters.maze_height)",
                '-D', "round_top_edges=$($stlParameters.round_top_edges)",
                '-D', "edge_radius=$($stlParameters.edge_radius)",
                '-D', "plinth_style=$($stlParameters.plinth_style)",
                '-D', "corner_radius=$($stlParameters.corner_radius)",
                '-D', "svg_scale=$($stlParameters.svg_scale)",
                '-D', "show_solution=$($stlParameters.show_solution)",
                $ScadFile
            )

            $proc = Start-Process -FilePath $OpenScadExe -ArgumentList $openScadArgs -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -ne 0 -or -not (Test-Path $stlPath)) {
                throw "OpenSCAD failed for $baseName (exit $($proc.ExitCode))"
            }

            Write-Host "OK: $baseName outputs complete" -ForegroundColor Green
            $okJobs++
        }
        catch {
            Write-Host "FAIL: $baseName -> $_" -ForegroundColor Red
            $failedJobs++
        }
    }
}

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  All-Shape Pipeline Complete' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "Requested seeds : $($Seeds.Count)" -ForegroundColor White
Write-Host "Shapes each     : 3" -ForegroundColor White
Write-Host "Total jobs      : $totalJobs" -ForegroundColor White
Write-Host "Succeeded       : $okJobs" -ForegroundColor Green
Write-Host "Failed          : $failedJobs" -ForegroundColor $(if ($failedJobs -gt 0) { 'Red' } else { 'White' })
Write-Host "Output dir      : $MazesDir" -ForegroundColor White
Write-Host "STL dir         : $StlDir" -ForegroundColor White
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Per shape outputs:' -ForegroundColor White
Write-Host '  maze_0100_square.svg / _solution.svg / .json / .png / .bmp / _traced.svg / .stl' -ForegroundColor Gray
Write-Host '  maze_0100_circle.svg / _solution.svg / .json / .png / .bmp / _traced.svg / .stl' -ForegroundColor Gray
Write-Host '  maze_0100_hexagon.svg / _solution.svg / .json / .png / .bmp / _traced.svg / .stl' -ForegroundColor Gray
