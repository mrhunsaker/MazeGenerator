#Requires -Version 3
<#
.SYNOPSIS
    batch_run_maze.ps1 - Batch maze generator for multiple seeds
.DESCRIPTION
    Generates multiple mazes from a list of seed values.
    Outputs SVG, PNG, BMP (via Inkscape), JSON, and solution SVG for each seed.
    BMP files are generated for better compatibility with potrace.
.PARAMETER Seeds
    Array of seed values (integers with at least 3 digits)
.EXAMPLE
    .\batch_run_maze.ps1 -Seeds 123,456,789,1011,1213,1415,1617,1819,2021,2223
.EXAMPLE
    .\batch_run_maze.ps1
    # Will prompt for 10 seed values interactively
#>

param(
    [Parameter(Mandatory=$false)]
    [int[]]$Seeds
)

$ErrorActionPreference = 'Stop'
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$LuaScript  = Join-Path $ScriptDir 'labyrinth.lua'

if (-not (Test-Path $LuaScript)) {
    Write-Error "Cannot find labyrinth.lua in '$ScriptDir'"
    exit 1
}

# ------------------------------------------------------------------
# Locate Lua
# ------------------------------------------------------------------
$LuaExe = $null
$candidates = @('lua', 'lua5.4', 'lua5.3', 'lua5.2', 'luajit')

foreach ($cmd in $candidates) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) { $LuaExe = $found.Source; break }
}

# Check common Windows install paths if not on PATH
if (-not $LuaExe) {
    $common = @(
        'C:\Program Files\Lua\lua.exe',
        'C:\Lua\lua.exe',
        'C:\tools\lua\lua.exe'
    )
    foreach ($p in $common) {
        if (Test-Path $p) { $LuaExe = $p; break }
    }
}

# Check Scoop shims
if (-not $LuaExe) {
    $scoop = Join-Path $env:USERPROFILE 'scoop\shims\lua.exe'
    if (Test-Path $scoop) { $LuaExe = $scoop }
}

if (-not $LuaExe) {
    Write-Host ''
    Write-Host 'ERROR: No Lua interpreter found.' -ForegroundColor Red
    Write-Host ''
    Write-Host 'Install Lua using one of:'
    Write-Host '  Scoop      :  scoop install lua'
    Write-Host '  Chocolatey :  choco install lua'
    Write-Host '  Winget     :  winget install Lua.Lua'
    Write-Host '  Manual     :  https://luabinaries.sourceforge.net/'
    Write-Host ''
    Read-Host 'Press Enter to exit'
    exit 1
}

# ------------------------------------------------------------------
# Locate Inkscape
# ------------------------------------------------------------------
$InkscapeExe = $null
$inkscapeCandidates = @(
    'inkscape',
    'C:\Program Files\Inkscape\bin\inkscape.exe',
    'C:\Program Files (x86)\Inkscape\bin\inkscape.exe',
    "$env:ProgramFiles\Inkscape\bin\inkscape.exe",
    "${env:ProgramFiles(x86)}\Inkscape\bin\inkscape.exe"
)

foreach ($cmd in $inkscapeCandidates) {
    if ($cmd -eq 'inkscape') {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) { $InkscapeExe = $found.Source; break }
    } elseif (Test-Path $cmd) {
        $InkscapeExe = $cmd; break
    }
}

if (-not $InkscapeExe) {
    Write-Host 'WARNING: Inkscape not found. PNG/BMP export will be skipped.' -ForegroundColor Yellow
    Write-Host 'Install from: https://inkscape.org/release/' -ForegroundColor Yellow
    Write-Host ''
}

# ------------------------------------------------------------------
# Get seed values
# ------------------------------------------------------------------
if (-not $Seeds -or $Seeds.Count -eq 0) {
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host '  Batch Maze Generator' -ForegroundColor Cyan
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Enter 10 seed values (integers from 100 to 2147483647)'
    Write-Host ''
    
    $Seeds = @()
    for ($i = 1; $i -le 10; $i++) {
        while ($true) {
            $input = Read-Host "Seed $i"
            if ($input -match '^(\d{3,})$') {
                $val = [double]$input
                if ($val -gt 2147483647) {
                    $val = 2147483647
                    Write-Host "  Value too large, using 2147483647 instead." -ForegroundColor Yellow
                }
                if ($val -ge 100) {
                    $Seeds += [int][math]::Floor($val)
                    break
                }
            }
            Write-Host "  Invalid. Please enter an integer from 100 to 2147483647." -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host "Using Lua: $LuaExe" -ForegroundColor Green
if ($InkscapeExe) {
    Write-Host "Using Inkscape: $InkscapeExe" -ForegroundColor Green
}
Write-Host ''
Write-Host "Processing $($Seeds.Count) mazes..." -ForegroundColor Cyan
Write-Host ''

$mazesDir = Join-Path $ScriptDir 'mazes'
$successCount = 0
$failCount = 0

# ------------------------------------------------------------------
# Process each seed
# ------------------------------------------------------------------
foreach ($seed in $Seeds) {
    Write-Host "============================================" -ForegroundColor White
    Write-Host "Processing Seed: $seed" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor White
    
    try {
        # Run Lua script with seed piped to stdin
        $seedInput = "$seed`n"
        $luaOutput = $seedInput | & $LuaExe $LuaScript 2>&1
        
        # Display output
        $luaOutput | ForEach-Object { Write-Host $_ }
        
        # Check if files were created
        $baseName = "maze{0:D4}" -f $seed
        $svgFile = Join-Path $mazesDir "$baseName.svg"
        $solutionFile = Join-Path $mazesDir "${baseName}_solution.svg"
        $jsonFile = Join-Path $mazesDir "$baseName.json"
        
        if (-not (Test-Path $svgFile) -or -not (Test-Path $solutionFile)) {
            Write-Host "ERROR: Maze generation failed for seed $seed" -ForegroundColor Red
            $failCount++
            continue
        }
        
        # Export to PNG and BMP if Inkscape is available
        if ($InkscapeExe) {
            Write-Host "Exporting to PNG and BMP..." -ForegroundColor Cyan
            
            # Export maze PNG
            $pngFile = Join-Path $mazesDir "$baseName.png"
            $inkscapeArgs = @(
                $svgFile,
                '--export-type=png',
                "--export-filename=$pngFile",
                '--export-dpi=300'
            )
            Start-Process -FilePath $InkscapeExe -ArgumentList $inkscapeArgs -NoNewWindow -Wait
            Start-Sleep -Milliseconds 500
            
            if (Test-Path $pngFile) {
                Write-Host "  -> $baseName.png created" -ForegroundColor Green
            }
            
            # Export maze BMP
            $bmpFile = Join-Path $mazesDir "$baseName.bmp"
            $inkscapeArgs = @(
                $svgFile,
                '--export-type=png',
                "--export-filename=$bmpFile",
                '--export-dpi=300'
            )
            Start-Process -FilePath $InkscapeExe -ArgumentList $inkscapeArgs -NoNewWindow -Wait
            Start-Sleep -Milliseconds 100
            
            # Convert PNG to BMP if PNG was created
            if (Test-Path $pngFile) {
                # Use built-in .NET to convert PNG to BMP
                Add-Type -AssemblyName System.Drawing
                $img = [System.Drawing.Image]::FromFile($pngFile)
                $img.Save($bmpFile, [System.Drawing.Imaging.ImageFormat]::Bmp)
                $img.Dispose()
                
                if (Test-Path $bmpFile) {
                    Write-Host "  -> $baseName.bmp created" -ForegroundColor Green
                }
            }
            
            # Export solution PNG
            $solutionPngFile = Join-Path $mazesDir "${baseName}_solution.png"
            $inkscapeArgs = @(
                $solutionFile,
                '--export-type=png',
                "--export-filename=$solutionPngFile",
                '--export-dpi=300'
            )
            Start-Process -FilePath $InkscapeExe -ArgumentList $inkscapeArgs -NoNewWindow -Wait
            Start-Sleep -Milliseconds 500
            
            if (Test-Path $solutionPngFile) {
                Write-Host "  -> ${baseName}_solution.png created" -ForegroundColor Green
            }
            
            # Export solution BMP
            $solutionBmpFile = Join-Path $mazesDir "${baseName}_solution.bmp"
            if (Test-Path $solutionPngFile) {
                # Convert PNG to BMP
                Add-Type -AssemblyName System.Drawing
                $img = [System.Drawing.Image]::FromFile($solutionPngFile)
                $img.Save($solutionBmpFile, [System.Drawing.Imaging.ImageFormat]::Bmp)
                $img.Dispose()
                
                if (Test-Path $solutionBmpFile) {
                    Write-Host "  -> ${baseName}_solution.bmp created" -ForegroundColor Green
                }
            }
        }
        
        $successCount++
        Write-Host "SUCCESS: Seed $seed completed" -ForegroundColor Green
        Write-Host ''
        
    } catch {
        Write-Host "ERROR: Failed to process seed $seed - $_" -ForegroundColor Red
        Write-Host ''
        $failCount++
    }
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  Batch Generation Complete' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  Total Seeds  : $($Seeds.Count)" -ForegroundColor White
Write-Host "  Successful   : $successCount" -ForegroundColor Green
Write-Host "  Failed       : $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'White' })
Write-Host "  Output Dir   : $mazesDir" -ForegroundColor White
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Files generated per maze:' -ForegroundColor White
Write-Host '  - mazeXXXX.svg (base maze)' -ForegroundColor Gray
Write-Host '  - mazeXXXX_solution.svg (with solution path)' -ForegroundColor Gray
Write-Host '  - mazeXXXX.json (parameters and stats)' -ForegroundColor Gray
if ($InkscapeExe) {
    Write-Host '  - mazeXXXX.png (300 DPI render)' -ForegroundColor Gray
    Write-Host '  - mazeXXXX.bmp (300 DPI render for potrace)' -ForegroundColor Gray
    Write-Host '  - mazeXXXX_solution.png (300 DPI render with solution)' -ForegroundColor Gray
    Write-Host '  - mazeXXXX_solution.bmp (300 DPI render with solution for potrace)' -ForegroundColor Gray
}
Write-Host ''
