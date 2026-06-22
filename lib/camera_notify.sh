#!/usr/bin/env bash

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CAMERA_OUTPUT_DIR=""
CAMERA_OUTPUT_PIPE=""
CAMERA_OUTPUT_READER_PID=""

camera_begin_output_monitor() {
  local work_dir="$1"
  local work_date="$2"
  local start_at="$3"
  local end_at="$4"
  local slot_label="$5"

  CAMERA_OUTPUT_DIR="$(mktemp -d)"
  CAMERA_OUTPUT_PIPE="${CAMERA_OUTPUT_DIR}/camera.pipe"
  mkfifo "$CAMERA_OUTPUT_PIPE"

  camera_forward_output "$CAMERA_OUTPUT_PIPE" "$work_dir" "$work_date" "$start_at" "$end_at" "$slot_label" &
  CAMERA_OUTPUT_READER_PID=$!

  export CAMERA_OUTPUT_DIR CAMERA_OUTPUT_PIPE CAMERA_OUTPUT_READER_PID
}

camera_finish_output_monitor() {
  if [[ -n "$CAMERA_OUTPUT_READER_PID" ]]; then
    wait "$CAMERA_OUTPUT_READER_PID" >/dev/null 2>&1 || true
  fi

  if [[ -n "$CAMERA_OUTPUT_DIR" ]]; then
    rm -rf -- "$CAMERA_OUTPUT_DIR"
  fi

  CAMERA_OUTPUT_DIR=""
  CAMERA_OUTPUT_PIPE=""
  CAMERA_OUTPUT_READER_PID=""
}

camera_forward_output() {
  local output_pipe="$1"
  local work_dir="$2"
  local work_date="$3"
  local start_at="$4"
  local end_at="$5"
  local slot_label="$6"
  local line
  local capture_started=0
  local capture_ended=0

  [[ -n "$output_pipe" && -p "$output_pipe" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line"

    case "$line" in
      *"Starting capture round "*)
        if [[ "$capture_started" -eq 0 ]]; then
          log "检测到 camera-timelapse 真正开始拍摄"
          webhook_notify_event "entered_key_node" "已进入关键节点：camera-timelapse 真正开始拍摄，${slot_label}延时摄影，日期 ${work_date}，时间段 ${start_at}-${end_at}，目录 ${work_dir}"
          capture_started=1
        fi
        ;;
      *"Scheduled end time "*"reached; stopping after this round"*)
        if [[ "$capture_started" -eq 1 && "$capture_ended" -eq 0 ]]; then
          log "检测到 camera-timelapse 到达结束时间并完成最后一轮拍摄"
          webhook_notify_event "exited_key_node" "关键节点已结束：camera-timelapse 拍摄已按计划结束，${slot_label}延时摄影，日期 ${work_date}，时间段 ${start_at}-${end_at}，目录 ${work_dir}"
          capture_ended=1
        fi
        ;;
    esac
  done < "$output_pipe"

  if [[ "$capture_started" -eq 1 && "$capture_ended" -eq 0 ]]; then
    log "检测到 camera-timelapse 拍摄进程结束"
    webhook_notify_event "exited_key_node" "关键节点已结束：camera-timelapse 拍摄进程已结束，${slot_label}延时摄影，日期 ${work_date}，时间段 ${start_at}-${end_at}，目录 ${work_dir}"
  fi
}
