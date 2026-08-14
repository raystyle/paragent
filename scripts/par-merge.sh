#!/usr/bin/env bash
# par-merge.sh — 人确认后顺序 merge:par-merge.sh <task-id>...
# 每个任务:校验 task-id → 校验 state(done|verified) → git merge --no-ff par/<tid> → worktree remove → 删分支
# 冲突:git merge --abort + rc2(报回派原 agent 修复的指引;零重叠拆分时不应发生)
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/par-lib.sh"

[ $# -ge 1 ] || { err "usage: par-merge.sh <task-id>..."; exit 1; }
for TID in "$@"; do
  [[ "$TID" =~ ^[a-z][a-z0-9-]{1,32}$ ]] || { err "task-id 须匹配 [a-z][a-z0-9-]{1,32}: $TID"; exit 1; }
  TD="$PWD/.parallel/$TID"
  ST=$(cat "$TD/state" 2>/dev/null || echo missing)
  case "$ST" in
    done|verified) ;;
    *) err "$TID state=$ST(非 done/verified),跳过——先完成并 verify"; exit 2 ;;
  esac
  git rev-parse --verify "par/$TID" >/dev/null 2>&1 || { err "$TID 无分支 par/$TID"; exit 2; }
  # merge checklist 三行（P-4；脚本不替人看 diff，人确认后才该跑到这里）
  vlog="无 verify 记录（人判豁免）"
  [ -f "$TD/verify.log" ] && vlog=$(grep -q '^PASS$' "$TD/verify.log" 2>/dev/null && echo "PASS" || echo "FAIL/未定")
  diffstat=$(git diff --shortstat HEAD "par/$TID" 2>/dev/null | sed 's/^ *//')
  echo "  checklist $TID:"
  echo "    1) state=$ST（done|verified 才合）"
  echo "    2) verify.log: $vlog"
  echo "    3) diff: ${diffstat:-零变更}（人确认后才 merge——脚本不自动化判 diff）"
  if ! git merge --no-ff "par/$TID" -m "merge: par/$TID" >/dev/null 2>&1; then
    git merge --abort >/dev/null 2>&1 || true
    err "$TID merge 冲突(已 abort)——回派原 agent(同 pane/同 worktree)rebase 修复后再 merge"
    exit 2
  fi
  [ -d "$TD/wt" ] && git worktree remove --force "$TD/wt" >/dev/null 2>&1 || true
  git branch -d "par/$TID" >/dev/null 2>&1 || true
  echo "merged" > "$TD/state"
  echo "parallel: $TID merged"
done
echo "parallel: all merged ($#)"
