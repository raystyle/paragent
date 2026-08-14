#!/usr/bin/env bash
# par-discard.sh — 丢弃任务（极限测/失败波）：不 merge。
# 用法: par-discard.sh <task-id>...
#   对每个 tid: 关任务窗 → worktree remove → 删分支 par/<tid> → state=discarded
#   缺目录/分支不致命，尽量清干净；rc0=全处理完，个别失败打 stderr 继续
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/par-lib.sh"

[ $# -ge 1 ] || { err "usage: par-discard.sh <task-id>..."; exit 1; }

fail=0
for TID in "$@"; do
  [[ "$TID" =~ ^[a-z][a-z0-9-]{1,32}$ ]] || { err "task-id 须匹配 [a-z][a-z0-9-]{1,32}: $TID"; fail=1; continue; }
  TD="$PWD/.parallel/$TID"
  pane=""; layout=tab
  if [ -d "$TD" ]; then
    pane=$(cat "$TD/pane" 2>/dev/null || true)
    layout=$(sed -n 's/^layout=//p' "$TD/meta" 2>/dev/null | head -1)
    layout=${layout:-tab}
  fi
  export PAR_CLOSE_PANE=1
  [ -n "$pane" ] && par_close_task_pane "$pane" "$layout"

  if [ -d "$TD/wt" ]; then
    git worktree remove --force "$TD/wt" >/dev/null 2>&1 \
      || { err "$TID worktree remove failed"; fail=1; }
  fi
  if git rev-parse --verify "par/$TID" >/dev/null 2>&1; then
    # -D：未 merge 的极限测分支也删
    git branch -D "par/$TID" >/dev/null 2>&1 \
      || { err "$TID branch -D failed"; fail=1; }
  fi
  if [ -d "$TD" ]; then
    echo discarded > "$TD/state"
    echo "parallel: $TID discarded ($TD 仍保留 artifact，可手删)"
  else
    echo "parallel: $TID discarded (no .parallel dir)"
  fi
done
git worktree prune >/dev/null 2>&1 || true
[ "$fail" = 0 ] && exit 0 || exit 2
