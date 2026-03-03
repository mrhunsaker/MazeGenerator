#Requires -Version 3
<#
.SYNOPSIS
    run_maze.ps1 - PowerShell entry point for labyrinth.lua
.DESCRIPTION
    Locates a Lua interpreter and runs labyrinth.lua to generate a
    200x200 mm labyrinth SVG (plus solution SVG and JSON parameters).
.EXAMPLE
    .\run_maze.ps1
    # Run from PowerShell in the script directory.
    # If execution policy blocks it:
    #   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#>

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

Write-Host "Using Lua: $LuaExe"
Write-Host ''

# ------------------------------------------------------------------
# Run the generator
# ------------------------------------------------------------------
& $LuaExe $LuaScript

if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host 'Labyrinth generator returned an error.' -ForegroundColor Red
    Read-Host 'Press Enter to exit'
    exit $LASTEXITCODE
}
# ------------------------------------------------------------------
# Post-process with Inkscape (SVG -> PNG -> Traced SVG)
# ------------------------------------------------------------------
# NOTE: Tracing disabled - original SVG mazes work better for OpenSCAD
# Uncomment below to enable PNG export if needed for other purposes

<#
Write-Host ''
Write-Host 'Post-processing with Inkscape...' -ForegroundColor Cyan

# Locate Inkscape
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
    Write-Host 'WARNING: Inkscape not found. Skipping post-processing.' -ForegroundColor Yellow
    Write-Host 'Install from: https://inkscape.org/release/' -ForegroundColor Yellow
    Write-Host ''
    Read-Host 'Press Enter to continue'
    exit 0
}

Write-Host "Using Inkscape: $InkscapeExe"

# Find generated maze files in ./mazes directory
$mazesDir = Join-Path $ScriptDir 'mazes'
$svgFiles = Get-ChildItem -Path $mazesDir -Filter 'maze*.svg' | Where-Object { $_.Name -notmatch '_traced' }

foreach ($svgFile in $svgFiles) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($svgFile.Name)
    $svgPath = $svgFile.FullName
    $pngPath = Join-Path $mazesDir "$baseName.png"
    $tracedPath = Join-Path $mazesDir "${baseName}_traced.svg"
    
    Write-Host "Processing: $($svgFile.Name)" -ForegroundColor Green
    
    # Step 1: Export SVG to PNG with a simpler command
    Write-Host "  -> Converting to PNG..."
    
    # Use Inkscape with absolute paths and simpler syntax
    $inkscapeArgs = @(
        $svgPath,
        '--export-type=png',
        "--export-filename=$pngPath",
        '--export-dpi=300'
    )
    
    Start-Process -FilePath $InkscapeExe -ArgumentList $inkscapeArgs -NoNewWindow -Wait -RedirectStandardError (Join-Path $env:TEMP 'inkscape_err.txt') -RedirectStandardOutput (Join-Path $env:TEMP 'inkscape_out.txt')
    Start-Sleep -Milliseconds 500
    
    if (-not (Test-Path $pngPath)) {
        # Try legacy syntax
        $inkscapeArgs = @(
            '--export-png=' + $pngPath,
            '--export-dpi=300',
            $svgPath
        )
        Start-Process -FilePath $InkscapeExe -ArgumentList $inkscapeArgs -NoNewWindow -Wait
        Start-Sleep -Milliseconds 500
    }
    
    if (-not (Test-Path $pngPath)) {
        Write-Host "  ERROR: PNG export failed" -ForegroundColor Red
        $errContent = Get-Content (Join-Path $env:TEMP 'inkscape_err.txt') -ErrorAction SilentlyContinue
        $outContent = Get-Content (Join-Path $env:TEMP 'inkscape_out.txt') -ErrorAction SilentlyContinue
        if ($errContent) { Write-Host "  Error: $errContent" -ForegroundColor Gray }
        if ($outContent) { Write-Host "  Output: $outContent" -ForegroundColor Gray }
        continue
    }
    
    Write-Host "  -> PNG created successfully" -ForegroundColor Green
    
    # Step 2: Use potrace if available, otherwise skip tracing
    $potraceExe = Get-Command potrace -ErrorAction SilentlyContinue
    if ($potraceExe) {
        Write-Host "  -> Tracing with potrace..."
        & potrace -s -o "$tracedPath" "$pngPath" 2>$null
        
        if (Test-Path $tracedPath) {
            Write-Host "  -> Saved: $([System.IO.Path]::GetFileName($tracedPath))" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  -> Skipping trace (potrace not found, install with: scoop install potrace)" -ForegroundColor Yellow
        Write-Host "  -> Keeping PNG file for manual processing" -ForegroundColor Yellow
        continue
    }
    
    # Clean up PNG
    if (Test-Path $pngPath) {
        Remove-Item $pngPath -Force
    }
}

Write-Host ''
Write-Host 'Post-processing complete!' -ForegroundColor Green

#>