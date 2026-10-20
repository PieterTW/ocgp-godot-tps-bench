@echo off
rem OCGP TPS benchmark launcher.
rem   run_benchmark.bat [Small|Medium|Large] [result-file]
rem Defaults: Medium, ocgp_tps_result_<variant>.txt in the current folder.
rem The engine flags below are REQUIRED (the benchmark refuses to score without them), so use this file
rem instead of starting OCGP-TPS.exe by hand.
setlocal
set "VARIANT=%~1"
if "%VARIANT%"=="" set "VARIANT=Medium"
set "OUT=%~2"
if "%OUT%"=="" set "OUT=ocgp_tps_result_%VARIANT%.txt"
rem The exe resolves relative paths against its own folder, so hand it an absolute path.
for %%I in ("%OUT%") do set "OUT=%%~fI"
echo Running OCGP TPS benchmark, variant %VARIANT%.
echo A window opens and closes by itself. Results go to "%OUT%".
start "" /wait "%~dp0OCGP-TPS.exe" --rendering-driver vulkan --disable-vsync --fixed-fps 60 --flush-stdout -- --variant %VARIANT% --output "%OUT%"
echo.
echo Finished. Please send back "%OUT%".
endlocal
