#Requires -Version 3
<#
.SYNOPSIS
    create_stl.ps1 - Batch STL generator for all mazes
.DESCRIPTION
    Scans the ./mazes folder for traced maze SVG files and generates
    STL files using OpenSCAD with predefined parameters.
.EXAMPLE
    .\create_stl.ps1
    # Generates STL files for all mazeXXXX_traced.svg files
#>

$ErrorActionPreference = 'Stop'
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScadFile   = Join-Path $ScriptDir 'maze_3d.scad'
$MazesDir   = Join-Path $ScriptDir 'mazes'

if (-not (Test-Path $ScadFile)) {
    Write-Error "Cannot find maze_3d.scad in '$ScriptDir'"
    exit 1
}

if (-not (Test-Path $MazesDir)) {
    Write-Error "Cannot find mazes directory in '$ScriptDir'"
    exit 1
}

# ------------------------------------------------------------------
# Locate OpenSCAD
# ------------------------------------------------------------------
$OpenScadExe = $null
$openscadCandidates = @(
    'openscad',
    'C:\Program Files\OpenSCAD\openscad.exe',
    'C:\Program Files (x86)\OpenSCAD\openscad.exe',
    'C:\Program Files\OpenSCAD (Nightly)\openscad.exe',
    "$env:ProgramFiles\OpenSCAD\openscad.exe",
    "${env:ProgramFiles(x86)}\OpenSCAD\openscad.exe"
)

foreach ($cmd in $openscadCandidates) {
    if ($cmd -eq 'openscad') {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) { $OpenScadExe = $found.Source; break }
    } elseif (Test-Path $cmd) {
        $OpenScadExe = $cmd; break
    }
}

if (-not $OpenScadExe) {
    Write-Host ''
    Write-Host 'ERROR: OpenSCAD not found.' -ForegroundColor Red
    Write-Host ''
    Write-Host 'Install OpenSCAD from:'
    Write-Host '  https://openscad.org/downloads.html'
    Write-Host ''
    Read-Host 'Press Enter to exit'
    exit 1
}

Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  Batch STL Generator for Mazes' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "Using OpenSCAD: $OpenScadExe" -ForegroundColor Green
Write-Host ''

# ------------------------------------------------------------------
# Find all traced maze files (excluding solutions)
# ------------------------------------------------------------------
$mazeFiles = Get-ChildItem -Path $MazesDir -Filter 'maze*_traced.svg' | 
    Where-Object { $_.Name -notmatch '_solution' } |
    Sort-Object Name

if ($mazeFiles.Count -eq 0) {
    Write-Host 'No traced maze files found in ./mazes/' -ForegroundColor Yellow
    Write-Host 'Expected files like: maze0123_traced.svg' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Run batch_run_maze.ps1 first, then trace with potrace:' -ForegroundColor Yellow
    Write-Host '  Get-ChildItem -Path ./mazes -Filter *.bmp | ForEach-Object {' -ForegroundColor Gray
    Write-Host '      $outputName = $_.BaseName + "_traced.svg"' -ForegroundColor Gray
    Write-Host '      $outputPath = Join-Path $_.DirectoryName $outputName' -ForegroundColor Gray
    Write-Host '      potrace -s --flat -o $outputPath $_.FullName' -ForegroundColor Gray
    Write-Host '  }' -ForegroundColor Gray
    Write-Host ''
    Read-Host 'Press Enter to exit'
    exit 0
}

Write-Host "Found $($mazeFiles.Count) maze(s) to process" -ForegroundColor Cyan
Write-Host ''

# ------------------------------------------------------------------
# Parameters for 3D model
# ------------------------------------------------------------------
$params = @{
    plinth_height = 2.0
    maze_height = 3.5
    round_top_edges = 1
    edge_radius = 0.5
    plinth_style = 0
    corner_radius = 3.0
    svg_scale = 1.0
    show_solution = 0
}

Write-Host 'STL Generation Parameters:' -ForegroundColor White
Write-Host "  Plinth Height    : $($params.plinth_height) mm" -ForegroundColor Gray
Write-Host "  Maze Height      : $($params.maze_height) mm" -ForegroundColor Gray
Write-Host "  Round Top Edges  : Yes (radius: $($params.edge_radius) mm)" -ForegroundColor Gray
Write-Host "  Plinth Style     : Simple Square" -ForegroundColor Gray
Write-Host "  SVG Scale        : $($params.svg_scale)" -ForegroundColor Gray
Write-Host ''

$successCount = 0
$failCount = 0

# ------------------------------------------------------------------
# Process each maze
# ------------------------------------------------------------------
$StlDir = Join-Path $MazesDir 'stl_files'
if (-not (Test-Path $StlDir)) {
    New-Item -ItemType Directory -Path $StlDir | Out-Null
}

foreach ($mazeFile in $mazeFiles) {
    # Extract full seed from filename (e.g., maze0123_traced.svg or maze123456_traced.svg)
    if ($mazeFile.Name -match 'maze(\d+)_traced\.svg') {
        $seedStr = $matches[1]
        $seed = [int]$seedStr
        $stlFile = Join-Path $StlDir "maze$seedStr.stl"

        Write-Host "Processing: maze$seedStr (seed: $seed)" -ForegroundColor White

        # Double-check the traced SVG file exists
        if (-not (Test-Path $mazeFile.FullName)) {
            Write-Host "  -> Traced SVG file not found: $($mazeFile.FullName)" -ForegroundColor Red
            $failCount++
            continue
        }

        try {
            # Build OpenSCAD command line arguments
            $openscadArgs = @(
                '-o', $stlFile,
                '-D', "maze_seed=$seedStr",
                '-D', "plinth_height=$($params.plinth_height)",
                '-D', "maze_height=$($params.maze_height)",
                '-D', "round_top_edges=$($params.round_top_edges)",
                '-D', "edge_radius=$($params.edge_radius)",
                '-D', "plinth_style=$($params.plinth_style)",
                '-D', "corner_radius=$($params.corner_radius)",
                '-D', "svg_scale=$($params.svg_scale)",
                '-D', "show_solution=$($params.show_solution)",
                $ScadFile
            )

            # Run OpenSCAD
            Write-Host "  -> Rendering STL..." -ForegroundColor Cyan
            $process = Start-Process -FilePath $OpenScadExe -ArgumentList $openscadArgs -NoNewWindow -Wait -PassThru

            if ($process.ExitCode -eq 0 -and (Test-Path $stlFile)) {
                $fileInfo = Get-Item $stlFile
                $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
                Write-Host "  -> Success! ($fileSizeMB MB)" -ForegroundColor Green
                $successCount++
            } else {
                Write-Host "  -> Failed (exit code: $($process.ExitCode))" -ForegroundColor Red
                $failCount++
            }

        } catch {
            Write-Host "  -> Error: $_" -ForegroundColor Red
            $failCount++
        }

        Write-Host ''
    }
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  STL Generation Complete' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  Total Mazes  : $($mazeFiles.Count)" -ForegroundColor White
Write-Host "  Successful   : $successCount" -ForegroundColor Green
Write-Host "  Failed       : $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'White' })
Write-Host "  Output Dir   : $StlDir" -ForegroundColor White
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''

if ($successCount -gt 0) {
    Write-Host 'STL files ready for 3D printing!' -ForegroundColor Green
    Write-Host "Location: $StlDir" -ForegroundColor Gray
}

Write-Host ''
