#!/usr/bin/env bash

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  log "错误: $*"
  exit 1
}

pause_and_exit() {
  local message="$1"
  local prompt="${2:-请按回车键继续}"

  log "$message"
  printf '%s' "$prompt"

  if [[ -r /dev/tty ]]; then
    read -r _ </dev/tty || true
  elif [[ -t 0 ]]; then
    read -r _ || true
  else
    sleep 5
  fi

  exit 1
}

find_command() {
  local candidate
  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

next_iso_date() {
  local base_date="$1"

  if date -j -v+1d -f '%F' "$base_date" '+%F' >/dev/null 2>&1; then
    date -j -v+1d -f '%F' "$base_date" '+%F'
    return
  fi

  date -d "$base_date 1 day" '+%F'
}
