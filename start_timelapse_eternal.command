#!/bin/bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "${SCRIPT_DIR}/start_timelapse_eternal.sh"
