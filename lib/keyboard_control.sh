#!/usr/bin/env bash

keyboard_listener_pid=""
terminal_settings=""

stop_keyboard_listener() {
  if [[ -n "$keyboard_listener_pid" ]]; then
    kill "$keyboard_listener_pid" >/dev/null 2>&1 || true
    wait "$keyboard_listener_pid" >/dev/null 2>&1 || true
    keyboard_listener_pid=""
  fi

  if [[ -n "$terminal_settings" ]]; then
    stty "$terminal_settings" </dev/tty >/dev/null 2>&1 || true
    terminal_settings=""
  fi
}

listen_for_loop_shortcuts() {
  local key
  local loop_pid="$1"

  while IFS= read -r -n 1 key; do
    case "$key" in
      $'\011')
        kill -USR2 "$loop_pid" >/dev/null 2>&1 || true
        return
        ;;
      $'\025')
        kill -USR1 "$loop_pid" >/dev/null 2>&1 || true
        return
        ;;
    esac
  done </dev/tty
}

start_keyboard_listener() {
  if [[ ! -t 0 || ! -r /dev/tty || ! -w /dev/tty ]]; then
    log "当前不是交互式终端，Ctrl+I 和 Ctrl+U 快捷键不可用"
    return
  fi

  terminal_settings="$(stty -g </dev/tty)" || {
    terminal_settings=""
    log "无法读取终端设置，Ctrl+I 和 Ctrl+U 快捷键不可用"
    return
  }

  if ! stty -icanon -echo min 1 time 0 </dev/tty; then
    terminal_settings=""
    log "无法启用终端按键监听，Ctrl+I 和 Ctrl+U 快捷键不可用"
    return
  fi

  listen_for_loop_shortcuts "$$" &
  keyboard_listener_pid=$!
}
