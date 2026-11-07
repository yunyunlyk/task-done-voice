#!/usr/bin/env bash
# 任务完成语音提示 — macOS / Linux。
# 设计要点：调用方拿到返回立刻走人；真正发声在 nohup 背景进程里做；任何失败都 exit 0。
# 本文件必须存成 UTF-8 无 BOM、LF 换行，否则 shebang 会失效、bash 会报错。
set -u

event=done
text=''
lang=''
voice=''
rate=''
dry=0

while [ $# -gt 0 ]; do
  case "$1" in
    --event) event="${2:-done}"; shift 2 || shift ;;
    --text) text="${2:-}"; shift 2 || shift ;;
    --lang) lang="${2:-}"; shift 2 || shift ;;
    --voice) voice="${2:-}"; shift 2 || shift ;;
    --rate) rate="${2:-}"; shift 2 || shift ;;
    --dry-run) dry=1; shift ;;
    -h|--help)
      echo "usage: notify.sh [--event done|ask|error] [--text TEXT] [--lang zh|en] [--voice VOICE] [--rate N] [--dry-run]"
      exit 0 ;;
    *) shift ;;   # 吞掉 harness 追加的多余参数
  esac
done

case "$event" in done|ask|error) ;; *) event=done ;; esac

log() {
  [ -n "${VOICE_NOTIFY_DEBUG:-}" ] || return 0
  local p="${TMPDIR:-/tmp}/voice-notify.log"
  printf '%s | %s | %s | %s | %s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$event" "$lang" "$voice" "$1" "$2" >>"$p" 2>/dev/null || true
}

if [ "${VOICE_NOTIFY_OFF:-}" = "1" ]; then log OFF ''; exit 0; fi

if [ -z "$lang" ]; then
  case "${VOICE_NOTIFY_LANG:-}" in zh|en) lang="$VOICE_NOTIFY_LANG" ;; *) lang=zh ;; esac
fi

if [ -z "$text" ]; then
  if [ "$lang" = "en" ]; then
    case "$event" in
      ask) text='Waiting for your input' ;;
      error) text='Something went wrong' ;;
      *) text='Task complete' ;;
    esac
  else
    case "$event" in
      ask) text='需要你确认一下' ;;
      error) text='出错了，需要看一下' ;;
      *) text='任务完成了' ;;
    esac
  fi
fi

speaker=''
for c in say spd-say espeak-ng espeak; do
  if command -v "$c" >/dev/null 2>&1; then speaker="$c"; break; fi
done

if [ "$dry" = "1" ]; then
  echo "WOULD SAY: $text | lang=$lang voice=${voice:-auto} event=$event speaker=${speaker:-none}"
  exit 0
fi

if [ -z "$speaker" ]; then log NO-TTS "$text"; exit 0; fi

# 节流：窗口内的第二次只记日志，不重复出声。
gap="${VOICE_NOTIFY_MIN_GAP:-10}"
stamp="${TMPDIR:-/tmp}/voice-notify.last"
now=$(date +%s)
if [ "$gap" -gt 0 ] 2>/dev/null && [ -f "$stamp" ]; then
  last=$(cat "$stamp" 2>/dev/null || echo 0)
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  if [ $((now - last)) -lt "$gap" ]; then log SKIP "$text"; exit 0; fi
fi
printf '%s' "$now" >"$stamp" 2>/dev/null || true

args=()
case "$speaker" in
  say)
    if [ -n "$voice" ]; then args+=(-v "$voice"); fi
    if [ -n "$rate" ]; then args+=(-r "$rate"); fi
    args+=("$text") ;;
  spd-say) args+=(--wait "$text") ;;
  *)
    if [ -n "$voice" ]; then args+=(-v "$voice"); fi
    if [ -n "$rate" ]; then args+=(-s "$rate"); fi
    args+=("$text") ;;
esac

( nohup "$speaker" "${args[@]}" >/dev/null 2>&1 & )
log DISPATCHED "$text"
exit 0
