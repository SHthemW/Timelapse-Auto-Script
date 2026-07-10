#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_PATH="${SCRIPT_DIR}/auto_timelapse.sh"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-300}"

current_pid=""
stop_requested=0
stop_after_current_requested=0
stop_after_current_reason=""

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# shellcheck source=lib/webhook.sh
source "${SCRIPT_DIR}/lib/webhook.sh"
# shellcheck source=lib/keyboard_control.sh
source "${SCRIPT_DIR}/lib/keyboard_control.sh"

terminate_current_run() {
  if [[ -n "$current_pid" ]] && kill -0 "$current_pid" >/dev/null 2>&1; then
    log "正在停止当前延时摄影任务, pid=${current_pid}"
    kill "$current_pid" >/dev/null 2>&1 || true
    wait "$current_pid" >/dev/null 2>&1 || true
  fi
}

request_stop() {
  stop_requested=1
  log "收到停止信号，循环将在当前清理完成后退出"
  terminate_current_run
}

request_stop_after_current() {
  if [[ "$stop_after_current_requested" -eq 0 ]]; then
    stop_after_current_requested=1
    stop_after_current_reason="Ctrl+U"
    log "收到 Ctrl+U，本时间段任务将继续完成，完成后不再启动下一时间段任务"
  fi
  stop_keyboard_listener
}

request_finish_current_now() {
  if [[ "$stop_after_current_requested" -eq 0 ]]; then
    stop_after_current_requested=1
    stop_after_current_reason="Ctrl+I"
    log "收到 Ctrl+I，正在停止当前拍摄，后续处理和导出完成后不再启动下一时间段任务"
  fi

  if [[ -n "$current_pid" ]] && kill -0 "$current_pid" >/dev/null 2>&1; then
    kill -USR2 "$current_pid" >/dev/null 2>&1 || true
  fi
  stop_keyboard_listener
}

run_once() {
  local status

  /bin/bash "$RUNNER_PATH" &
  current_pid=$!
  log "已启动自动 Timelapse 子任务, pid=${current_pid}"

  while true; do
    if wait "$current_pid"; then
      status=0
    else
      status=$?
    fi

    if [[ "$stop_after_current_requested" -ne 0 ]] \
      && kill -0 "$current_pid" >/dev/null 2>&1; then
      continue
    fi
    break
  done

  current_pid=""
  return "$status"
}

main() {
  local status

  [[ -x "$RUNNER_PATH" || -f "$RUNNER_PATH" ]] || {
    log "错误: 找不到自动 Timelapse 脚本: ${RUNNER_PATH}"
    exit 1
  }

  load_webhook_config "$SCRIPT_DIR"

  trap stop_keyboard_listener EXIT
  trap request_stop INT TERM
  trap request_stop_after_current USR1
  trap request_finish_current_now USR2

  log "开始永久循环自动 Timelapse，每次会按配置选择下一段清晨或黄昏任务"
  log "手动关闭此终端窗口或按 Ctrl+C 可停止循环"
  log "按 Ctrl+U 可在本时间段任务完成后停止循环"
  log "按 Ctrl+I 可立即停止拍摄，并在处理和导出完成后停止循环"
  start_keyboard_listener

  while [[ "$stop_requested" -eq 0 && "$stop_after_current_requested" -eq 0 ]]; do
    set +e
    run_once
    status=$?
    set -e

    if [[ "$stop_requested" -ne 0 ]]; then
      break
    fi

    if [[ "$stop_after_current_requested" -ne 0 ]]; then
      log "本轮任务已结束，根据 ${stop_after_current_reason} 请求，不再启动下一次清晨或黄昏任务"
      break
    fi

    if [[ "$status" -eq 0 ]]; then
      log "本轮任务完成，继续启用下一次清晨或黄昏任务"
      continue
    fi

    log "本轮任务退出码为 ${status}，${RETRY_DELAY_SECONDS}s 后重试"
    sleep "$RETRY_DELAY_SECONDS"
  done

  log "自动 Timelapse 循环已停止"
}

main "$@"
