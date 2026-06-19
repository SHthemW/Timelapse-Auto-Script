#!/usr/bin/env bash

disk_free_space_gb() {
  local target_path="$1"
  local available_kb

  available_kb="$(df -k "$target_path" | awk 'NR==2 {print $4}')"
  awk -v kb="$available_kb" 'BEGIN { printf "%.2f\n", kb / 1024 / 1024 }'
}

disk_check_space() {
  local target_path="$1"
  local threshold_gb="$2"
  local remaining_gb

  [[ -n "$threshold_gb" ]] || return 0
  [[ "$threshold_gb" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "磁盘空间阈值配置无效: ${threshold_gb}"
  awk "BEGIN { exit !($threshold_gb > 0) }" || return 0

  remaining_gb="$(disk_free_space_gb "$target_path")"
  if awk -v remaining="$remaining_gb" -v threshold="$threshold_gb" 'BEGIN { exit !(remaining < threshold) }'; then
    log "警告: 磁盘剩余空间不足，剩余 ${remaining_gb}GB，低于阈值 ${threshold_gb}GB"
    webhook_notify_event "disk_space_warning" "磁盘剩余空间不足，剩余 ${remaining_gb}GB，低于阈值 ${threshold_gb}GB"
  fi
}
