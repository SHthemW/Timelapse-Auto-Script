#!/bin/sh

pause_and_fail() {
    printf "Press Return to close..."
    if [ -r /dev/tty ]; then
        read -r _ </dev/tty || true
    else
        read -r _ || true
    fi
    exit 1
}

python_version_ready() {
    "$1" -c 'import sys; assert sys.version_info >= (3, 10)' >/dev/null 2>&1
}

runtime_dependencies_ready() {
    "$1" -c 'import customtkinter, yaml, psutil, PIL' >/dev/null 2>&1
}

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
if [ -z "$SCRIPT_DIR" ] || ! cd "$SCRIPT_DIR"; then
    echo "Unable to locate the Timelapse Manager directory."
    pause_and_fail
fi

if [ -x "./TimelapseManager" ]; then
    exec "./TimelapseManager" gui
fi

if [ ! -f "./timelapse.py" ]; then
    echo "Timelapse Manager launcher was not found in:"
    pwd
    pause_and_fail
fi

GUI_PYTHON=""
GUI_ENVIRONMENT=""

if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "${VIRTUAL_ENV}/bin/python3" ]; then
    GUI_PYTHON="${VIRTUAL_ENV}/bin/python3"
    GUI_ENVIRONMENT="active environment ${VIRTUAL_ENV}"
elif [ -n "${VIRTUAL_ENV:-}" ] && [ -x "${VIRTUAL_ENV}/bin/python" ]; then
    GUI_PYTHON="${VIRTUAL_ENV}/bin/python"
    GUI_ENVIRONMENT="active environment ${VIRTUAL_ENV}"
elif [ -x "./.venv/bin/python3" ]; then
    GUI_PYTHON="./.venv/bin/python3"
    GUI_ENVIRONMENT="project environment .venv"
elif [ -x "./.venv/bin/python" ]; then
    GUI_PYTHON="./.venv/bin/python"
    GUI_ENVIRONMENT="project environment .venv"
elif [ -x "./venv/bin/python3" ]; then
    GUI_PYTHON="./venv/bin/python3"
    GUI_ENVIRONMENT="project environment venv"
elif [ -x "./venv/bin/python" ]; then
    GUI_PYTHON="./venv/bin/python"
    GUI_ENVIRONMENT="project environment venv"
fi

if [ -z "$GUI_PYTHON" ]; then
    BOOTSTRAP_PYTHON=""
    if command -v python3 >/dev/null 2>&1; then
        CANDIDATE=$(command -v python3)
        if python_version_ready "$CANDIDATE"; then
            BOOTSTRAP_PYTHON="$CANDIDATE"
        fi
    fi
    if [ -z "$BOOTSTRAP_PYTHON" ]; then
        echo "Python 3.10 or newer was not found."
        pause_and_fail
    fi

    echo "Creating project virtual environment: ${SCRIPT_DIR}/.venv"
    if ! "$BOOTSTRAP_PYTHON" -m venv "./.venv"; then
        echo "Failed to create the project virtual environment."
        pause_and_fail
    fi
    if [ -x "./.venv/bin/python3" ]; then
        GUI_PYTHON="./.venv/bin/python3"
    else
        GUI_PYTHON="./.venv/bin/python"
    fi
    GUI_ENVIRONMENT="new project environment .venv"
fi

if ! python_version_ready "$GUI_PYTHON"; then
    echo "The selected virtual environment does not contain Python 3.10 or newer:"
    echo "$GUI_PYTHON"
    pause_and_fail
fi

echo "Using ${GUI_ENVIRONMENT}"
echo "Python: ${GUI_PYTHON}"

if ! runtime_dependencies_ready "$GUI_PYTHON"; then
    if [ ! -f "./requirements.txt" ]; then
        echo "requirements.txt was not found."
        pause_and_fail
    fi
    echo "Installing missing runtime dependencies into the virtual environment..."
    if ! "$GUI_PYTHON" -m pip install --disable-pip-version-check -r "./requirements.txt"; then
        echo "Failed to install runtime dependencies."
        pause_and_fail
    fi
fi

exec "$GUI_PYTHON" "./timelapse.py" gui
