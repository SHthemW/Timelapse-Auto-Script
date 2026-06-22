#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/schedule.sh
source "${SCRIPT_DIR}/lib/schedule.sh"
# shellcheck source=lib/disk.sh
source "${SCRIPT_DIR}/lib/disk.sh"
# shellcheck source=lib/webhook.sh
source "${SCRIPT_DIR}/lib/webhook.sh"
# shellcheck source=lib/webhook_image.sh
source "${SCRIPT_DIR}/lib/webhook_image.sh"
# shellcheck source=lib/camera_notify.sh
source "${SCRIPT_DIR}/lib/camera_notify.sh"
# shellcheck source=lib/bracketlapse_notify.sh
source "${SCRIPT_DIR}/lib/bracketlapse_notify.sh"
# shellcheck source=lib/runner.sh
source "${SCRIPT_DIR}/lib/runner.sh"

main() {
  local camera_cmd
  local bracket_cmd
  local work_dir

  trap cleanup_on_signal INT TERM

  load_config "$SCRIPT_DIR"
  load_webhook_config "$SCRIPT_DIR"
  validate_schedule_config

  log "开始自动 Timelapse 流程"
  log "使用配置文件: ${AUTO_TIMELAPSE_CONFIG_PATH}"

  camera_cmd="$(find_command camera-timelapse)" \
    || fail "找不到 camera-timelapse，请确认它已经在 PATH 中"
  bracket_cmd="$(find_command brackerlapse bracketlapse)" \
    || fail "找不到 brackerlapse 或 bracketlapse，请确认 Bracketlapse 已经在 PATH 中"

  select_time_slot
  work_dir="${AUTO_ROOT}/${SELECTED_WORK_DATE}/${SELECTED_TIME_RANGE_DIR}"

  log "清晨时间段: ${MORNING_START_AT}-${MORNING_END_AT}"
  log "黄昏时间段: ${DUSK_START_AT}-${DUSK_END_AT}"
  log "选定任务类型: ${SELECTED_SLOT_LABEL}延时摄影"
  log "选定任务日期: ${SELECTED_WORK_DATE}"
  log "选定时间范围: ${SELECTED_TIME_RANGE_DIR}"
  log "工作目录: ${work_dir}"
  webhook_notify_event "scheduled" "拍摄预约已创建：${SELECTED_SLOT_LABEL}延时摄影计划于 ${SELECTED_WORK_DATE} ${SELECTED_START_AT}-${SELECTED_END_AT} 执行，工作目录 ${work_dir}"

  run_timelapse \
    "$camera_cmd" \
    "$bracket_cmd" \
    "$work_dir" \
    "$SELECTED_WORK_DATE" \
    "$SELECTED_START_AT" \
    "$SELECTED_END_AT"

  log "Bracketlapse 处理完成，脚本退出"
}

main "$@"
