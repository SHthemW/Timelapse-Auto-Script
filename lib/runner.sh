#!/usr/bin/env bash

camera_pid=""
bracket_pid=""

terminate_process() {
  local pid="$1"
  local name="$2"

  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    log "正在停止 ${name}, pid=${pid}"
    kill "$pid" >/dev/null 2>&1 || true
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

wait_for_process() {
  local pid="$1"
  local name="$2"
  local status

  set +e
  wait "$pid"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    log "${name} 退出码为 ${status}"
  else
    log "${name} 已正常完成"
  fi

  return "$status"
}

cleanup_work_dir() {
  local dir="$1"
  local entry_name
  local entry_path

  [[ -d "$dir" ]] || fail "清理目录不存在: ${dir}"

  log "清理工作目录，仅保留 hdr_enfuse 和 hdr_video"
  while IFS= read -r -d '' entry_path; do
    entry_name="$(basename "$entry_path")"
    case "$entry_name" in
      hdr_enfuse | hdr_video)
        log "保留: ${entry_path}"
        ;;
      *)
        log "删除: ${entry_path}"
        rm -rf -- "$entry_path"
        ;;
    esac
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0)
}

run_timelapse() {
  local camera_cmd="$1"
  local bracket_cmd="$2"
  local work_dir="$3"
  local work_date="$4"
  local start_at="$5"
  local end_at="$6"
  local workflow_status=0
  local camera_status=0
  local bracket_status=0
  local bracket_ready=0

  mkdir -p "$work_dir"
  log "已创建或确认工作目录存在"

  log "使用 camera-timelapse 命令: ${camera_cmd}"
  log "使用 Bracketlapse 命令: ${bracket_cmd}"
  webhook_notify_event "runner_started" "拍摄预约已进入守护状态：${SELECTED_SLOT_LABEL}延时摄影，日期 ${work_date}，计划时间段 ${start_at}-${end_at}，等待实际拍摄开始，工作目录 ${work_dir}"

  bracketlapse_begin_output_monitor "$work_dir" "$work_date" "$start_at" "$end_at" "$SELECTED_SLOT_LABEL"
  log "启动 Bracketlapse 监听: 目录=${work_dir}, 静息判定=${WATCH_QUIET_SECONDS}s"
  BRACKLAPSE_RUN_DATE="$work_date" \
    BRACKLAPSE_RUN_START_AT="$start_at" \
    BRACKLAPSE_RUN_END_AT="$end_at" \
    "$bracket_cmd" --standby "$work_dir" "$work_dir" "$WATCH_QUIET_SECONDS" \
    > >(tee "$BRACKETLAPSE_OUTPUT_PIPE") 2>&1 &
  bracket_pid=$!
  log "Bracketlapse 监听进程已启动, pid=${bracket_pid}"
  webhook_notify_event "entered_key_node" "已进入关键节点：Bracketlapse 监听处理已开始，目录 ${work_dir}"

  sleep 2
  if ! kill -0 "$bracket_pid" >/dev/null 2>&1; then
    wait_for_process "$bracket_pid" "Bracketlapse standby" || true
    workflow_status=1
    log "Bracketlapse 监听启动失败"
  else
    bracket_ready=1
  fi

  if [[ "$bracket_ready" -eq 1 ]]; then
    log "启动 camera-timelapse 预约进程: ${work_date} ${start_at}-${end_at}, 间隔=${CAPTURE_INTERVAL_SECONDS}s"
    camera_begin_output_monitor "$work_dir" "$work_date" "$start_at" "$end_at" "$SELECTED_SLOT_LABEL"
    PYTHONUNBUFFERED=1 "$camera_cmd" "$work_dir" \
      --start-at "$start_at" \
      --start-day "$work_date" \
      --end-at "$end_at" \
      --end-day "$work_date" \
      --interval "$CAPTURE_INTERVAL_SECONDS" \
      > "$CAMERA_OUTPUT_PIPE" 2>&1 &
    camera_pid=$!
    log "camera-timelapse 进程已启动, pid=${camera_pid}"
    webhook_notify_event "camera_process_started" "camera-timelapse 预约进程已启动，正在等待实际拍摄窗口：${SELECTED_SLOT_LABEL}延时摄影，日期 ${work_date}，时间段 ${start_at}-${end_at}"

    set +e
    wait_for_process "$camera_pid" "camera-timelapse"
    camera_status=$?
    set -e
    camera_finish_output_monitor
    if [[ "$camera_status" -ne 0 ]]; then
      workflow_status=1
      webhook_notify_event "exited_key_node" "关键节点已结束：camera-timelapse 退出码 ${camera_status}，日期 ${work_date}，时间段 ${start_at}-${end_at}"
      terminate_process "$bracket_pid" "Bracketlapse standby"
      log "拍摄任务失败，已停止监听"
    fi
  fi

  log "拍摄任务完成，等待 Bracketlapse 检测目录静息并自动处理"
  if [[ "$bracket_ready" -eq 1 ]]; then
    set +e
    wait_for_process "$bracket_pid" "Bracketlapse standby"
    bracket_status=$?
    set -e
    if [[ "$bracket_status" -ne 0 ]]; then
      workflow_status=1
      webhook_notify_event "exited_key_node" "关键节点已结束：Bracketlapse 退出码 ${bracket_status}，目录 ${work_dir}"
      log "Bracketlapse 处理失败"
    else
      webhook_notify_event "exited_key_node" "关键节点已结束：Bracketlapse 已完成，目录 ${work_dir}"
    fi
  fi

  bracketlapse_finish_output_monitor

  if [[ "$WEBHOOK_ENABLED" -eq 1 && "$WEBHOOK_PUSH_IMAGE" -eq 1 ]]; then
    if webhook_prepare_image "$work_dir"; then
      webhook_notify_image "webhook-image" "图片推送：${SELECTED_SLOT_LABEL}延时摄影，日期 ${work_date}，时间段 ${start_at}-${end_at}"
    fi
  fi

  cleanup_work_dir "$work_dir"
  disk_check_space "$work_dir" "$DISK_SPACE_WARNING_THRESHOLD_GB"
  webhook_notify_event "ended" "任务已结束：${SELECTED_SLOT_LABEL}延时摄影，日期 ${work_date}，时间段 ${start_at}-${end_at}，工作目录 ${work_dir}"

  if [[ "$workflow_status" -ne 0 || "$camera_status" -ne 0 || "$bracket_status" -ne 0 ]]; then
    return 1
  fi
}
