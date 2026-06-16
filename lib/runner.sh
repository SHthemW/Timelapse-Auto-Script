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

  mkdir -p "$work_dir"
  log "已创建或确认工作目录存在"

  log "使用 camera-timelapse 命令: ${camera_cmd}"
  log "使用 Bracketlapse 命令: ${bracket_cmd}"

  log "启动 Bracketlapse 监听: 目录=${work_dir}, 静息判定=${WATCH_QUIET_SECONDS}s"
  "$bracket_cmd" --standby "$work_dir" "$work_dir" "$WATCH_QUIET_SECONDS" &
  bracket_pid=$!
  log "Bracketlapse 监听进程已启动, pid=${bracket_pid}"

  sleep 2
  if ! kill -0 "$bracket_pid" >/dev/null 2>&1; then
    wait_for_process "$bracket_pid" "Bracketlapse standby" || true
    fail "Bracketlapse 监听启动失败"
  fi

  log "启动 camera-timelapse 拍摄任务: ${work_date} ${start_at}-${end_at}, 间隔=${CAPTURE_INTERVAL_SECONDS}s"
  "$camera_cmd" "$work_dir" \
    --start-at "$start_at" \
    --start-day "$work_date" \
    --end-at "$end_at" \
    --end-day "$work_date" \
    --interval "$CAPTURE_INTERVAL_SECONDS" &
  camera_pid=$!
  log "camera-timelapse 进程已启动, pid=${camera_pid}"

  if ! wait_for_process "$camera_pid" "camera-timelapse"; then
    terminate_process "$bracket_pid" "Bracketlapse standby"
    fail "拍摄任务失败，已停止监听"
  fi

  log "拍摄任务完成，等待 Bracketlapse 检测目录静息并自动处理"
  if ! wait_for_process "$bracket_pid" "Bracketlapse standby"; then
    fail "Bracketlapse 处理失败"
  fi

  cleanup_work_dir "$work_dir"
}
