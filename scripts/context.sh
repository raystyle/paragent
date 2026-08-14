#!/usr/bin/env bash
# context.sh — 子 agent 自发现：herdr+workspace 路径、任务目录、完成上报命令、端能力。
# 用法:
#   context.sh [--json] [--tid <id>] [--task-dir <path>]
#   context.sh text   # 默认可读
# 出口: 0 成功；stdout 为 JSON 或可读文本。不改系统状态。
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SELF_DIR/.." && pwd)"
PAR_ENTRY="$(cd "$SELF_DIR/.." && pwd)/bin/par"
AGENT_ENTRY="$SELF_DIR/agent.sh"
PANE_ENTRY="$SELF_DIR/pane.sh"

JSON=0
TID=""
TASK_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json|-j) JSON=1; shift ;;
    --tid)
      [ $# -ge 2 ] && [ -n "${2:-}" ] || { echo "context: --tid 需要非空参数" >&2; exit 2; }
      TID=$2; shift 2 ;;
    --task-dir)
      [ $# -ge 2 ] && [ -n "${2:-}" ] || { echo "context: --task-dir 需要非空参数" >&2; exit 2; }
      TASK_DIR=$2; shift 2 ;;
    text|human) JSON=0; shift ;;
    -h|--help|help)
      sed -n '2,8p' "$0" | sed -n '/^#/s/^# \?//p'
      exit 0
      ;;
    *)
      # 裸 tid 兼容: context.sh r-grok
      if [[ "$1" =~ ^[a-z][a-z0-9-]{1,32}$ ]] && [ -z "$TID" ]; then
        TID=$1; shift
      else
        echo "usage: context.sh [--json] [--tid <id>] [--task-dir <path>]" >&2
        exit 2
      fi
      ;;
  esac
done

# ── 解析 task 目录 ──
resolve_task_dir() {
  if [ -n "$TASK_DIR" ]; then
    [ -d "$TASK_DIR" ] || { echo "context: task-dir 不存在: $TASK_DIR" >&2; return 1; }
    printf '%s' "$TASK_DIR"
    return 0
  fi
  local root base
  root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  if [ -n "$TID" ]; then
    base="$root/.parallel/$TID"
    [ -d "$base" ] || base="$PWD/.parallel/$TID"
    [ -d "$base" ] || { echo "context: 无 .parallel/$TID" >&2; return 1; }
    printf '%s' "$base"
    return 0
  fi
  # 从 cwd 推断: …/.parallel/<tid>[/wt]
  case "$PWD" in
    */.parallel/*)
      local rel tid cand
      rel=${PWD#*/.parallel/}
      tid=${rel%%/*}
      if [[ "$tid" =~ ^[a-z][a-z0-9-]{1,32}$ ]]; then
        TID=$tid
        base="$root/.parallel/$tid"
        if [ ! -d "$base" ]; then
          cand=$(cd "$PWD" && while [ ! -f meta ] && [ "$PWD" != / ]; do cd ..; done; pwd)
          # 必须仍在 .parallel/<tid> 下且含 meta，禁止回落到 /
          if [ -f "$cand/meta" ] && [[ "$cand" == */.parallel/"$tid" ]]; then
            base=$cand
          else
            base=""
          fi
        fi
        [ -n "$base" ] && [ -d "$base" ] && { printf '%s' "$base"; return 0; }
      fi
      ;;
  esac
  # 无 task：返回空，context 仍输出环境层
  printf ''
}

# ── 端能力（静态知识 + 本机是否装了 CLI）──
# 字段: binary, prompt_flag, stdin, trust_or_skip_git, worktree_ok, notes
harness_row() {
  # name|binary|prompt_flag|stdin|trust|worktree|notes
  case "$1" in
    claude)
      echo "claude|claude|-p|ok|claude.json projects trust|yes|[1m] alias; seed trust via par_seed_trust" ;;
    codex)
      echo "codex|codex|exec|must_close|skip-git-repo-check or codex trust|yes|effort=low for flash; stdin </dev/null" ;;
    pi)
      echo "pi|pi|-p|ok|CPA|yes|no reasoning effort switch" ;;
    grok)
      echo "grok|grok|-m/-p|ok|trusted_folders.toml|yes|native CLI" ;;
    kimi)
      echo "kimi|kimi|-m/-p|ok|config|yes|keys kimi-code/<id> not bare" ;;
    *) return 1 ;;
  esac
}

harness_present() {
  command -v "$1" >/dev/null 2>&1 && echo true || echo false
}

# 轻量探测：CLI 是否能 --version/--help（2s 超时）；不调模型、不耗 token
harness_probe() {
  local bin=$1 out rc=1
  command -v "$bin" >/dev/null 2>&1 || { echo "missing"; return; }
  out=$(timeout 2s "$bin" --version 2>&1 | head -c 120 | tr '\n' ' ' || true)
  if [ -z "$out" ]; then
    out=$(timeout 2s "$bin" -V 2>&1 | head -c 120 | tr '\n' ' ' || true)
  fi
  if [ -z "$out" ]; then
    out=$(timeout 2s "$bin" --help 2>&1 | head -c 80 | tr '\n' ' ' || true)
  fi
  if [ -n "$out" ]; then
    printf 'ok:%s' "$out"
  else
    echo "present_no_version"
  fi
}

# ── 读 meta/state ──
# 显式 --tid/--task-dir 时缺目录必须失败；否则允许无 task 的环境-only context
if [ -n "$TID" ] || [ -n "$TASK_DIR" ]; then
  TD=$(resolve_task_dir) || exit 1
else
  TD=$(resolve_task_dir || true)
fi
META_MODE=""; META_CMD=""; META_RAW=""; META_LAYOUT=""; META_CWD=""; META_ATTEMPT="1"; META_BASE=""
STATE=""; PANE_ID="${HERDR_PANE_ID:-}"
if [ -n "$TD" ] && [ -d "$TD" ]; then
  [ -f "$TD/state" ] && STATE=$(cat "$TD/state" 2>/dev/null || true)
  [ -f "$TD/pane" ] && PANE_ID=$(cat "$TD/pane" 2>/dev/null || echo "$PANE_ID")
  if [ -f "$TD/meta" ]; then
    META_MODE=$(sed -n 's/^mode=//p' "$TD/meta" | head -1)
    META_CMD=$(sed -n 's/^cmd=//p' "$TD/meta" | head -1)
    META_RAW=$(sed -n 's/^raw=//p' "$TD/meta" | head -1)
    META_LAYOUT=$(sed -n 's/^layout=//p' "$TD/meta" | head -1)
    META_CWD=$(sed -n 's/^cwd=//p' "$TD/meta" | head -1)
    META_ATTEMPT=$(sed -n 's/^attempt=//p' "$TD/meta" | head -1)
    META_BASE=$(sed -n 's/^base=//p' "$TD/meta" | head -1)
    META_ATTEMPT=${META_ATTEMPT:-1}
  fi
  # 从路径回填 tid
  if [ -z "$TID" ]; then
    TID=$(basename "$TD")
  fi
fi

PANE_FOR_CMD=${PANE_ID:-'${HERDR_PANE_ID}'}
ATT=${META_ATTEMPT:-1}
DONE_CMD=""
BLOCKED_CMD=""
ARTIFACT=""
TASK_MD=""
META_SRC="${PAR_META_SOURCE:-parallel}"
META_KEY="${PAR_META_KEY:-par_result}"
if [ -n "$TID" ]; then
  DONE_CMD="herdr pane report-metadata \"$PANE_FOR_CMD\" --source $META_SRC --token \"$META_KEY=PAR-DONE ${TID}#${ATT} <一句话结论>\""
  BLOCKED_CMD="herdr pane report-metadata \"$PANE_FOR_CMD\" --source $META_SRC --token \"$META_KEY=PAR-BLOCKED ${TID}#${ATT} <原因>\""
fi
if [ -n "$TD" ]; then
  ARTIFACT="$TD/artifact.md"
  TASK_MD="$TD/task.md"
fi

WS_ID="${HERDR_WORKSPACE_ID:-}"
if [ -z "$WS_ID" ] && command -v herdr >/dev/null 2>&1 && [ "${HERDR_ENV:-}" = 1 ]; then
  WS_ID=$(herdr workspace list 2>/dev/null \
    | jq -r '(.result.workspaces[]|select(.focused==true).workspace_id)//.result.workspaces[0].workspace_id//empty' \
    | head -1) || true
  [ "$WS_ID" = null ] && WS_ID=""
fi

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)

if [ "$JSON" = 1 ]; then
  # harness object（静态契约 + present + 轻量 probe）
  H_JSON='{}'
  for name in claude codex pi grok kimi; do
    row=$(harness_row "$name")
    IFS='|' read -r _ bin prompt stdin trust wt notes <<<"$row"
    present=$(harness_present "$bin")
    probe=$(harness_probe "$bin")
    H_JSON=$(jq -cn \
      --argjson acc "$H_JSON" \
      --arg n "$name" \
      --arg bin "$bin" \
      --arg prompt "$prompt" \
      --arg stdin "$stdin" \
      --arg trust "$trust" \
      --arg wt "$wt" \
      --arg notes "$notes" \
      --arg probe "$probe" \
      --argjson present "$present" \
      '$acc + {($n): {binary:$bin, present:$present, probe:$probe, prompt_flag:$prompt, stdin:$stdin, trust_or_skip_git:$trust, worktree_ok:($wt=="yes"), notes:$notes}}')
  done

  jq -n \
    --arg skill_dir "$SKILL_DIR" \
    --arg par "$PAR_ENTRY" \
    --arg agent "$AGENT_ENTRY" \
    --arg pane "$PANE_ENTRY" \
    --arg cwd "$PWD" \
    --arg git_root "${GIT_ROOT:-}" \
    --arg herdr_env "${HERDR_ENV:-}" \
    --arg pane_id "${PANE_ID:-}" \
    --arg ws_id "${WS_ID:-}" \
    --arg tid "${TID:-}" \
    --arg task_dir "${TD:-}" \
    --arg task_md "${TASK_MD:-}" \
    --arg artifact "${ARTIFACT:-}" \
    --arg state "${STATE:-}" \
    --arg mode "${META_MODE:-}" \
    --arg cmd "${META_CMD:-}" \
    --arg raw "${META_RAW:-}" \
    --arg layout "${META_LAYOUT:-}" \
    --arg task_cwd "${META_CWD:-}" \
    --arg attempt "${ATT}" \
    --arg done_cmd "${DONE_CMD}" \
    --arg blocked_cmd "${BLOCKED_CMD}" \
    --arg meta_src "$META_SRC" \
    --arg meta_key "$META_KEY" \
    --argjson harness "$H_JSON" \
    '{
      layers: {
        herdr: "runtime: pane/session/agent primitives",
        workspace: "routing skill + par/pane/agent scripts (this skill)",
        center: "mesh/token/SSH certs — not this skill"
      },
      selling_points: ["matrix model-cmd tracks", "par_result metadata token completion"],
      env: {
        cwd: $cwd,
        git_root: $git_root,
        HERDR_ENV: $herdr_env,
        HERDR_PANE_ID: $pane_id,
        HERDR_WORKSPACE_ID: $ws_id
      },
      skill: {
        dir: $skill_dir,
        par: $par,
        agent: $agent,
        pane: $pane
      },
      task: (if $tid == "" then null else {
        id: $tid,
        dir: $task_dir,
        task_md: $task_md,
        artifact: $artifact,
        state: $state,
        mode: $mode,
        model_cmd: $cmd,
        raw: $raw,
        layout: $layout,
        cwd: $task_cwd,
        attempt: $attempt
      } end),
      completion: (if $tid == "" then null else {
        truth: "herdr pane report-metadata token only; idle/artifact alone is not done",
        done: $done_cmd,
        blocked: $blocked_cmd
      } end),
      entries: {
        par: "par wave|run|ix|triad|context|close-tasks|verify|merge|discard|gate|smoke|nightly",
        agent: "agent.sh ensure|check|test|context|harness",
        pane: "pane.sh dir|file|code|run|close|…"
      },
      token: { source: $meta_src, key: $meta_key },
      harness: $harness
    }'
  exit 0
fi

# ── 可读文本 ──
cat <<EOF
# workspace context

## 三层
- herdr     = runtime（pane/session/agent 原语）
- workspace = 本 skill（routing + par/pane/agent 脚本）
- center    = mesh/token/SSH 证（不在本 skill 签发）

卖点: 矩阵轨 model-cmd + par_result metadata token 完成真源（不是又一个 TUI）。

## 环境
- cwd:              $PWD
- git_root:         ${GIT_ROOT:-(none)}
- HERDR_ENV:        ${HERDR_ENV:-(unset)}
- HERDR_PANE_ID:    ${PANE_ID:-(unset)}
- HERDR_WORKSPACE_ID: ${WS_ID:-(unset)}
- skill_dir:        $SKILL_DIR

## 入口
- par:   $PAR_ENTRY  (wave|run|verify|merge|context|test|help)
- agent: $AGENT_ENTRY (ensure|check|test|context|harness)
- pane:  $PANE_ENTRY
EOF

if [ -n "$TID" ]; then
  cat <<EOF

## 当前任务 ($TID)
- dir:       ${TD:-?}
- state:     ${STATE:-(none)}
- mode:      ${META_MODE:-(none)}
- model-cmd: ${META_CMD:-(none)}
- layout:    ${META_LAYOUT:-(none)}
- task.md:   ${TASK_MD:-}
- artifact:  ${ARTIFACT:-}  (必须非空交付)
- attempt:   $ATT

## 完成上报（必须最后执行；只认 token）
done:
  $DONE_CMD
blocked:
  $BLOCKED_CMD
EOF
else
  cat <<EOF

## 当前任务
(未指定 --tid / 不在 .parallel/<tid> 下。可用: context.sh --tid <id> 或 --json)
EOF
fi

echo
echo "## 端能力（present + probe；契约见 models.md）"
printf '%-8s %-8s %-10s %-12s %s\n' "end" "present" "prompt" "stdin" "probe"
for name in claude codex pi grok kimi; do
  row=$(harness_row "$name")
  IFS='|' read -r _ bin prompt stdin trust wt notes <<<"$row"
  present=$(harness_present "$bin")
  probe=$(harness_probe "$bin")
  printf '%-8s %-8s %-10s %-12s %s\n' "$name" "$present" "$prompt" "$stdin" "${probe:0:40}"
done
echo
echo "CONTEXT-PASS"
