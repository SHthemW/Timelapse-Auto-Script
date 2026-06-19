#!/usr/bin/env bash

validate_time_value() {
  local name="$1"
  local value="$2"

  [[ "$value" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] \
    || fail "${name} 必须是 HH:MM 格式，当前值: ${value}"
}

time_to_minutes() {
  local value="$1"
  local hour="${value%%:*}"
  local minute="${value##*:}"

  printf '%d\n' "$((10#$hour * 60 + 10#$minute))"
}

time_to_dir_component() {
  local value="$1"

  printf '%s\n' "${value//:/}"
}

validate_time_range() {
  local label="$1"
  local start_at="$2"
  local end_at="$3"
  local start_minutes
  local end_minutes

  [[ -n "$start_at" && -n "$end_at" ]] || fail "${label}时间段未设置完整"
  validate_time_value "${label}开始时间" "$start_at"
  validate_time_value "${label}结束时间" "$end_at"

  start_minutes="$(time_to_minutes "$start_at")"
  end_minutes="$(time_to_minutes "$end_at")"
  ((start_minutes < end_minutes)) || fail "${label}时间段必须在同一天内按升序设置"
}

validate_schedule_config() {
  validate_time_range "清晨" "$MORNING_START_AT" "$MORNING_END_AT"
  validate_time_range "黄昏" "$DUSK_START_AT" "$DUSK_END_AT"

  local morning_end
  local dusk_start

  morning_end="$(time_to_minutes "$MORNING_END_AT")"
  dusk_start="$(time_to_minutes "$DUSK_START_AT")"
  ((morning_end < dusk_start)) || fail "黄昏开始时间必须晚于清晨结束时间"
}

select_time_slot() {
  local now_hm="${1:-$(date '+%H:%M')}"
  local today="${2:-$(date '+%F')}"
  local now_minutes
  local morning_start
  local morning_end
  local dusk_start
  local dusk_end
  local label
  local start_at
  local end_at
  local work_date

  validate_time_value "当前时间" "$now_hm"

  now_minutes="$(time_to_minutes "$now_hm")"
  morning_start="$(time_to_minutes "$MORNING_START_AT")"
  morning_end="$(time_to_minutes "$MORNING_END_AT")"
  dusk_start="$(time_to_minutes "$DUSK_START_AT")"
  dusk_end="$(time_to_minutes "$DUSK_END_AT")"

  if ((now_minutes >= morning_start && now_minutes < morning_end)); then
    label="清晨"
    start_at="$MORNING_START_AT"
    end_at="$MORNING_END_AT"
    work_date="$today"
  elif ((now_minutes >= morning_end && now_minutes < dusk_start)); then
    label="黄昏"
    start_at="$DUSK_START_AT"
    end_at="$DUSK_END_AT"
    work_date="$today"
  elif ((now_minutes >= dusk_start && now_minutes < dusk_end)); then
    label="黄昏"
    start_at="$DUSK_START_AT"
    end_at="$DUSK_END_AT"
    work_date="$today"
  else
    label="清晨"
    start_at="$MORNING_START_AT"
    end_at="$MORNING_END_AT"
    work_date="$(next_iso_date "$today")"
  fi

  SELECTED_SLOT_LABEL="$label"
  SELECTED_START_AT="$start_at"
  SELECTED_END_AT="$end_at"
  SELECTED_WORK_DATE="$work_date"
  SELECTED_TIME_RANGE_DIR="$(time_to_dir_component "$start_at")-$(time_to_dir_component "$end_at")"
}
