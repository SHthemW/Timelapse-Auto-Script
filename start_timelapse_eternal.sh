#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-300}"
ETERNAL_BATCH_GROUPS="${ETERNAL_BATCH_GROUPS:-2000}"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/disk.sh
source "${SCRIPT_DIR}/lib/disk.sh"
# shellcheck source=lib/webhook.sh
source "${SCRIPT_DIR}/lib/webhook.sh"
# shellcheck source=lib/webhook_image.sh
source "${SCRIPT_DIR}/lib/webhook_image.sh"
# shellcheck source=lib/bracketlapse_notify.sh
source "${SCRIPT_DIR}/lib/bracketlapse_notify.sh"
# shellcheck source=lib/workflow_control.sh
source "${SCRIPT_DIR}/lib/workflow_control.sh"
# shellcheck source=lib/runner.sh
source "${SCRIPT_DIR}/lib/runner.sh"
# shellcheck source=lib/keyboard_control.sh
source "${SCRIPT_DIR}/lib/keyboard_control.sh"
# shellcheck source=lib/eternal_archive.sh
source "${SCRIPT_DIR}/lib/eternal_archive.sh"
# shellcheck source=lib/eternal_capture.sh
source "${SCRIPT_DIR}/lib/eternal_capture.sh"
# shellcheck source=lib/eternal_camera_monitor.sh
source "${SCRIPT_DIR}/lib/eternal_camera_monitor.sh"
# shellcheck source=lib/eternal_worker.sh
source "${SCRIPT_DIR}/lib/eternal_worker.sh"

eternal_camera_pid=""
eternal_worker_pid=""
eternal_hard_stop=0
eternal_graceful_stop=0
eternal_stop_after_batch=0
eternal_stop_reason=""

cleanup_eternal_exit() {
  stop_keyboard_listener
  eternal_release_lock
}

request_eternal_hard_stop() {
  eternal_hard_stop=1
  eternal_stop_reason="Ctrl+C"
  log "收到 Ctrl+C，正在立即停止永续拍摄和所有后台进程"
  stop_keyboard_listener
  terminate_process "$eternal_camera_pid" "永续 camera-timelapse"
  terminate_process "$ETERNAL_CAMERA_MONITOR_PID" "永续拍摄输出监控"
  eternal_terminate_recovery_archives
  terminate_process "$eternal_worker_pid" "永续后台处理进程"
}

request_eternal_finish_now() {
  [[ "$eternal_graceful_stop" -eq 0 ]] || return
  eternal_graceful_stop=1
  eternal_stop_reason="Ctrl+I"
  log "收到 Ctrl+I，立即停止拍摄并处理剩余完整组"
  stop_keyboard_listener
  terminate_process "$eternal_camera_pid" "永续 camera-timelapse"
}

request_eternal_finish_after_batch() {
  [[ "$eternal_stop_after_batch" -eq 0 ]] || return
  eternal_stop_after_batch=1
  eternal_stop_reason="Ctrl+U"
  touch "$ETERNAL_STOP_AFTER_BATCH_FILE"
  log "收到 Ctrl+U，将在当前批次达到 ${ETERNAL_BATCH_GROUPS} 组后停止拍摄"
  stop_keyboard_listener
}

finish_eternal_batch_boundary() {
  [[ "$eternal_stop_after_batch" -ne 0 ]] || return
  eternal_graceful_stop=1
  log "当前批次已达到 ${ETERNAL_BATCH_GROUPS} 组，正在按 Ctrl+U 请求停止拍摄"
  terminate_process "$eternal_camera_pid" "永续 camera-timelapse"
}

wait_before_eternal_retry() {
  local elapsed=0
  while [[ "$elapsed" -lt "$RETRY_DELAY_SECONDS" ]]; do
    [[ "$eternal_hard_stop" -eq 0 && "$eternal_graceful_stop" -eq 0 ]] || return
    sleep 1 || true
    elapsed=$((elapsed + 1))
  done
}

run_eternal_camera() {
  local camera_cmd="$1"
  local status

  eternal_camera_begin_output_monitor
  PYTHONUNBUFFERED=1 "$camera_cmd" "$ETERNAL_CAPTURE_DIR" \
    --interval "$CAPTURE_INTERVAL_SECONDS" \
    > "$ETERNAL_CAMERA_OUTPUT_PIPE" 2>&1 </dev/null &
  eternal_camera_pid=$!
  log "永续 camera-timelapse 拍摄进程已启动, pid=${eternal_camera_pid}"
  webhook_notify_event "camera_process_started" "永续 camera-timelapse 已立即启动，间隔 ${CAPTURE_INTERVAL_SECONDS}s，暂存目录 ${ETERNAL_CAPTURE_DIR}"

  if wait_for_process "$eternal_camera_pid" "永续 camera-timelapse"; then
    status=0
  else
    status=$?
  fi
  eternal_camera_pid=""
  eternal_camera_finish_output_monitor
  return "$status"
}

finish_eternal_gracefully() {
  local archive_count
  local incomplete_count
  local failed_count

  log "根据 ${eternal_stop_reason} 请求，正在整理并处理最后一批完整组"
  webhook_notify_event "eternal_stop_requested" "永续拍摄收到 ${eternal_stop_reason} 请求，正在完成剩余批次处理和导出"
  eternal_sync_complete_groups
  eternal_wait_recovery_archives
  eternal_recover_archives
  eternal_wait_recovery_archives
  eternal_finalize_pending_batch
  touch "$ETERNAL_QUEUE_STOP_FILE"
  wait "$eternal_worker_pid" >/dev/null 2>&1 || true
  eternal_worker_pid=""

  incomplete_count="$(find "$ETERNAL_CAPTURE_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')"
  if [[ "$incomplete_count" -gt 0 ]]; then
    log "忽略并清理未形成完整组的照片: 数量=${incomplete_count}"
    find "$ETERNAL_CAPTURE_DIR" -maxdepth 1 -type f -delete
  fi
  rm -f "$ETERNAL_STOP_AFTER_BATCH_FILE" "$ETERNAL_QUEUE_STOP_FILE"
  failed_count="$(find "$ETERNAL_QUEUE_DIR" -maxdepth 1 -type l -name '*.failed' | wc -l | tr -d ' ')"
  archive_count="$(find "$ETERNAL_STATE_DIR" -maxdepth 1 -type f -name 'batch.*.tsv' | wc -l | tr -d ' ')"
  if [[ "$failed_count" -gt 0 || "$archive_count" -gt 0 ]]; then
    log "永续拍摄已关闭，但有 ${failed_count} 个处理失败批次和 ${archive_count} 个未完成归档批次"
    webhook_notify_event "ended" "永续拍摄已关闭，但仍有失败或未完成后台批次，停止方式 ${eternal_stop_reason}"
    return 1
  fi
  log "永续拍摄及所有后台任务已完成并关闭"
  webhook_notify_event "ended" "永续拍摄及所有后台批次已完成并关闭，停止方式 ${eternal_stop_reason}"
}

main() {
  local camera_cmd
  local bracket_cmd
  local status

  load_config "$SCRIPT_DIR"
  load_webhook_config "$SCRIPT_DIR"
  [[ "$ETERNAL_BATCH_GROUPS" =~ ^[1-9][0-9]*$ ]] || fail "ETERNAL_BATCH_GROUPS 必须为正整数"
  camera_cmd="$(find_command camera-timelapse)" || fail "找不到 camera-timelapse"
  bracket_cmd="$(find_command brackerlapse bracketlapse)" || fail "找不到 Bracketlapse"

  ETERNAL_MAIN_PID="$$"
  export ETERNAL_BATCH_GROUPS ETERNAL_MAIN_PID
  eternal_initialize_state
  eternal_recover_archives
  SELECTED_SLOT_LABEL="永续批次"

  trap cleanup_eternal_exit EXIT
  trap request_eternal_hard_stop INT TERM
  trap request_eternal_finish_after_batch USR1
  trap request_eternal_finish_now USR2
  trap finish_eternal_batch_boundary HUP

  eternal_processing_worker "$bracket_cmd" &
  eternal_worker_pid=$!
  log "永续后台处理工作进程 PID=${eternal_worker_pid}"
  log "永续 Timelapse 已启动，每 ${ETERNAL_BATCH_GROUPS} 组进入单进程后台处理队列"
  log "按 Ctrl+I 立即结束拍摄，按 Ctrl+U 拍满当前批次后结束，按 Ctrl+C 强制停止"
  webhook_notify_event "runner_started" "永续 Timelapse 已启动，每 ${ETERNAL_BATCH_GROUPS} 组归档并进入单进程后台处理队列"
  start_keyboard_listener

  while [[ "$eternal_hard_stop" -eq 0 && "$eternal_graceful_stop" -eq 0 ]]; do
    if run_eternal_camera "$camera_cmd"; then status=0; else status=$?; fi
    [[ "$eternal_hard_stop" -eq 0 && "$eternal_graceful_stop" -eq 0 ]] || break
    log "永续拍摄进程意外结束，退出码=${status}，${RETRY_DELAY_SECONDS}s 后自动重启"
    webhook_notify_event "eternal_camera_restarting" "永续拍摄进程意外结束，退出码 ${status}，将在 ${RETRY_DELAY_SECONDS}s 后自动重启"
    wait_before_eternal_retry
  done

  if [[ "$eternal_hard_stop" -ne 0 ]]; then
    rm -f "$ETERNAL_STOP_AFTER_BATCH_FILE"
    log "永续拍摄已按 Ctrl+C 强制停止，未完成队列将在下次启动时继续"
    webhook_notify_event "ended" "永续拍摄已按 Ctrl+C 强制停止，未完成队列已保留"
    return 130
  fi
  finish_eternal_gracefully
}

main "$@"
