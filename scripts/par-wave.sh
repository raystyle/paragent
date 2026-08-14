#!/usr/bin/env bash
# par-wave.sh — 渐进式批量派发(事件驱动启动)
# 用法: par-wave.sh --mode dev|research|review [--timeout-min N] [--layout tab|stack] \
#          <tid>=<model-cmd|@matrix/track> ...
#   布局默认: 一律 tab（每任务一 tab；agent 不开右侧窗格）。可用 --layout stack 覆盖。
#   dev=worktree；research/review=只读无 worktree
#   启动串行: par-run --launch-only 回执后才下一个; 启动后并发 par_finish 收割。
#   rc0=全 done; 否则 rc2
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/par-lib.sh"

MODE=""; TMO_MIN=15; LAYOUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mode)        MODE=${2:-}; shift 2 ;;
    --timeout-min) TMO_MIN=${2:-15}; shift 2 ;;
    --layout)      LAYOUT=${2:-}; shift 2 ;;
    -*) err "unknown arg: $1"; exit 1 ;;
    *)  break ;;
  esac
done
[ "$MODE" = dev ] || [ "$MODE" = research ] || [ "$MODE" = review ] \
  || { err "need --mode dev|research|review"; exit 1; }
[[ "$TMO_MIN" =~ ^[0-9]+$ ]] || { err "--timeout-min 须为正整数"; exit 1; }
[ $# -ge 1 ] || { err "need <tid>=<model-cmd|@matrix/track>..."; exit 1; }
LAYOUT=${LAYOUT:-tab}
[ "$LAYOUT" = tab ] || [ "$LAYOUT" = stack ] || { err "--layout 须 tab|stack"; exit 1; }

RUN="$(dirname "${BASH_SOURCE[0]}")/par-run.sh"
TIDS=()
for spec in "$@"; do
  TID=${spec%%=*}; CMD=${spec#*=}
  { [ "$TID" != "$spec" ] && [ -n "$CMD" ]; } || { err "任务规格须 <tid>=<cmd|@matrix/track>: $spec"; exit 1; }
  [[ "$TID" =~ ^[a-z][a-z0-9-]{1,32}$ ]] || { err "task-id 须匹配 [a-z][a-z0-9-]{1,32}: $TID"; exit 1; }
  if bash "$RUN" "$TID" "$CMD" --mode "$MODE" --timeout-min "$TMO_MIN" --layout "$LAYOUT" --launch-only >/dev/null; then
    TIDS+=("$TID")
    RESOLVED=$(par_matrix_resolve "$CMD" 2>/dev/null || echo "$CMD")
    echo "parallel: launched $TID layout=$LAYOUT cmd=$RESOLVED"
  else
    echo "parallel: launch failed $TID(不拖全局,继续下一个)" >&2
  fi
done
[ ${#TIDS[@]} -ge 1 ] || { err "全部启动失败"; exit 2; }

# 收割:每任务后台 par_finish,等全部落终态
pids=()
for TID in "${TIDS[@]}"; do
  ( par_finish "$TID" "$TMO_MIN" >/dev/null 2>&1 ) &
  pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done

fail=0
for TID in "${TIDS[@]}"; do
  ST=$(cat "$PWD/.parallel/$TID/state" 2>/dev/null || echo missing)
  echo "parallel: $TID -> $ST"
  [ "$ST" = done ] || fail=1
done
[ "$fail" = 0 ] && exit 0 || exit 2
