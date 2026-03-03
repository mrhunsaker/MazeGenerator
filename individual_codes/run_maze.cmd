@echo off
:: run_maze.cmd — Windows Command Prompt entry point for labyrinth.lua
:: Usage: run_maze.cmd  (double-click or run from cmd.exe)

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "LUA_SCRIPT=%SCRIPT_DIR%labyrinth.lua"

:: Try common Lua locations
set "LUA="
for %%L in (lua.exe lua5.4.exe lua5.3.exe luajit.exe) do (
  where /q %%L 2>nul && (set "LUA=%%L" & goto :found)
)

:: Check common install paths
for %%P in (
  "C:\Program Files\Lua\lua.exe"
  "C:\Lua\lua.exe"
  "C:\tools\lua\lua.exe"
) do (
  if exist %%P (set "LUA=%%~P" & goto :found)
)

echo ERROR: No Lua interpreter found on PATH.
echo.
echo Install Lua for Windows from: https://luabinaries.sourceforge.net/
echo Or use Scoop:   scoop install lua
echo Or use Chocolatey: choco install lua
echo.
echo After installing, make sure lua.exe is on your PATH.
pause
exit /b 1

:found
echo Using: %LUA%
echo.
"%LUA%" "%LUA_SCRIPT%"
if errorlevel 1 (
  echo.
  echo Labyrinth generator encountered an error.
  pause
  exit /b 1
)

:: Post-process with Inkscape
echo.
echo Post-processing with Inkscape...

:: Locate Inkscape
set "INKSCAPE="
where /q inkscape.exe 2>nul && (set "INKSCAPE=inkscape.exe" & goto :inkscape_found)

for %%P in (
  "C:\Program Files\Inkscape\bin\inkscape.exe"
  "C:\Program Files (x86)\Inkscape\bin\inkscape.exe"
) do (
  if exist %%P (set "INKSCAPE=%%~P" & goto :inkscape_found)
)

echo WARNING: Inkscape not found. Skipping post-processing.
echo Install from: https://inkscape.org/release/
echo.
pause
exit /b 0

:inkscape_found
echo Using Inkscape: %INKSCAPE%

:: Process all maze SVG files
set "MAZES_DIR=%SCRIPT_DIR%mazes"
for %%F in ("%MAZES_DIR%\maze*.svg") do (
  set "SVG_FILE=%%F"
  set "FILE_NAME=%%~nF"
  
  :: Skip if it's already a traced file
  echo !FILE_NAME! | findstr /C:"_traced" >nul && goto :skip_file
  
  set "PNG_FILE=%MAZES_DIR%\!FILE_NAME!.png"
  set "TRACED_FILE=%MAZES_DIR%\!FILE_NAME!_traced.svg"
  
  echo Processing: %%~nxF
  
  :: Export to PNG
  echo   -^> Converting to PNG...
  "%INKSCAPE%" --export-type=png --export-filename="!PNG_FILE!" "!SVG_FILE!" 2>nul
  
  if not exist "!PNG_FILE!" (
    echo   ERROR: PNG export failed
    goto :skip_file
  )
  
  :: Trace bitmap
  echo   -^> Tracing bitmap (brightness cutoff 0.5^)...
  "%INKSCAPE%" --export-type=svg --export-filename="!TRACED_FILE!" --export-plain-svg --actions="file-open:!PNG_FILE!;EditSelectAll;selection-trace;edit-select-all-in-all-layers;fit-canvas-to-selection;export-do" 2>nul
  
  if exist "!TRACED_FILE!" (
    echo   -^> Saved: !FILE_NAME!_traced.svg
  ) else (
    echo   WARNING: Traced SVG not generated
  )
  
  :: Clean up PNG
  if exist "!PNG_FILE!" del /q "!PNG_FILE!"
  
  :skip_file
)

echo.
echo Post-processing complete!
