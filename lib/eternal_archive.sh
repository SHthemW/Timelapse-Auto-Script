#!/usr/bin/env bash

eternal_format_epoch() {
  local epoch="$1"
  local format="$2"

  if date -r "$epoch" "$format" >/dev/null 2>&1; then
    date -r "$epoch" "$format"
  else
    date -d "@${epoch}" "$format"
  fi
}

eternal_create_batch_directory() {
  local start_epoch="$1"
  local end_epoch="$2"
  local date_part
  local time_part
  local candidate
  local suffix=1

  date_part="$(eternal_format_epoch "$start_epoch" '+%F')"
  time_part="$(eternal_format_epoch "$start_epoch" '+%H%M')-$(eternal_format_epoch "$end_epoch" '+%H%M')"
  mkdir -p "${AUTO_ROOT}/${date_part}"
  candidate="${AUTO_ROOT}/${date_part}/${time_part}"
  while ! mkdir "$candidate" 2>/dev/null; do
    [[ -e "$candidate" ]] || fail "无法创建永续批次目录: ${candidate}"
    suffix=$((suffix + 1))
    candidate="${AUTO_ROOT}/${date_part}/${time_part}-${suffix}"
  done
  printf '%s\n' "$candidate"
}

eternal_remove_manifest_from_pending() {
  local manifest="$1"
  local filtered="${ETERNAL_PENDING_FILE}.recovery.$$"

  awk -F '\t' 'NR == FNR { archived[$1] = 1; next } !($1 in archived)' \
    "$manifest" "$ETERNAL_PENDING_FILE" > "$filtered"
  mv "$filtered" "$ETERNAL_PENDING_FILE"
}

eternal_archive_manifest() {
  local manifest="$1"
  local sequence="$2"
  local first_line
  local last_line
  local start_epoch
  local end_epoch
  local batch_dir
  local group
  local image
  local image_count
  local ready_path
  local destination_file="${manifest}.destination"

  ready_path="${ETERNAL_QUEUE_DIR}/$(printf '%08d' "$sequence").ready"
  if [[ -L "$ready_path" ]]; then
    rm -f "$manifest" "$destination_file"
    return 0
  fi

  first_line="$(head -n 1 "$manifest")"
  last_line="$(tail -n 1 "$manifest")"
  IFS=$'\t' read -r _ start_epoch <<< "$first_line"
  IFS=$'\t' read -r _ end_epoch <<< "$last_line"
  if [[ -f "$destination_file" ]]; then
    batch_dir="$(cat "$destination_file")"
    mkdir -p "$batch_dir"
  else
    batch_dir="$(eternal_create_batch_directory "$start_epoch" "$end_epoch")"
    printf '%s\n' "$batch_dir" > "$destination_file"
  fi

  while IFS=$'\t' read -r group _; do
    for image in "$ETERNAL_CAPTURE_DIR"/"$(printf '%04d' "$group")"_*; do
      [[ -f "$image" ]] || continue
      mv "$image" "$batch_dir/"
    done
    rmdir "${ETERNAL_COMPLETED_DIR}/${group}" >/dev/null 2>&1 || true
  done < "$manifest"

  printf '%s\t%s\t%s\n' \
    "$(eternal_format_epoch "$start_epoch" '+%F')" \
    "$(eternal_format_epoch "$start_epoch" '+%H:%M')" \
    "$(eternal_format_epoch "$end_epoch" '+%H:%M')" \
    > "${batch_dir}/.eternal-batch.tsv"
  ln -s "$batch_dir" "${ready_path}.tmp.$$"
  mv "${ready_path}.tmp.$$" "$ready_path"
  rm -f "$manifest" "$destination_file"
  image_count="$(find "$batch_dir" -maxdepth 1 -type f -name '*.jp*g' | wc -l | tr -d ' ')"

  log "永续批次 ${sequence} 已归档并进入处理队列: 目录=${batch_dir}, 图片=${image_count}"
  webhook_notify_event "eternal_batch_queued" "永续拍摄批次 ${sequence} 已归档并进入处理队列，目录 ${batch_dir}，图片数量 ${image_count}"
}

eternal_archive_with_retry() {
  local manifest="$1"
  local sequence="$2"

  while [[ -f "$manifest" ]]; do
    if eternal_archive_manifest "$manifest" "$sequence"; then
      return 0
    fi
    log "永续批次 ${sequence} 归档失败，${ETERNAL_ARCHIVE_RETRY_SECONDS:-60}s 后重试"
    webhook_notify_event "eternal_archive_retrying" "永续批次 ${sequence} 归档失败，将在 ${ETERNAL_ARCHIVE_RETRY_SECONDS:-60}s 后重试"
    sleep "${ETERNAL_ARCHIVE_RETRY_SECONDS:-60}" || true
  done
}

eternal_recover_archives() {
  local manifest
  local name
  local sequence

  for manifest in "$ETERNAL_STATE_DIR"/batch.*.tsv; do
    [[ -f "$manifest" ]] || continue
    eternal_remove_manifest_from_pending "$manifest"
    name="$(basename "$manifest")"
    sequence="${name#batch.}"
    sequence="${sequence%.tsv}"
    eternal_archive_with_retry "$manifest" "$((10#$sequence))" &
    ETERNAL_RECOVERY_PIDS="${ETERNAL_RECOVERY_PIDS} $!"
    log "正在恢复未完成的永续归档批次 ${sequence}, pid=$!"
  done
}

eternal_wait_recovery_archives() {
  local pid
  for pid in $ETERNAL_RECOVERY_PIDS; do
    wait "$pid" >/dev/null 2>&1 || true
  done
  ETERNAL_RECOVERY_PIDS=""
}

eternal_terminate_recovery_archives() {
  local pid
  for pid in $ETERNAL_RECOVERY_PIDS; do
    terminate_process "$pid" "永续归档恢复进程"
  done
  ETERNAL_RECOVERY_PIDS=""
}
