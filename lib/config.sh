#!/usr/bin/env bash

load_config() {
  local script_dir="$1"
  local config_path="${AUTO_TIMELAPSE_CONFIG:-${script_dir}/config/auto_timelapse.yaml}"
  local config_values
  local config_key
  local config_value
  local yaml_auto_root=""
  local yaml_capture_interval_seconds=""
  local yaml_watch_quiet_seconds=""
  local yaml_morning_start_at=""
  local yaml_morning_end_at=""
  local yaml_dusk_start_at=""
  local yaml_dusk_end_at=""

  if [[ ! -f "$config_path" ]]; then
    mkdir -p "$(dirname "$config_path")"
    cat >"$config_path" <<'EOF'
# Auto Timelapse 配置文件。
#
# 可通过环境变量 AUTO_TIMELAPSE_CONFIG 指定其他配置文件路径。

auto_root:
capture_interval_seconds:
watch_quiet_seconds:

morning:
  start_at:
  end_at:

# 黄昏时间段需要按季节或拍摄需求设置。
# dusk:
#   start_at:
#   end_at:
dusk:
  start_at:
  end_at:
EOF
    pause_and_exit "检测到配置文件不存在，已自动创建空配置文件: ${config_path}" "请完善配置文件后按回车键退出"
  fi

  if ! config_values="$(ruby -r yaml -e '
    def fetch_value(data, *keys)
      keys.reduce(data) { |memo, key| memo.is_a?(Hash) ? memo[key] : nil }
    end

    config_path = ARGV.fetch(0)
    data = YAML.load_file(config_path) || {}

    values = {
      "auto_root" => fetch_value(data, "auto_root"),
      "capture_interval_seconds" => fetch_value(data, "capture_interval_seconds"),
      "watch_quiet_seconds" => fetch_value(data, "watch_quiet_seconds"),
      "morning_start_at" => fetch_value(data, "morning", "start_at"),
      "morning_end_at" => fetch_value(data, "morning", "end_at"),
      "dusk_start_at" => fetch_value(data, "dusk", "start_at"),
      "dusk_end_at" => fetch_value(data, "dusk", "end_at")
    }

    values.each do |key, value|
      printf "%s\t%s\n", key, value.nil? ? "" : value
    end
  ' "$config_path")"; then
    fail "读取配置文件失败: ${config_path}"
  fi

  while IFS=$'\t' read -r config_key config_value; do
    case "$config_key" in
      auto_root)
        yaml_auto_root="$config_value"
        ;;
      capture_interval_seconds)
        yaml_capture_interval_seconds="$config_value"
        ;;
      watch_quiet_seconds)
        yaml_watch_quiet_seconds="$config_value"
        ;;
      morning_start_at)
        yaml_morning_start_at="$config_value"
        ;;
      morning_end_at)
        yaml_morning_end_at="$config_value"
        ;;
      dusk_start_at)
        yaml_dusk_start_at="$config_value"
        ;;
      dusk_end_at)
        yaml_dusk_end_at="$config_value"
        ;;
    esac
  done <<< "$config_values"

  AUTO_ROOT="${AUTO_ROOT:-${AUTO_TIMELAPSE_ROOT:-${yaml_auto_root:-/Users/shw/Pictures/AutoTimelapse}}}"
  CAPTURE_INTERVAL_SECONDS="${CAPTURE_INTERVAL_SECONDS:-${yaml_capture_interval_seconds:-6}}"
  WATCH_QUIET_SECONDS="${WATCH_QUIET_SECONDS:-${yaml_watch_quiet_seconds:-60}}"
  MORNING_START_AT="${MORNING_START_AT:-${START_AT:-${yaml_morning_start_at:-03:00}}}"
  MORNING_END_AT="${MORNING_END_AT:-${END_AT:-${yaml_morning_end_at:-09:00}}}"
  DUSK_START_AT="${DUSK_START_AT:-${yaml_dusk_start_at:-}}"
  DUSK_END_AT="${DUSK_END_AT:-${yaml_dusk_end_at:-}}"
  AUTO_TIMELAPSE_CONFIG_PATH="$config_path"
}
