#!/usr/bin/env bash

ETERNAL_CAMERA_OUTPUT_DIR=""
ETERNAL_CAMERA_OUTPUT_PIPE=""
ETERNAL_CAMERA_MONITOR_PID=""
ETERNAL_RECOVERY_PIDS=""

eternal_acquire_lock() {
  local existing_pid=""

  if mkdir "$ETERNAL_LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "${ETERNAL_LOCK_DIR}/pid"
    return
  fi
  [[ -f "${ETERNAL_LOCK_DIR}/pid" ]] && existing_pid="$(cat "${ETERNAL_LOCK_DIR}/pid")"
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" >/dev/null 2>&1; then
    fail "永续 Timelapse 已在运行, pid=${existing_pid}"
  fi

  rm -f "${ETERNAL_LOCK_DIR}/pid"
  rmdir "$ETERNAL_LOCK_DIR" >/dev/null 2>&1 || fail "无法清理永续 Timelapse 状态锁"
  mkdir "$ETERNAL_LOCK_DIR" || fail "无法创建永续 Timelapse 状态锁"
  printf '%s\n' "$$" > "${ETERNAL_LOCK_DIR}/pid"
}

eternal_release_lock() {
  local owner_pid=""
  [[ -f "${ETERNAL_LOCK_DIR}/pid" ]] && owner_pid="$(cat "${ETERNAL_LOCK_DIR}/pid")"
  [[ "$owner_pid" == "$$" ]] || return 0
  rm -f "${ETERNAL_LOCK_DIR}/pid"
  rmdir "$ETERNAL_LOCK_DIR" >/dev/null 2>&1 || true
}

eternal_initialize_state() {
  local failed_marker
  ETERNAL_STATE_DIR="${AUTO_ROOT}/.eternal"
  ETERNAL_CAPTURE_DIR="${ETERNAL_STATE_DIR}/capture"
  ETERNAL_QUEUE_DIR="${ETERNAL_STATE_DIR}/queue"
  ETERNAL_COMPLETED_DIR="${ETERNAL_STATE_DIR}/completed"
  ETERNAL_PENDING_FILE="${ETERNAL_STATE_DIR}/pending.tsv"
  ETERNAL_COUNTER_FILE="${ETERNAL_STATE_DIR}/batch-counter"
  ETERNAL_LOCK_DIR="${ETERNAL_STATE_DIR}/lock"
  ETERNAL_STOP_AFTER_BATCH_FILE="${ETERNAL_STATE_DIR}/stop-after-batch"
  ETERNAL_QUEUE_STOP_FILE="${ETERNAL_QUEUE_DIR}/STOP"

  mkdir -p "$ETERNAL_STATE_DIR"
  eternal_acquire_lock
  mkdir -p "$ETERNAL_CAPTURE_DIR" "$ETERNAL_QUEUE_DIR" "$ETERNAL_COMPLETED_DIR"
  touch "$ETERNAL_PENDING_FILE"
  [[ -f "$ETERNAL_COUNTER_FILE" ]] || printf '0\n' > "$ETERNAL_COUNTER_FILE"
  rm -f "$ETERNAL_STOP_AFTER_BATCH_FILE" "$ETERNAL_QUEUE_STOP_FILE"
  find "$ETERNAL_QUEUE_DIR" -maxdepth 1 -name '*.tmp.*' -delete
  find "$ETERNAL_STATE_DIR" -maxdepth 1 -name 'pending.tsv.next.*' -delete
  for failed_marker in "$ETERNAL_QUEUE_DIR"/*.failed; do
    [[ -L "$failed_marker" ]] || continue
    mv "$failed_marker" "${failed_marker%.failed}.ready"
  done

  export ETERNAL_STATE_DIR ETERNAL_CAPTURE_DIR ETERNAL_QUEUE_DIR
  export ETERNAL_COMPLETED_DIR ETERNAL_PENDING_FILE ETERNAL_COUNTER_FILE
  export ETERNAL_STOP_AFTER_BATCH_FILE ETERNAL_QUEUE_STOP_FILE
}

eternal_next_batch_sequence() {
  local sequence
  sequence="$(cat "$ETERNAL_COUNTER_FILE")"
  sequence=$((sequence + 1))
  printf '%s\n' "$sequence" > "$ETERNAL_COUNTER_FILE"
  printf '%s\n' "$sequence"
}

eternal_dispatch_batch() {
  local group_count="$1"
  local sequence
  local manifest
  local remaining

  sequence="$(eternal_next_batch_sequence)"
  manifest="${ETERNAL_STATE_DIR}/batch.$(printf '%08d' "$sequence").tsv"
  remaining="${ETERNAL_PENDING_FILE}.next.$$"
  head -n "$group_count" "$ETERNAL_PENDING_FILE" > "$manifest"
  tail -n "+$((group_count + 1))" "$ETERNAL_PENDING_FILE" > "$remaining"
  mv "$remaining" "$ETERNAL_PENDING_FILE"

  eternal_archive_with_retry "$manifest" "$sequence" &
  ETERNAL_LAST_ORGANIZER_PID=$!
  log "永续批次 ${sequence} 已交给归档进程, pid=${ETERNAL_LAST_ORGANIZER_PID}, 组数=${group_count}"
}

eternal_dispatch_full_batches() {
  local pending_count
  pending_count="$(wc -l < "$ETERNAL_PENDING_FILE" | tr -d ' ')"
  while [[ "$pending_count" -ge "$ETERNAL_BATCH_GROUPS" ]]; do
    eternal_dispatch_batch "$ETERNAL_BATCH_GROUPS"
    pending_count=$((pending_count - ETERNAL_BATCH_GROUPS))
    if [[ -f "$ETERNAL_STOP_AFTER_BATCH_FILE" ]]; then
      kill -HUP "$ETERNAL_MAIN_PID" >/dev/null 2>&1 || true
    fi
  done
}

eternal_record_complete_group() {
  local group="$1"
  local count=0
  local image

  [[ -d "${ETERNAL_COMPLETED_DIR}/${group}" ]] && return 0
  for image in "$ETERNAL_CAPTURE_DIR"/"$(printf '%04d' "$group")"_*; do
    [[ -f "$image" ]] || continue
    count=$((count + 1))
  done
  [[ "$count" -ge 3 ]] || return 0

  mkdir "${ETERNAL_COMPLETED_DIR}/${group}" 2>/dev/null || return 0
  printf '%s\t%s\n' "$group" "$(date '+%s')" >> "$ETERNAL_PENDING_FILE"
  eternal_dispatch_full_batches
}

eternal_sync_complete_groups() {
  local image
  local name
  local group

  while IFS= read -r image; do
    name="$(basename "$image")"
    group="${name%%_*}"
    [[ "$group" =~ ^[0-9]+$ ]] || continue
    eternal_record_complete_group "$((10#$group))"
  done < <(find "$ETERNAL_CAPTURE_DIR" -maxdepth 1 -type f -name '*_*.*' | sort)
}

eternal_finalize_pending_batch() {
  local pending_count
  pending_count="$(wc -l < "$ETERNAL_PENDING_FILE" | tr -d ' ')"
  if [[ "$pending_count" -gt 0 ]]; then
    eternal_dispatch_batch "$pending_count"
    wait "$ETERNAL_LAST_ORGANIZER_PID" >/dev/null 2>&1 || true
  fi
}
