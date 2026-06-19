#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_PATH="${SCRIPT_DIR}/auto_timelapse.sh"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-300}"

current_pid=""
stop_requested=0

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# shellcheck source=lib/webhook.sh
source "${SCRIPT_DIR}/lib/webhook.sh"

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

run_once() {
  local status

  /bin/bash "$RUNNER_PATH" &
  current_pid=$!
  log "已启动自动 Timelapse 子任务, pid=${current_pid}"

  set +e
  wait "$current_pid"
  status=$?
  set -e

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

  trap request_stop INT TERM

  log "开始永久循环自动 Timelapse，每次会按配置选择下一段清晨或黄昏任务"
  log "手动关闭此终端窗口或按 Ctrl+C 可停止循环"

  while [[ "$stop_requested" -eq 0 ]]; do
    set +e
    run_once
    status=$?
    set -e

    if [[ "$stop_requested" -ne 0 ]]; then
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
