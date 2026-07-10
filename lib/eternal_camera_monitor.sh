#!/usr/bin/env bash

eternal_camera_begin_output_monitor() {
  ETERNAL_CAMERA_OUTPUT_DIR="$(mktemp -d)"
  ETERNAL_CAMERA_OUTPUT_PIPE="${ETERNAL_CAMERA_OUTPUT_DIR}/camera.pipe"
  mkfifo "$ETERNAL_CAMERA_OUTPUT_PIPE"

  eternal_camera_forward_output "$ETERNAL_CAMERA_OUTPUT_PIPE" &
  ETERNAL_CAMERA_MONITOR_PID=$!
  export ETERNAL_CAMERA_OUTPUT_DIR ETERNAL_CAMERA_OUTPUT_PIPE ETERNAL_CAMERA_MONITOR_PID
}

eternal_camera_finish_output_monitor() {
  if [[ -n "$ETERNAL_CAMERA_MONITOR_PID" ]]; then
    wait "$ETERNAL_CAMERA_MONITOR_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$ETERNAL_CAMERA_OUTPUT_DIR" ]]; then
    rm -rf -- "$ETERNAL_CAMERA_OUTPUT_DIR"
  fi

  ETERNAL_CAMERA_OUTPUT_DIR=""
  ETERNAL_CAMERA_OUTPUT_PIPE=""
  ETERNAL_CAMERA_MONITOR_PID=""
}

eternal_camera_forward_output() {
  local output_pipe="$1"
  local line
  local current_group=""
  local capture_started=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line"
    if [[ "$line" =~ Starting[[:space:]]capture[[:space:]]round[[:space:]]([0-9]+) ]]; then
      current_group="$((10#${BASH_REMATCH[1]}))"
      if [[ "$capture_started" -eq 0 ]]; then
        capture_started=1
        log "检测到永续 camera-timelapse 真正开始拍摄"
        webhook_notify_event "entered_key_node" "已进入关键节点：永续 camera-timelapse 真正开始拍摄，暂存目录 ${ETERNAL_CAPTURE_DIR}"
      fi
      continue
    fi

    case "$line" in
      *"Deleting "*" from camera"*)
        if [[ -n "$current_group" ]]; then
          eternal_record_complete_group "$current_group"
        fi
        ;;
    esac
  done < "$output_pipe"

  eternal_sync_complete_groups
  wait >/dev/null 2>&1 || true
  if [[ "$capture_started" -eq 1 ]]; then
    log "检测到永续 camera-timelapse 拍摄进程结束"
    webhook_notify_event "exited_key_node" "关键节点已结束：永续 camera-timelapse 拍摄进程已结束，暂存目录 ${ETERNAL_CAPTURE_DIR}"
  fi
}
