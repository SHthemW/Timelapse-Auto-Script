@echo off
setlocal

pushd "%~dp0" >nul || exit /b 1

if exist "TimelapseManager.exe" (
    "TimelapseManager.exe" gui
    goto finished
)

if not exist "timelapse.py" (
    echo Timelapse Manager launcher was not found in:
    echo %CD%
    goto failed
)

if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" -c "import sys, customtkinter, yaml, psutil, PIL; assert sys.version_info.__ge__((3, 10))" >nul 2>&1
    if not errorlevel 1 (
        ".venv\Scripts\python.exe" timelapse.py gui
        goto finished
    )
)

if exist "venv\Scripts\python.exe" (
    "venv\Scripts\python.exe" -c "import sys, customtkinter, yaml, psutil, PIL; assert sys.version_info.__ge__((3, 10))" >nul 2>&1
    if not errorlevel 1 (
        "venv\Scripts\python.exe" timelapse.py gui
        goto finished
    )
)

where py >nul 2>&1
if not errorlevel 1 (
    py -3 -c "import sys, customtkinter, yaml, psutil, PIL; assert sys.version_info.__ge__((3, 10))" >nul 2>&1
    if not errorlevel 1 (
        py -3 timelapse.py gui
        goto finished
    )
)

where python >nul 2>&1
if not errorlevel 1 (
    python -c "import sys, customtkinter, yaml, psutil, PIL; assert sys.version_info.__ge__((3, 10))" >nul 2>&1
    if not errorlevel 1 (
        python timelapse.py gui
        goto finished
    )
)

echo No ready Python environment was found.
echo Install Python 3.10 or newer, then run:
echo python -m pip install -r requirements.txt
goto failed

:finished
set "LAUNCH_EXIT_CODE=%ERRORLEVEL%"
if not "%LAUNCH_EXIT_CODE%"=="0" (
    echo.
    echo Timelapse Manager exited with code %LAUNCH_EXIT_CODE%.
    echo Install dependencies with: python -m pip install -r requirements.txt
    pause
)
popd >nul
exit /b %LAUNCH_EXIT_CODE%

:failed
echo.
pause
popd >nul
exit /b 1
