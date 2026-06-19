#!/usr/bin/env bash

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

BRACKETLAPSE_OUTPUT_DIR=""
BRACKETLAPSE_OUTPUT_PIPE=""
BRACKETLAPSE_OUTPUT_READER_PID=""

bracketlapse_begin_output_monitor() {
  local work_dir="$1"
  local work_date="$2"
  local start_at="$3"
  local end_at="$4"
  local slot_label="$5"

  BRACKETLAPSE_OUTPUT_DIR="$(mktemp -d)"
  BRACKETLAPSE_OUTPUT_PIPE="${BRACKETLAPSE_OUTPUT_DIR}/bracketlapse.pipe"
  mkfifo "$BRACKETLAPSE_OUTPUT_PIPE"

  bracketlapse_forward_output "$BRACKETLAPSE_OUTPUT_PIPE" "$work_dir" "$work_date" "$start_at" "$end_at" "$slot_label" &
  BRACKETLAPSE_OUTPUT_READER_PID=$!

  export BRACKETLAPSE_OUTPUT_DIR BRACKETLAPSE_OUTPUT_PIPE BRACKETLAPSE_OUTPUT_READER_PID
}

bracketlapse_finish_output_monitor() {
  if [[ -n "$BRACKETLAPSE_OUTPUT_READER_PID" ]]; then
    wait "$BRACKETLAPSE_OUTPUT_READER_PID" >/dev/null 2>&1 || true
  fi

  if [[ -n "$BRACKETLAPSE_OUTPUT_DIR" ]]; then
    rm -rf -- "$BRACKETLAPSE_OUTPUT_DIR"
  fi

  BRACKETLAPSE_OUTPUT_DIR=""
  BRACKETLAPSE_OUTPUT_PIPE=""
  BRACKETLAPSE_OUTPUT_READER_PID=""
}

bracketlapse_forward_output() {
  local output_pipe="$1"
  local work_dir="$2"
  local work_date="$3"
  local start_at="$4"
  local end_at="$5"
  local slot_label="$6"
  local line
  local enfuse_started=0
  local enfuse_ended=0
  local deflick_started=0
  local deflick_ended=0

  [[ -n "$output_pipe" && -p "$output_pipe" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line"

    case "$line" in
      *"Fusing "*)
        if [[ "$enfuse_started" -eq 0 ]]; then
          webhook_notify_event "entered_key_node" "已进入关键节点：enfuse 开始融合，${slot_label}延时摄影，日期 ${work_date}，时间段 ${start_at}-${end_at}，目录 ${work_dir}"
          enfuse_started=1
        fi
        ;;
      *"Deflickering fused frames."*)
        if [[ "$enfuse_started" -eq 1 && "$enfuse_ended" -eq 0 ]]; then
          webhook_notify_event "exited_key_node" "关键节点已结束：enfuse 融合完成，${slot_label}延时摄影，日期 ${work_date}，时间段 ${start_at}-${end_at}，目录 ${work_dir}"
          enfuse_ended=1
        fi
        if [[ "$deflick_started" -eq 0 ]]; then
          webhook_notify_event "entered_key_node" "已进入关键节点：simple-deflicker 去闪开始，${slot_label}延时摄影，日期 ${work_date}，时间段 ${start_at}-${end_at}，目录 ${work_dir}"
          deflick_started=1
        fi
        ;;
      *"Creating video from "*|*"Done."*)
        if [[ "$deflick_started" -eq 1 && "$deflick_ended" -eq 0 ]]; then
          webhook_notify_event "exited_key_node" "关键节点已结束：simple-deflicker 去闪完成，${slot_label}延时摄影，日期 ${work_date}，时间段 ${start_at}-${end_at}，目录 ${work_dir}"
          deflick_ended=1
        fi
        if [[ "$enfuse_started" -eq 1 && "$enfuse_ended" -eq 0 && "$deflick_started" -eq 0 ]]; then
          webhook_notify_event "exited_key_node" "关键节点已结束：enfuse 融合完成，${slot_label}延时摄影，日期 ${work_date}，时间段 ${start_at}-${end_at}，目录 ${work_dir}"
          enfuse_ended=1
        fi
        ;;
    esac
  done < "$output_pipe"

  if [[ "$enfuse_started" -eq 1 && "$enfuse_ended" -eq 0 ]]; then
    webhook_notify_event "exited_key_node" "关键节点已结束：enfuse 处理结束，${slot_label}延时摄影，日期 ${work_date}，时间段 ${start_at}-${end_at}，目录 ${work_dir}"
  fi

  if [[ "$deflick_started" -eq 1 && "$deflick_ended" -eq 0 ]]; then
    webhook_notify_event "exited_key_node" "关键节点已结束：simple-deflicker 处理结束，${slot_label}延时摄影，日期 ${work_date}，时间段 ${start_at}-${end_at}，目录 ${work_dir}"
  fi
}
