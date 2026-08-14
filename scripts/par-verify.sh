#!/usr/bin/env bash
# par-verify.sh — 机械 verify 门禁:在 .parallel/<tid>/wt 跑规划定的 verify 命令
# 用法: par-verify.sh <task-id> --cmd "<verify命令>" [--retry N] [--timeout-min N]
#   失败→同 pane 补发修复(等新一轮上报 token PAR-DONE <tid>#<attempt+1>)→复审,≤ retry 次
#   rc0=PASS(state=verified);rc2=FAIL(state=verify-failed,升档重派归主 agent 决策)
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/par-lib.sh"

TID=${1:?usage: par-verify.sh <task-id> --cmd "<cmd>" [--retry N] [--timeout-min N]}
shift
VCMD=""; RETRY=2; TMO_MIN=15
while [ $# -gt 0 ]; do
  case "$1" in
    --cmd)         VCMD=${2:-}; shift 2 ;;
    --retry)       RETRY=${2:-2}; shift 2 ;;
    --timeout-min) TMO_MIN=${2:-15}; shift 2 ;;
    *) err "unknown arg: $1"; exit 1 ;;
  esac
done
[[ "$TID" =~ ^[a-z][a-z0-9-]{1,32}$ ]] || { err "task-id 须匹配 [a-z][a-z0-9-]{1,32}: $TID"; exit 1; }
[ -n "$VCMD" ] || { err "need --cmd"; exit 1; }
[[ "$RETRY" =~ ^[0-9]+$ && "$TMO_MIN" =~ ^[0-9]+$ ]] || { err "--retry/--timeout-min 须为非负整数"; exit 1; }

TD="$PWD/.parallel/$TID"
PANE=$(cat "$TD/pane" 2>/dev/null) || { err "$TD/pane 缺失(先 par-run)"; exit 2; }
[ -d "$TD/wt" ] || { err "$TD/wt 缺失(非 develop 任务?)"; exit 2; }
ATTEMPT=$(sed -n 's/^attempt=//p' "$TD/meta" 2>/dev/null); ATTEMPT=${ATTEMPT:-1}
LOG="$TD/verify.log"; : > "$LOG"

i=0
while [ "$i" -le "$RETRY" ]; do
  echo "== verify 第 $((i+1)) 轮: $VCMD" >> "$LOG"
  if ( cd "$TD/wt" 2>/dev/null && eval "$VCMD" ) >> "$LOG" 2>&1; then
    echo "PASS" >> "$LOG"; echo verified > "$TD/state"
    echo "parallel: verify $TID PASS ($TD/verify.log)"; exit 0
  fi
  echo "FAIL(第 $((i+1)) 轮)" >> "$LOG"
  i=$((i+1)); [ "$i" -gt "$RETRY" ] && break
  ATTEMPT=$((ATTEMPT+1)); sed -i "s/^attempt=.*/attempt=$ATTEMPT/" "$TD/meta"
  par_dispatch_msg "$PANE" "verify 失败(日志: $LOG)。修复后重新上报: herdr pane report-metadata \"\$HERDR_PANE_ID\" --source parallel --token \"par_result=PAR-DONE $TID#$ATTEMPT <结论>\",并终端打印同一行。" || break
  R=$(par_await_sentinel $((TMO_MIN * 60000)) "$PANE" "$TID" "$ATTEMPT")
  [ "$R" = done ] || { echo "修复轮未等到完成上报($R)" >> "$LOG"; break; }
done
echo verify-failed > "$TD/state"
err "verify $TID FAIL ($TD/verify.log)"; exit 2
