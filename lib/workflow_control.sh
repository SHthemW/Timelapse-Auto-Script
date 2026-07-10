#!/usr/bin/env bash

camera_pid=""
bracket_pid=""
finish_capture_early_requested=0

terminate_process_tree() {
  local pid="$1"
  local child_pid

  while IFS= read -r child_pid; do
    [[ -n "$child_pid" ]] || continue
    terminate_process_tree "$child_pid"
  done < <(pgrep -P "$pid" 2>/dev/null || true)
  kill "$pid" >/dev/null 2>&1 || true
}

terminate_process() {
  local pid="$1"
  local name="$2"

  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    log "正在停止 ${name}, pid=${pid}"
    terminate_process_tree "$pid"
    wait "$pid" >/dev/null 2>&1 || true
  fi
}

cleanup_on_signal() {
  log "收到中断信号，正在清理后台进程"
  terminate_process "$camera_pid" "camera-timelapse"
  terminate_process "$bracket_pid" "Bracketlapse standby"
  camera_finish_output_monitor
  bracketlapse_finish_output_monitor
  exit 130
}

finish_capture_early() {
  if [[ "$finish_capture_early_requested" -ne 0 ]]; then
    return
  fi

  finish_capture_early_requested=1
  if [[ -n "$camera_pid" ]] && kill -0 "$camera_pid" >/dev/null 2>&1; then
    log "收到 Ctrl+I，正在立即停止 camera-timelapse 拍摄进程, pid=${camera_pid}"
    terminate_process_tree "$camera_pid"
  else
    log "收到 Ctrl+I，拍摄进程已经结束，继续等待后续处理和导出"
  fi
}

wait_for_process() {
  local pid="$1"
  local name="$2"
  local status

  while true; do
    if wait "$pid"; then
      status=0
    else
      status=$?
    fi

    if kill -0 "$pid" >/dev/null 2>&1; then
      continue
    fi
    break
  done

  if [[ "$status" -ne 0 ]]; then
    log "${name} 退出码为 ${status}"
  else
    log "${name} 已正常完成"
  fi

  return "$status"
}
