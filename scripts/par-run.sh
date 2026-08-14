#!/usr/bin/env bash
# par-run.sh — parallel 单任务派发(薄原语;拆分/判断归主 agent)
# 用法: par-run.sh <task-id> <model-cmd|@matrix/track> [--mode develop|research|review] [--brief …] [--timeout-min N] [--attempt N] [--launch-only] [--layout tab|stack]
#   model-cmd: 裸命令,或矩阵轨 @develop/a · @research/b · @review/a · @speed/flash（见 par_matrix_resolve）
#   布局: 一律 **tab**（每任务一 tab；agent 不开右侧窗格）；可 --layout stack 覆盖
#   develop: worktree + tab；research/review: 无 worktree + tab（只读）
#   --launch-only: 只 recruit+dispatch,收割归 par_finish（par-wave 用）
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/par-lib.sh"

TID=${1:?usage: par-run.sh <task-id> <model-cmd|@matrix/track> [--mode develop|research|review] …}
RAW_CMD=${2:?need <model-cmd> or @develop/a|@research/b|@review/a|…}
shift 2
MODE=research; BRIEF=""; TMO_MIN=15; ATTEMPT=1; LAUNCH_ONLY=0; LAYOUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mode)        MODE=${2:-}; shift 2 ;;
    --brief)       BRIEF=${2:-}; shift 2 ;;
    --timeout-min) TMO_MIN=${2:-15}; shift 2 ;;
    --attempt)     ATTEMPT=${2:-1}; shift 2 ;;
    --launch-only) LAUNCH_ONLY=1; shift ;;
    --layout)      LAYOUT=${2:-}; shift 2 ;;
    *) err "unknown arg: $1"; exit 1 ;;
  esac
done
[[ "$TID" =~ ^[a-z][a-z0-9-]{1,32}$ ]] || { err "task-id 须匹配 [a-z][a-z0-9-]{1,32}: $TID"; exit 1; }
[ "$MODE" = develop ] || [ "$MODE" = research ] || [ "$MODE" = review ] \
  || { err "--mode 须 develop|research|review"; exit 1; }
[[ "$TMO_MIN" =~ ^[0-9]+$ && "$ATTEMPT" =~ ^[0-9]+$ ]] || { err "--timeout-min/--attempt 须为正整数"; exit 1; }

# 布局: 默认 tab（每任务一 tab）；stack 仅显式 --layout 覆盖
LAYOUT=${LAYOUT:-tab}
[ "$LAYOUT" = tab ] || [ "$LAYOUT" = stack ] || { err "--layout 须 tab|stack"; exit 1; }

CMD=$(par_matrix_resolve "$RAW_CMD") || exit 1

TD="$PWD/.parallel/$TID"; mkdir -p "$TD"
st() { echo "$1" > "$TD/state"; }
par_preflight || exit 1
WS=$(par_ws) || exit 1

CWD=$PWD; BASE=""
if [ "$MODE" = develop ]; then
  [ -d "$TD/wt" ] || git worktree add -B "par/$TID" "$TD/wt" HEAD >/dev/null 2>&1 \
    || { st failed; err "worktree add failed: $TD/wt"; exit 2; }
  CWD="$TD/wt"; BASE=$(git -C "$CWD" rev-parse HEAD 2>/dev/null)
fi

# review/research：模板写死——首 launch 预写骨架进 artifact.md（须在基线前；
# agent 填实后文件才变，交付门禁才认；缺节 lint 见 par-lib par_delivery_met）
if [ ! -f "$TD/task.md" ]; then
  case "$MODE" in
    review)
      cat > "$TD/artifact.md" <<EOF
# review $TID#$ATTEMPT

## 结论
（通过 | 有条件通过 | 不通过——填一词 + 一句理由）

## P0
（阻断性，不修不能合；每条格式：文件:行号 — 问题 — 证据。无则写「无」）

## P1
（应修不阻断；格式同上。无则写「无」）

## 存疑
（不确定 / 需人裁。无则写「无」）

## 证据
（读过什么文件 / 跑过什么命令）
EOF
      ;;
    research)
      cat > "$TD/artifact.md" <<EOF
# research $TID#$ATTEMPT

## 结论
（结论先行：一句话 + 要点清单）

## 证据
（每条：文件:行号 或 URL —— 支撑哪条结论）

## 存疑
（不确定 / 未覆盖。无则写「无」）
EOF
      ;;
  esac
fi

# 本轮 artifact 基线：交付须在此之后新写（防旧产物假 done）
par_artifact_baseline_write "$TD"

if [ ! -f "$TD/task.md" ]; then
  CTX_BIN="$PAR_HOME/bin/par"
  DONE_CMD=$(par_token_done_cmd '${HERDR_PANE_ID}' "$TID" "$ATTEMPT" '<一句话结论>')
  BLOCKED_CMD=$(par_token_blocked_cmd '${HERDR_PANE_ID}' "$TID" "$ATTEMPT" '<原因>')
  {
    echo "# task $TID（parallel $MODE，第 $ATTEMPT 轮）"
    echo
    echo "- **Time budget**: ${TMO_MIN} 分钟硬上限"
    echo "- **Scope freeze**: 只做本任务;工作目录 \`$CWD\`"
    if [ "$MODE" = review ]; then
      echo "- **契约**: **只读审阅**（并行 review/审核）。除本任务交付外 **严禁** 改仓库/系统状态"
      echo "  **唯一允许写**: \`$TD/artifact.md\` + 最后 \`report-metadata\` 完成 token；禁其它写重定向/git 改动"
    elif [ "$MODE" = research ]; then
      echo "- **契约**: **只读探索**。除本任务交付外 **严禁** 改仓库/系统状态"
      echo "  **唯一允许写**: \`$TD/artifact.md\` + 最后 \`report-metadata\` 完成 token"
    else
      echo "- **Forbidden**: 禁止 push;禁止改本任务目录外的文件"
    fi
    echo "- **model-cmd**: \`$CMD\`（raw=$RAW_CMD layout=$LAYOUT）"
    echo "- **完成上报(必须,作为最后动作)**: 编排**只认** herdr metadata token（key=$(par_meta_key)）。最后一步必须执行:"
    echo "  \`$DONE_CMD\`"
    echo "  卡住: \`$BLOCKED_CMD\`"
    echo "  终端可打印同一行供人眼；**脚本不扫终端文本**。仅写 artifact / 仅 agent idle / 无非空结论 **不算完成**。"
    echo "- **自发现(绝对路径)**: \`bash $CTX_BIN context --json --tid $TID\`"
    if [ "$MODE" = review ]; then
      echo "- **交付(必须)**: 填实 \`$TD/artifact.md\` 预写骨架："
      echo "  结论 / P0 / P1 / 存疑 / 证据 五节标题固定（缺一不收，门禁 lint 硬卡）；P0/P1 每条 文件:行号 — 问题 — 证据"
    elif [ "$MODE" = research ]; then
      echo "- **交付(必须)**: 填实 \`$TD/artifact.md\` 预写骨架："
      echo "  结论 / 证据 / 存疑 三节标题固定（缺一不收，门禁 lint 硬卡）；证据每条 文件:行号 或 URL"
    else
      echo "- **交付(必须)**: 写非空 artifact.md 到 \`$TD/artifact.md\`(做了什么/结论/产出)"
    fi
    [ "$MODE" = develop ] && echo "  代码改动在 worktree \`$CWD\` 内 git add -A && git commit(分支 par/$TID,留给主 agent review/merge)"
    echo
    echo "## 任务"
    if [ "$MODE" = review ] && [ -z "${BRIEF:-}" ]; then
      echo "（主 agent 应预写 task.md：审阅范围/提交或 diff/验收标准）"
    else
      echo "${BRIEF:-（主 agent 应预写 task.md）}"
    fi
  } > "$TD/task.md"
fi

PANE=$(par_recruit "$WS" "$TID" "$CMD" "$CWD" "$LAYOUT") || { st failed; err "recruit 失败"; exit 2; }
echo "$PANE" > "$TD/pane"
printf 'mode=%s\ncmd=%s\nraw=%s\nlayout=%s\ncwd=%s\nattempt=%s\nbase=%s\n' \
  "$MODE" "$CMD" "$RAW_CMD" "$LAYOUT" "$CWD" "$ATTEMPT" "$BASE" > "$TD/meta"
st working

par_dispatch_msg "$PANE" "Read $TD/task.md and execute it end to end. As your LAST action, report completion per task.md: $(par_token_done_cmd '${HERDR_PANE_ID}' "$TID" "$ATTEMPT" '<结论>') (or blocked variant), and print the same line to the terminal." \
  || { st failed; err "dispatch 无回执"; exit 2; }

# dispatch 后 agent 常已 working：补刷 $dyn_title（recruit 时多为 idle）
par_refresh_dyn_title "$PANE" "$TID" || true

# --launch-only(par-wave 渐进批量用):回执成功(working/done)即返回,收割归 par_finish
if [ "$LAUNCH_ONLY" = 1 ]; then
  echo "$PANE"
  exit 0
fi

R=$(par_finish "$TID" "$TMO_MIN")
echo "parallel: task $TID -> $(cat "$TD/state") ($TD)"
[ "$(cat "$TD/state")" = done ] && exit 0 || exit 2
