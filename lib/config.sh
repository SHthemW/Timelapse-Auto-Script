#!/usr/bin/env bash

load_config() {
  local script_dir="$1"
  local config_path="${AUTO_TIMELAPSE_CONFIG:-${script_dir}/config/auto_timelapse.conf}"

  [[ -f "$config_path" ]] || fail "配置文件不存在: ${config_path}"

  # shellcheck source=/dev/null
  source "$config_path"

  AUTO_ROOT="${AUTO_ROOT:-${AUTO_TIMELAPSE_ROOT:-/Users/shw/Pictures/AutoTimelapse}}"
  CAPTURE_INTERVAL_SECONDS="${CAPTURE_INTERVAL_SECONDS:-6}"
  WATCH_QUIET_SECONDS="${WATCH_QUIET_SECONDS:-60}"
  MORNING_START_AT="${MORNING_START_AT:-${START_AT:-03:00}}"
  MORNING_END_AT="${MORNING_END_AT:-${END_AT:-09:00}}"
  DUSK_START_AT="${DUSK_START_AT:-}"
  DUSK_END_AT="${DUSK_END_AT:-}"
  AUTO_TIMELAPSE_CONFIG_PATH="$config_path"
}
