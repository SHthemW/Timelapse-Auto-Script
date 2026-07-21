#!/bin/sh

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
if [ -z "$SCRIPT_DIR" ] || ! cd "$SCRIPT_DIR"; then
    echo "Unable to locate the Timelapse Manager directory."
    printf "Press Return to close..."
    read -r _
    exit 1
fi

if [ -x "./TimelapseManager" ]; then
    exec "./TimelapseManager" gui
fi

if [ ! -f "./timelapse.py" ]; then
    echo "Timelapse Manager launcher was not found in:"
    pwd
    printf "Press Return to close..."
    read -r _
    exit 1
fi

python_ready() {
    "$1" -c 'import sys, customtkinter, yaml, psutil, PIL; assert sys.version_info >= (3, 10)' >/dev/null 2>&1
}

if [ -x "./.venv/bin/python3" ] && python_ready "./.venv/bin/python3"; then
    GUI_PYTHON="./.venv/bin/python3"
elif [ -x "./.venv/bin/python" ] && python_ready "./.venv/bin/python"; then
    GUI_PYTHON="./.venv/bin/python"
elif [ -x "./venv/bin/python3" ] && python_ready "./venv/bin/python3"; then
    GUI_PYTHON="./venv/bin/python3"
elif [ -x "./venv/bin/python" ] && python_ready "./venv/bin/python"; then
    GUI_PYTHON="./venv/bin/python"
elif command -v python3 >/dev/null 2>&1 && python_ready "$(command -v python3)"; then
    GUI_PYTHON="$(command -v python3)"
else
    echo "No ready Python environment was found."
    echo "Install Python 3.10 or newer, then run:"
    echo "python3 -m pip install -r requirements.txt"
    printf "Press Return to close..."
    read -r _
    exit 1
fi

exec "$GUI_PYTHON" "./timelapse.py" gui
