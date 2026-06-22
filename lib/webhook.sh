#!/usr/bin/env bash

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

webhook_render_template() {
  local template="$1"
  local content="$2"
  local time_value="$3"
  local img_base64="$4"
  local img_md5="$5"

  template="${template//__CONTENT__/$content}"
  template="${template//__TIME__/$time_value}"
  template="${template//__IMGBASE64__/$img_base64}"
  template="${template//__IMGMD5__/$img_md5}"

  printf '%s' "$template"
}

webhook_send_payload() {
  local payload="$1"
  local event_name="$2"
  local payload_file

  payload_file="$(mktemp)"
  printf '%s' "$payload" > "$payload_file"
  if ! curl -fsS --connect-timeout 10 --max-time 30 \
    --data-binary "@${payload_file}" \
    "$WEBHOOK_URL" >/dev/null; then
    rm -f "$payload_file"
    log "webhook推送失败: ${event_name}"
    return 0
  fi

  rm -f "$payload_file"
  log "webhook推送成功: ${event_name}"
}

webhook_validate_template() {
  local template="$1"
  local required_token="$2"
  local label="$3"

  case "$template" in
    *"$required_token"*) ;;
    *) fail "${label}必须包含 ${required_token} 占位符" ;;
  esac
}

load_webhook_config() {
  local script_dir="$1"
  local config_path="${AUTO_TIMELAPSE_WEBHOOK_CONFIG:-${script_dir}/config/webhook.yaml}"
  local config_values
  local config_key
  local config_value
  local yaml_enabled="false"
  local yaml_url=""
  local yaml_body=""
  local yaml_push_image="false"
  local yaml_image_body=""

  if [[ "${WEBHOOK_CONFIG_LOADED:-0}" -eq 1 ]]; then
    return 0
  fi

  WEBHOOK_CONFIG_PATH="$config_path"
  WEBHOOK_ENABLED=0
  WEBHOOK_URL=""
  WEBHOOK_BODY_TEMPLATE=""
  WEBHOOK_PUSH_IMAGE=0
  WEBHOOK_IMAGE_BODY_TEMPLATE=""

  if [[ ! -f "$config_path" ]]; then
    mkdir -p "$(dirname "$config_path")"
    cat >"$config_path" <<'EOF'
# webhook 配置。
# enabled 为 true 时才会执行推送。
# body 必须包含 __CONTENT__ 占位符。
# image_body 在 push_image 为 true 时必须包含 __IMGBASE64__ 和 __IMGMD5__ 占位符。
enabled:
url:
body:
push_image:
image_body:
EOF
    pause_and_exit "检测到 webhook 配置文件不存在，已自动创建空配置文件: ${config_path}" "请完善 webhook 配置文件后按回车键退出"
  fi

  if ! config_values="$(ruby -r yaml -e '
    def fetch_value(data, *keys)
      keys.reduce(data) { |memo, key| memo.is_a?(Hash) ? memo[key] : nil }
    end

    config_path = ARGV.fetch(0)
    data = YAML.load_file(config_path) || {}

    values = {
      "enabled" => fetch_value(data, "enabled"),
      "url" => fetch_value(data, "url"),
      "body" => fetch_value(data, "body"),
      "push_image" => fetch_value(data, "push_image"),
      "image_body" => fetch_value(data, "image_body")
    }

    values.each do |key, value|
      printf "%s\t%s\n", key, value.nil? ? "" : value
    end
  ' "$config_path")"; then
    fail "读取 webhook 配置文件失败: ${config_path}"
  fi

  while IFS=$'\t' read -r config_key config_value; do
    case "$config_key" in
      enabled)
        yaml_enabled="$config_value"
        ;;
      url)
        yaml_url="$config_value"
        ;;
      body)
        yaml_body="$config_value"
        ;;
      push_image)
        yaml_push_image="$config_value"
        ;;
      image_body)
        yaml_image_body="$config_value"
        ;;
    esac
  done <<< "$config_values"

  case "$(printf '%s' "$yaml_enabled" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on) WEBHOOK_ENABLED=1 ;;
    *) WEBHOOK_ENABLED=0 ;;
  esac

  case "$(printf '%s' "$yaml_push_image" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on) WEBHOOK_PUSH_IMAGE=1 ;;
    *) WEBHOOK_PUSH_IMAGE=0 ;;
  esac

  WEBHOOK_URL="${yaml_url}"
  WEBHOOK_BODY_TEMPLATE="${yaml_body}"
  WEBHOOK_IMAGE_BODY_TEMPLATE="${yaml_image_body}"

  if [[ "$WEBHOOK_ENABLED" -eq 1 ]]; then
    [[ -n "$WEBHOOK_URL" ]] || fail "webhook 已开启但 url 为空"
    [[ -n "$WEBHOOK_BODY_TEMPLATE" ]] || fail "webhook 已开启但 body 为空"
    webhook_validate_template "$WEBHOOK_BODY_TEMPLATE" "__CONTENT__" "webhook body"
    if [[ "$WEBHOOK_PUSH_IMAGE" -eq 1 ]]; then
      [[ -n "$WEBHOOK_IMAGE_BODY_TEMPLATE" ]] || fail "webhook 图片推送已开启但 image_body 为空"
      webhook_validate_template "$WEBHOOK_IMAGE_BODY_TEMPLATE" "__IMGBASE64__" "webhook image_body"
      webhook_validate_template "$WEBHOOK_IMAGE_BODY_TEMPLATE" "__IMGMD5__" "webhook image_body"
    fi
  fi

  if [[ "$WEBHOOK_ENABLED" -eq 1 ]]; then
    log "webhook配置检查: 已启用，url=${WEBHOOK_URL}"
    log "webhook配置检查: 普通推送 body 校验通过"
    if [[ "$WEBHOOK_PUSH_IMAGE" -eq 1 ]]; then
      log "webhook配置检查: 图片推送已启用，image_body 校验通过"
    else
      log "webhook配置检查: 图片推送未启用"
    fi
  else
    log "webhook配置检查: 已关闭，路径=${config_path}"
  fi

  export WEBHOOK_CONFIG_LOADED=1 \
    WEBHOOK_CONFIG_PATH \
    WEBHOOK_ENABLED \
    WEBHOOK_URL \
    WEBHOOK_BODY_TEMPLATE \
    WEBHOOK_PUSH_IMAGE \
    WEBHOOK_IMAGE_BODY_TEMPLATE
}

webhook_notify_event() {
  local event_name="$1"
  local content="$2"

  [[ "$WEBHOOK_ENABLED" -eq 1 ]] || return 0

  local payload
  payload="$(webhook_render_template "$WEBHOOK_BODY_TEMPLATE" "$content" "$(date '+%Y-%m-%d %H:%M:%S')" "" "")"
  webhook_send_payload "$payload" "$event_name"
}
