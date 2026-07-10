#!/usr/bin/env bash

eternal_process_batch() {
  local bracket_cmd="$1"
  local batch_dir="$2"
  local sequence="$3"
  local work_date
  local start_at
  local end_at
  local status

  IFS=$'\t' read -r work_date start_at end_at < "${batch_dir}/.eternal-batch.tsv"
  log "永续批次 ${sequence} 开始后台处理: 目录=${batch_dir}"
  webhook_notify_event "entered_key_node" "已进入关键节点：永续批次 ${sequence} 开始 Bracketlapse 处理，目录 ${batch_dir}"

  start_bracketlapse_processing \
    "$bracket_cmd" "$batch_dir" "$work_date" "$start_at" "$end_at"
  if wait_for_process "$bracket_pid" "永续批次 ${sequence} Bracketlapse"; then
    status=0
  else
    status=$?
  fi
  bracket_pid=""
  bracketlapse_finish_output_monitor

  if [[ "$status" -ne 0 ]]; then
    log "永续批次 ${sequence} 处理失败，保留批次目录等待检查"
    webhook_notify_event "exited_key_node" "关键节点异常结束：永续批次 ${sequence} Bracketlapse 退出码 ${status}，目录 ${batch_dir}"
    return "$status"
  fi

  webhook_notify_event "exited_key_node" "关键节点已结束：永续批次 ${sequence} Bracketlapse 已完成，目录 ${batch_dir}"
  if [[ "$WEBHOOK_ENABLED" -eq 1 && "$WEBHOOK_PUSH_IMAGE" -eq 1 ]]; then
    if webhook_prepare_image "$batch_dir"; then
      webhook_notify_image "webhook-image" "图片推送：永续批次 ${sequence}，日期 ${work_date}，时间 ${start_at}-${end_at}"
    fi
  fi

  cleanup_work_dir "$batch_dir"
  disk_check_space "$batch_dir" "$DISK_SPACE_WARNING_THRESHOLD_GB"
  log "永续批次 ${sequence} 后台处理、导出和清理全部完成"
  webhook_notify_event "ended" "永续批次 ${sequence} 已完成处理、导出和清理，目录 ${batch_dir}"
}

eternal_next_ready_item() {
  local marker
  for marker in "$ETERNAL_QUEUE_DIR"/*.ready; do
    [[ -L "$marker" ]] || continue
    printf '%s\n' "$marker"
    return 0
  done
}

eternal_processing_worker() {
  local bracket_cmd="$1"
  local marker
  local batch_dir
  local sequence
  local failed_marker

  log "永续后台处理进程已启动"
  webhook_notify_event "eternal_worker_started" "永续后台处理进程已启动，队列目录 ${ETERNAL_QUEUE_DIR}"
  while true; do
    marker="$(eternal_next_ready_item)"
    if [[ -z "$marker" ]]; then
      if [[ -f "$ETERNAL_QUEUE_STOP_FILE" ]]; then
        break
      fi
      sleep "${ETERNAL_QUEUE_POLL_SECONDS:-2}"
      continue
    fi

    batch_dir="$(readlink "$marker")"
    sequence="$(basename "$marker" .ready)"
    if eternal_process_batch "$bracket_cmd" "$batch_dir" "$sequence"; then
      rm -f "$marker"
      log "永续批次 ${sequence} 对应处理进程已关闭"
    else
      failed_marker="${marker%.ready}.failed"
      mv "$marker" "$failed_marker"
      log "永续批次 ${sequence} 已移入失败队列: ${failed_marker}"
    fi
  done

  log "永续后台处理队列已清空，工作进程即将关闭"
  webhook_notify_event "eternal_worker_stopped" "永续后台处理队列已清空，工作进程已关闭"
}
