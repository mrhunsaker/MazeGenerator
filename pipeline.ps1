# pipeline.ps1 - Full Maze Generation Pipeline
# Runs batch_run_maze.ps1, traces BMPs to SVG with potrace, then runs create_stl.ps1

$ErrorActionPreference = 'Stop'

# Always reliable script directory
$ScriptDir = $PSScriptRoot

# 1. Determine seeds to use
$batchScript = Join-Path $ScriptDir 'batch_run_maze.ps1'
if (-not (Test-Path $batchScript)) {
    Write-Error "Cannot find batch_run_maze.ps1 in $ScriptDir"
    exit 1
}

$mazesDir = Join-Path $ScriptDir 'mazes'
if (-not (Test-Path $mazesDir)) {
    New-Item -ItemType Directory -Path $mazesDir | Out-Null
}

# Find used seeds in mazes directory (maze*.svg, not _solution)
$usedSeeds = Get-ChildItem -Path $mazesDir -Filter 'maze*.svg' |
    Where-Object { $_.Name -notmatch '_solution' } |
    ForEach-Object {
        if ($_.BaseName -match '^maze(\d+)$') { [int]$matches[1] } else { $null }
    } |
    Where-Object { $_ -ne $null }

# Ask how many mazes to generate
Write-Host "How many mazes do you want to generate?" -ForegroundColor Cyan
while ($true) {
    $mazeCountInput = Read-Host 'Maze Count'
    if ($mazeCountInput -match '^\d+$' -and [int]$mazeCountInput -gt 0) {
        $mazeCount = [int]$mazeCountInput
        break
    } else {
        Write-Host "Please enter a valid positive integer." -ForegroundColor Yellow
    }
}

# Efficiently find next N unused seeds
$usedSeedSet = @{}
foreach ($s in $usedSeeds) { $usedSeedSet[$s] = $true }

$unusedSeeds = @()
$candidate = 100
while ($unusedSeeds.Count -lt $mazeCount -and $candidate -le 2147483647) {
    if (-not $usedSeedSet.ContainsKey($candidate)) {
        $unusedSeeds += $candidate
    }
    $candidate++
}

Write-Host '============================================' -ForegroundColor Cyan
Write-Host ' Maze Seed Selection' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "Detected $($usedSeeds.Count) used seeds in mazes directory."
Write-Host "Use next $mazeCount available seed values? (Y/N)" -NoNewline
$autoSeed = Read-Host ' '

$seedsToUse = @()

if ($autoSeed -match '^(Y|y)') {
    $seedsToUse = $unusedSeeds | Select-Object -First $mazeCount
    Write-Host "Using next $mazeCount available seeds: $($seedsToUse -join ', ')" -ForegroundColor Green
}
else {
    Write-Host "Enter $mazeCount seed values (integers from 100 to 2147483647), separated by commas:"
    while ($true) {
        $seedInputStr = Read-Host 'Seeds'
        $arr = $seedInputStr -split '[, ]+' | Where-Object { $_ -match '^\d{3,}$' }

        $arr = $arr | ForEach-Object {
            $val = [double]$_
            if ($val -gt 2147483647) { 2147483647 }
            elseif ($val -ge 100) { [int][math]::Floor($val) }
            else { $null }
        } | Where-Object { $_ -ne $null }

        if ($arr.Count -eq $mazeCount) {
            $seedsToUse = $arr
            break
        } else {
            Write-Host "Please enter exactly $mazeCount valid seed values." -ForegroundColor Yellow
        }
    }

    Write-Host "Using manual seeds: $($seedsToUse -join ', ')" -ForegroundColor Green
}

Write-Host '============================================' -ForegroundColor Cyan
Write-Host ' Step 1: Generating Mazes' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan

& $batchScript -Seeds $seedsToUse

# 2. Trace BMPs to SVG with potrace
$mazesDir = Join-Path $ScriptDir 'mazes'

Write-Host '============================================' -ForegroundColor Cyan
Write-Host ' Step 2: Tracing BMPs to SVG with potrace' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan

$potraceExe = Get-Command potrace -ErrorAction SilentlyContinue
if (-not $potraceExe) {
    Write-Error 'potrace not found. Install with: scoop install potrace'
    exit 1
}

$bmpFiles = Get-ChildItem -Path $mazesDir -Filter *.bmp |
    Where-Object { $_.Name -notmatch '_solution' }

if ($bmpFiles.Count -eq 0) {
    Write-Host 'No BMP files found to trace.' -ForegroundColor Yellow
}
else {
    foreach ($bmp in $bmpFiles) {
        $outputName = $bmp.BaseName + '_traced.svg'
        $outputPath = Join-Path $bmp.DirectoryName $outputName

        Write-Host "Tracing: $($bmp.Name) -> $outputName" -ForegroundColor White
        & $potraceExe -s --flat -o $outputPath $bmp.FullName

        if (Test-Path $outputPath) {
            Write-Host " -> $outputName created" -ForegroundColor Green
        } else {
            Write-Host " -> Failed to create $outputName" -ForegroundColor Red
        }
    }
}

# 3. Run create_stl.ps1
$stlScript = Join-Path $ScriptDir 'create_stl.ps1'
if (-not (Test-Path $stlScript)) {
    Write-Error "Cannot find create_stl.ps1 in $ScriptDir"
    exit 1
}

Write-Host '============================================' -ForegroundColor Cyan
Write-Host ' Step 3: Generating STL Files' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan

& $stlScript

Write-Host '============================================' -ForegroundColor Cyan
Write-Host ' Pipeline Complete!' -ForegroundColor Green
Write-Host '============================================' -ForegroundColor Cyan
