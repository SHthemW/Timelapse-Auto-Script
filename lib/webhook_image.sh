#!/usr/bin/env bash

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

webhook_file_size_bytes() {
  local file_path="$1"

  if stat -f%z "$file_path" >/dev/null 2>&1; then
    stat -f%z "$file_path"
  else
    stat -c%s "$file_path"
  fi
}

webhook_file_md5() {
  local file_path="$1"

  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$file_path" | awk '{print $1}'
  else
    md5 -q "$file_path"
  fi
}

webhook_file_base64() {
  local file_path="$1"

  base64 "$file_path" | tr -d '\n'
}

webhook_compress_image() {
  local source_image="$1"
  local output_image="$2"
  local tmp_output="${output_image}.tmp.jpg"
  local limit_bytes=$((2 * 1024 * 1024))
  local scale
  local quality
  local size_bytes

  rm -f "$tmp_output" "$output_image"

  for scale in 1.0 0.95 0.9 0.85 0.8 0.75 0.7 0.65 0.6 0.55 0.5; do
    for quality in 4 8 12 16 20 24 28 31; do
      if ! ffmpeg -hide_banner -loglevel error -y -i "$source_image" -frames:v 1 \
        -vf "scale=trunc(iw*${scale}/2)*2:trunc(ih*${scale}/2)*2" \
        -q:v "$quality" "$tmp_output"; then
        continue
      fi

      size_bytes="$(webhook_file_size_bytes "$tmp_output")"
      if [[ "$size_bytes" -le "$limit_bytes" ]]; then
        mv -f "$tmp_output" "$output_image"
        return 0
      fi
    done
  done

  if [[ -f "$tmp_output" ]]; then
    mv -f "$tmp_output" "$output_image"
  fi

  size_bytes="$(webhook_file_size_bytes "$output_image")"
  if [[ "$size_bytes" -le "$limit_bytes" ]]; then
    return 0
  fi

  log "webhook图片压缩失败: ${output_image} 仍然超过 2MB"
  return 1
}

webhook_prepare_image() {
  local work_dir="$1"
  local hdr_dir="${work_dir}/hdr_enfuse"
  local post_dir="${work_dir}/post_img"
  local file_list
  local file_count
  local middle_index
  local source_image
  local copied_image
  local compressed_image
  local source_name

  [[ -d "$hdr_dir" ]] || { log "webhook图片推送跳过: 未找到 hdr_enfuse 目录"; return 1; }

  file_list="$(mktemp)"
  find "$hdr_dir" -maxdepth 1 -type f \( \
    -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.heic' -o -iname '*.tif' -o -iname '*.tiff' \
  \) | sort > "$file_list"
  file_count="$(wc -l < "$file_list" | tr -d ' ')"

  if [[ "$file_count" -le 0 ]]; then
    rm -f "$file_list"
    log "webhook图片推送跳过: hdr_enfuse 目录没有可用图片"
    return 1
  fi

  middle_index=$(((file_count + 1) / 2))
  source_image="$(sed -n "${middle_index}p" "$file_list")"
  rm -f "$file_list"

  [[ -n "$source_image" ]] || { log "webhook图片推送跳过: 无法选中目标图片"; return 1; }

  mkdir -p "$post_dir"
  source_name="$(basename "$source_image")"
  copied_image="${post_dir}/${source_name}"
  compressed_image="${post_dir}/compressed.jpg"

  cp "$source_image" "$copied_image"
  if ! webhook_compress_image "$copied_image" "$compressed_image"; then
    return 1
  fi

  WEBHOOK_IMAGE_SOURCE_PATH="$source_image"
  WEBHOOK_IMAGE_COPY_PATH="$copied_image"
  WEBHOOK_IMAGE_COMPRESSED_PATH="$compressed_image"
  export WEBHOOK_IMAGE_SOURCE_PATH WEBHOOK_IMAGE_COPY_PATH WEBHOOK_IMAGE_COMPRESSED_PATH
}

webhook_notify_image() {
  local event_name="$1"
  local content="$2"
  local image_path="$WEBHOOK_IMAGE_COMPRESSED_PATH"
  local img_base64
  local img_md5
  local payload

  [[ "$WEBHOOK_ENABLED" -eq 1 ]] || return 0
  [[ "$WEBHOOK_PUSH_IMAGE" -eq 1 ]] || return 0
  [[ -n "$image_path" && -f "$image_path" ]] || { log "webhook图片推送跳过: 压缩图片不存在"; return 1; }

  img_base64="$(webhook_file_base64 "$image_path")"
  img_md5="$(webhook_file_md5 "$image_path")"
  payload="$(webhook_render_template "$WEBHOOK_IMAGE_BODY_TEMPLATE" "$content" "$(date '+%Y-%m-%d %H:%M:%S')" "$img_base64" "$img_md5")"
  webhook_send_payload "$payload" "$event_name"
}
