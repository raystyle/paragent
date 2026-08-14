#!/usr/bin/env bash
# par-triad.sh — 三席原语（chief 首席 + a/b 双席 · 状态驱动互话 · 主控零轮询）
# 用法:
#   par-triad.sh open [--mode research|review|discuss] [--chief|--a|--b <轨|cmd>] [--cwd DIR] [--force]
#   par-triad.sh fire "<题>"        # 只 prompt 首席，火即返（禁 --wait）
#   par-triad.sh take [chief|a|b|--all] [--read] [--json]   # 非阻塞收割；rc0 有货/rc3 无/rc2 无 session
#   par-triad.sh collect [...]      # 编排糖 = wait→take（人类兜底；主路径靠席位回注）
#   par-triad.sh status|poll [--json]
#   par-triad.sh wait [chief|a|b|--any|--all] [--timeout-ms N]
#   par-triad.sh relay <triad-chief|triad-a|triad-b> "<msg>"  # 席位回话闸控通道（状态闸/上限/隔离）
#   par-triad.sh close
#
# 形态：人类主窗不动；右 stack 三席 triad-chief（上）/ triad-a（中）/ triad-b（下）。
# 控制流：fire→首席拆题派发→席位报 token + 看状态互注回话（闸门 idle|done|blocked，上限 1 轮）。
# 完成真源：tokens.par_result 锚定 triad-<role>#<首席 attempt>；协议正本 references/triad-mode.md。
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/par-lib.sh"

# 交互形态硬规则：任何路径都不得自动关窗（与 discuss 同）
export PAR_CLOSE_PANE=0

TRIAD_ROOT="${PAR_TRIAD_DIR:-$PWD/.parallel/triad}"
DEFAULT_CHIEF="@develop/a"      # k3@kimi
DEFAULT_A="@review/a"       # opus@claude
DEFAULT_B="@review/b"       # gpt@codex
MODE=discuss                # open --mode 覆盖；fire 读 session

usage() {
  sed -n '2,16p' "$0" | sed -n '/^#/s/^# \?//p'
  exit 2
}

# 槽位 → 角色 chief|a|b|all|any
_triad_slot() {
  case "$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')" in
    chief|c|lead|triad-chief) echo chief ;;
    a|alpha|triad-a)          echo a ;;
    b|beta|triad-b)           echo b ;;
    all) echo all ;;
    any|first|"") echo any ;;
    *) err "槽位须 chief|a|b|any|all（got: $1）"; return 1 ;;
  esac
}

_triad_is_ready() {
  case "$1" in
    idle|done|blocked) return 0 ;;
    *) return 1 ;;
  esac
}

_triad_agent_status() {
  local pane=$1
  [ -n "$pane" ] || { echo missing; return; }
  herdr agent get "$pane" 2>/dev/null | jq -r '.result.agent.agent_status // "missing"' 2>/dev/null || echo missing
}

_triad_label() { printf 'triad-%s' "$1"; }
_triad_tid()   { printf 'triad-%s' "$1"; }
_triad_dir() {
  case "$1" in
    chief|a|b) echo "$TRIAD_ROOT/$1" ;;
    *) return 1 ;;
  esac
}

# ── round（防「派发前 idle」误收；完成真源 = par_result 锚定 tid#attempt）──
# $d/round: pending · busy_seen · harvestable · tid · attempt
# 席位（a/b）不由脚本 fire：pending 恒 0，take 闸 = token 锚 triad-<role>#<首席 attempt>
_triad_round_file() { printf '%s/round' "$(_triad_dir "$1")"; }

_triad_round_write() {
  local role=$1 pending=${2:-0} busy=${3:-0} harv=${4:-0}
  local tid=${5:-} att=${6:-} f cur_t cur_a
  f=$(_triad_round_file "$role") || return 1
  mkdir -p "$(dirname "$f")"
  if [ -z "$tid" ] || [ -z "$att" ]; then
    cur_t=$(sed -n 's/^tid=//p' "$f" 2>/dev/null | head -1)
    cur_a=$(sed -n 's/^attempt=//p' "$f" 2>/dev/null | head -1)
    tid=${tid:-${cur_t:-$(_triad_tid "$role")}}
    att=${att:-${cur_a:-0}}
  fi
  printf 'pending=%s\nbusy_seen=%s\nharvestable=%s\ntid=%s\nattempt=%s\n' \
    "$pending" "$busy" "$harv" "$tid" "$att" > "$f"
}

_triad_round_read() {
  # stdout: pending busy_seen harvestable tid attempt
  local f pending=0 busy=0 harv=0 tid="" att=0
  f=$(_triad_round_file "$1") || { echo "0 0 0  0"; return; }
  if [ -f "$f" ]; then
    pending=$(sed -n 's/^pending=//p' "$f" | head -1)
    busy=$(sed -n 's/^busy_seen=//p' "$f" | head -1)
    harv=$(sed -n 's/^harvestable=//p' "$f" | head -1)
    tid=$(sed -n 's/^tid=//p' "$f" | head -1)
    att=$(sed -n 's/^attempt=//p' "$f" | head -1)
  fi
  printf '%s %s %s %s %s\n' "${pending:-0}" "${busy:-0}" "${harv:-0}" "${tid:-}" "${att:-0}"
}

_triad_next_attempt() {
  local att
  att=$(sed -n 's/^attempt=//p' "$(_triad_round_file "$1")" 2>/dev/null | head -1)
  echo $(( ${att:-0} + 1 ))
}

# 首席 attempt = 全局轮次号（席位 token 锚同号）
_triad_chief_attempt() {
  local _p _b _h _t att
  read -r _p _b _h _t att < <(_triad_round_read chief)
  echo "${att:-0}"
}

# fire：首席 pending + 新 attempt；清首席旧 token 防串台
_triad_round_mark_prompt() {
  local role=$1 pane=$2 tid att
  tid=$(_triad_tid "$role")
  att=$(_triad_next_attempt "$role")
  [ -n "$pane" ] && par_clear_result_token "$pane"
  _triad_round_write "$role" 1 0 0 "$tid" "$att"
  printf '%s %s\n' "$tid" "$att"
}

_triad_round_clear() { _triad_round_write "$1" 0 0 0; }

# fire 新轮：清三席 replied-* 标记（回话额度随 attempt 重置）
_triad_replied_reset() {
  local role d
  for role in chief a b; do
    d=$(_triad_dir "$role") || continue
    rm -f "$d"/replied-* 2>/dev/null || true
  done
}

# token 闸：done|blocked|waiting
# 首席用自身 round 锚；席位用 自身 tid + 首席当前 attempt
_triad_token_gate() {
  local role=$1 pane=$2 pending busy harv tid att
  [ -n "$pane" ] || { echo waiting; return; }
  if [ "$role" = chief ]; then
    read -r pending busy harv tid att < <(_triad_round_read chief)
    [ -n "$tid" ] && [ "${att:-0}" -ge 1 ] 2>/dev/null || { echo waiting; return; }
  else
    tid=$(_triad_tid "$role")
    att=$(_triad_chief_attempt)
    [ "${att:-0}" -ge 1 ] 2>/dev/null || { echo waiting; return; }
  fi
  _par_report_token "$pane" "$tid" "$att"
}

_triad_try_harvest_from_token() {
  local role=$1 pane=$2 gate
  gate=$(_triad_token_gate "$role" "$pane")
  case "$gate" in
    done|blocked)
      _triad_round_write "$role" 0 0 1
      return 0 ;;
  esac
  return 1
}

# status/poll 展示用
_triad_round_ready() {
  local role=$1 st=$2 pane=$3 pending busy harv tid att
  read -r pending busy harv tid att < <(_triad_round_read "$role")
  if [ "$pending" = 1 ]; then
    case "$st" in
      working)
        _triad_round_write "$role" 1 1 0
        return 1 ;;
      done|blocked|idle)
        [ "$st" = idle ] && [ "$busy" != 1 ] && return 1
        [ "$st" = idle ] && _triad_round_write "$role" 1 1 0
        if [ -n "$pane" ] && _triad_try_harvest_from_token "$role" "$pane"; then
          return 0
        fi
        return 1 ;;
      *) return 1 ;;
    esac
  fi
  if [ "$harv" = 1 ]; then
    [ -n "$pane" ] || return 0
    case "$(_triad_token_gate "$role" "$pane")" in done|blocked) return 0 ;; *) return 1 ;; esac
  fi
  # 席位（无 pending）：token 锚本轮即可 READY；首席未 fire 时 idle 可先看
  if [ "$role" != chief ] && [ -n "$pane" ]; then
    case "$(_triad_token_gate "$role" "$pane")" in done|blocked) return 0 ;; esac
  fi
  _triad_is_ready "$st"
  return $?
}

# take 专用：仅 token 过闸（锚定 tid#attempt 已防半回合误收；
# 席位报完 token 后进 peer 阶段仍 working，不得按状态拒收）
_triad_round_takeable() {
  local role=$1 st=$2 pane=$3 pending busy harv tid att
  _triad_round_ready "$role" "$st" "$pane" >/dev/null 2>&1 || true
  read -r pending busy harv tid att < <(_triad_round_read "$role")
  if [ "$harv" = 1 ]; then
    case "$(_triad_token_gate "$role" "$pane")" in
      done|blocked) return 0 ;;
      *) _triad_round_write "$role" 0 0 0; return 1 ;;
    esac
  fi
  # 席位无 pending 状态机：直接验 token
  if [ "$role" != chief ] && [ -n "$pane" ]; then
    case "$(_triad_token_gate "$role" "$pane")" in
      done|blocked) _triad_round_write "$role" 0 0 1; return 0 ;;
    esac
  fi
  return 1
}

_triad_round_took() {
  local role=$1 pane=$2
  _triad_round_write "$role" 0 0 0
  [ -n "$pane" ] && par_clear_result_token "$pane"
}

_triad_round_complete() {
  local role=$1 pane=$2
  _triad_round_write "$role" 1 1 0
  _triad_try_harvest_from_token "$role" "$pane" || true
}

# prompt 后短等 busy（不堵死异步；不据此 harvest）
_triad_arm_after_prompt() {
  local role=$1 pane=$2 st i max="${PAR_TRIAD_ARM_MS:-2000}" step=100 n
  n=$((max / step)); [ "$n" -lt 1 ] && n=1
  for i in $(seq 1 "$n"); do
    st=$(_triad_agent_status "$pane")
    case "$st" in
      working|done|blocked)
        _triad_round_write "$role" 1 1 0
        _triad_try_harvest_from_token "$role" "$pane" || true
        return 0 ;;
    esac
    sleep 0.1
  done
  return 0
}

_triad_pane_alive() {
  local pane=$1 st
  [ -n "$pane" ] || return 1
  st=$(herdr agent get "$pane" 2>/dev/null | jq -r '.result.agent.agent_status // empty' 2>/dev/null) || return 1
  [ -n "$st" ] && [ "$st" != null ]
}

_triad_read_pane() { cat "$(_triad_dir "$1")/pane" 2>/dev/null || true; }

_triad_write_side() {
  local role=$1 pane=$2 cmd=$3 d
  d=$(_triad_dir "$role") || return 1
  mkdir -p "$d"
  printf '%s\n' "$pane" > "$d/pane"
  printf 'mode=triad\ntriad_mode=%s\nlayout=stack\nrole=%s\ncmd=%s\nlabel=%s\ncwd=%s\n' \
    "$MODE" "$role" "$cmd" "$(_triad_label "$role")" "${CWD:-$PWD}" > "$d/meta"
  echo working > "$d/state"
}

_triad_write_session() {
  mkdir -p "$TRIAD_ROOT"
  {
    echo "mode=triad"
    echo "triad_mode=$MODE"
    echo "layout=stack"
    echo "chief_pane=${CHIEF_PANE:-}"
    echo "a_pane=${A_PANE:-}"
    echo "b_pane=${B_PANE:-}"
    echo "chief_cmd=${CHIEF_CMD:-}"
    echo "a_cmd=${A_CMD:-}"
    echo "b_cmd=${B_CMD:-}"
    echo "cwd=${CWD:-$PWD}"
    echo "opened_at=$(date -Iseconds 2>/dev/null || date)"
  } > "$TRIAD_ROOT/session"
}

_triad_load_session() {
  CHIEF_PANE=$(_triad_read_pane chief)
  A_PANE=$(_triad_read_pane a)
  B_PANE=$(_triad_read_pane b)
  if [ -f "$TRIAD_ROOT/session" ]; then
    CHIEF_CMD=$(sed -n 's/^chief_cmd=//p' "$TRIAD_ROOT/session" | head -1)
    A_CMD=$(sed -n 's/^a_cmd=//p' "$TRIAD_ROOT/session" | head -1)
    B_CMD=$(sed -n 's/^b_cmd=//p' "$TRIAD_ROOT/session" | head -1)
    MODE=$(sed -n 's/^triad_mode=//p' "$TRIAD_ROOT/session" | head -1)
    CWD=$(sed -n 's/^cwd=//p' "$TRIAD_ROOT/session" | head -1)
  fi
  CHIEF_CMD=${CHIEF_CMD:-}; A_CMD=${A_CMD:-}; B_CMD=${B_CMD:-}
  MODE=${MODE:-discuss}; CWD=${CWD:-$PWD}
}

_triad_pane_of() {
  case "$1" in
    chief) echo "${CHIEF_PANE:-}" ;;
    a)     echo "${A_PANE:-}" ;;
    b)     echo "${B_PANE:-}" ;;
  esac
}

# ── mode brief（正本 references/triad-mode.md；此处为注入用紧凑版）──
_triad_mode_brief() {
  case "${1:-$MODE}" in
    research) printf 'mode=research 并行研究/分析：拆 2 路只读探索子题；席位禁写仓库，产出=结论+artifact 路径。' ;;
    review)   printf 'mode=review 并行 review/审核：双席交叉审同一对象；a 找正确性问题，b 找设计/边界问题；席位互审对方结论后再定稿。' ;;
    discuss)  printf 'mode=discuss 并行合作/交流：自由议题，双席各抒后互评，首席汇总。' ;;
    *)        printf 'mode=discuss 并行合作/交流。' ;;
  esac
}

# 席位协议模板（chief 原样转交给 a/b；role/att 运行时替换）
_triad_seat_protocol() {
  local role=$1 att=$2 peer self_bin
  case "$role" in a) peer=b ;; b) peer=a ;; esac
  self_bin=$(readlink -f "${BASH_SOURCE[0]}")
  cat <<EOF

【席位协议 · 必须遵守 · 你是 triad-$role · 本轮锚 triad-$role#$att】
1. 开工先清旧 token：
   herdr pane report-metadata "\$HERDR_PANE_ID" --source parallel --clear-token par_result
2. 做题（只读纪律见上）。长结论落文件 .parallel/triad/$role/artifact-$att.md，正文只回路径。
3. 【完成上报·必须】最后动作：
   herdr pane report-metadata "\$HERDR_PANE_ID" --source parallel \
     --token "par_result=PAR-DONE triad-$role#$att <一句话结论>"
   卡住则 PAR-BLOCKED triad-$role#$att <原因>。
4. peer 阶段（报完 token 后执行，不是轮询）：
   herdr agent wait triad-$peer --until idle --until done --until blocked --timeout 120000
   然后 herdr agent get triad-$peer 取 pane_id → herdr pane get <pane_id> 读 tokens.par_result。
   有异议/补充才回话；无则停。
5. 回话一律走 relay（脚本闸控：状态闸门/回话上限/主窗隔离，代码强制）：
   "$self_bin" relay triad-$peer "<回话>"      # 异议/质疑 → 对方席（让对方答辩）
   "$self_bin" relay triad-chief "<回话>"      # 定论/汇总 → 首席
   被拦：rc5=目标忙（先 agent wait 再 relay）；rc7=本轮回话额度已用完（上限 1 次/轮）→ 即停；
   rc4=目标非法（只许 triad-chief/triad-a/triad-b）。禁止用 raw herdr agent prompt 绕过 relay。
6. 隔离：禁止向 triad-chief / triad-a / triad-b 以外的窗格注入（relay 代码拦截；人类主窗隔离）。
EOF
}

# 首席协议（fire 时随题注入）
_triad_chief_protocol() {
  local att=$1 brief seat_a seat_b
  brief=$(_triad_mode_brief)
  seat_a=$(_triad_seat_protocol a "$att")
  seat_b=$(_triad_seat_protocol b "$att")
  cat <<EOF

【triad 协作协议 · 你是首席 triad-chief · 本轮 #$att】$brief
1. 【完成上报·必须·最后动作】综合定论后（编排只认 tokens.par_result 锚定 triad-chief#$att + 非空结论）：
   herdr pane report-metadata "\$HERDR_PANE_ID" --source parallel \
     --token "par_result=PAR-DONE triad-chief#$att <一句话结论>"
   卡住则 PAR-BLOCKED triad-chief#$att <原因>。
2. 立刻拆题派发，禁止等待/轮询席位状态（不 agent wait、不 collect）：
   herdr agent prompt triad-a "<子题A>$seat_a"
   herdr agent prompt triad-b "<子题B>$seat_b"
3. 派发即返。席位完成后会按状态闸门回注入你；被唤醒后再综合。
4. 人类可能同窗插话干预，人类输入优先。
EOF
}

_triad_print_usage() {
  cat <<EOF
parallel: triad ready（三席 · 状态驱动互话 · 主控零轮询）
  主窗      （人类自定，不代开）
  右上 chief pane=${CHIEF_PANE}  cmd=${CHIEF_CMD}
  右中 a     pane=${A_PANE}  cmd=${A_CMD}
  右下 b     pane=${B_PANE}  cmd=${B_CMD}
  mode=${MODE}  session $TRIAD_ROOT/session

节奏:
  par.sh triad fire "题目"          # 只派首席；席位由首席派发、互看状态回话
  par.sh triad take --all --read    # 非阻塞收割（rc3=无本轮 token）
  par.sh triad collect --all --read # 人类兜底：wait→take
  par.sh triad close
EOF
}

cmd_open() {
  local force=0 mode_explicit=0 raw_chief="$DEFAULT_CHIEF" raw_a="$DEFAULT_A" raw_b="$DEFAULT_B"
  CWD=$PWD
  while [ $# -gt 0 ]; do
    case "$1" in
      --mode)   [ -n "${2:-}" ] || { err "--mode 需要 research|review|discuss"; exit 1; }
        MODE=$2; mode_explicit=1; shift 2 ;;
      --chief)  [ -n "${2:-}" ] || { err "--chief 需要 <轨|cmd>"; exit 1; }
        raw_chief=$2; shift 2 ;;
      --a)      [ -n "${2:-}" ] || { err "--a 需要 <轨|cmd>"; exit 1; }
        raw_a=$2; shift 2 ;;
      --b)      [ -n "${2:-}" ] || { err "--b 需要 <轨|cmd>"; exit 1; }
        raw_b=$2; shift 2 ;;
      --cwd)    [ -n "${2:-}" ] || { err "--cwd 需要目录"; exit 1; }
        CWD=$2; shift 2 ;;
      --force)  force=1; shift ;;
      -h|--help) usage ;;
      *) err "unknown arg: $1"; exit 1 ;;
    esac
  done
  # 未显式 --mode：沿用既有 session 的 triad_mode（幂等重开不覆盖）
  if [ "$mode_explicit" != 1 ] && [ -f "$TRIAD_ROOT/session" ]; then
    MODE=$(sed -n 's/^triad_mode=//p' "$TRIAD_ROOT/session" | head -1)
    MODE=${MODE:-discuss}
  fi
  case "$MODE" in research|review|discuss) ;; *) err "--mode 须 research|review|discuss（got: $MODE）"; exit 1 ;; esac
  [ -d "$CWD" ] || { err "cwd 不存在: $CWD"; exit 1; }
  CWD=$(cd "$CWD" && pwd -P)
  par_preflight || exit 1
  WS=$(par_ws) || exit 1

  CHIEF_CMD=$(par_matrix_resolve "$raw_chief") || exit 1
  A_CMD=$(par_matrix_resolve "$raw_a") || exit 1
  B_CMD=$(par_matrix_resolve "$raw_b") || exit 1

  # 幂等：三席存活且非 --force → 复用
  local old_chief old_a old_b
  old_chief=$(_triad_read_pane chief)
  old_a=$(_triad_read_pane a)
  old_b=$(_triad_read_pane b)
  if [ "$force" != 1 ] && _triad_pane_alive "$old_chief" \
     && _triad_pane_alive "$old_a" && _triad_pane_alive "$old_b"; then
    CHIEF_PANE=$old_chief; A_PANE=$old_a; B_PANE=$old_b
    _triad_write_side chief "$CHIEF_PANE" "$CHIEF_CMD"
    _triad_write_side a "$A_PANE" "$A_CMD"
    _triad_write_side b "$B_PANE" "$B_CMD"
    _triad_round_clear chief; _triad_round_clear a; _triad_round_clear b
    _triad_write_session
    echo "parallel: triad reuse chief=$CHIEF_PANE a=$A_PANE b=$B_PANE"
    _triad_print_usage
    return 0
  fi

  # 强制重开：先关本模式登记的旧窗
  if [ "$force" = 1 ]; then
    local p
    for p in "$old_chief" "$old_a" "$old_b"; do
      [ -n "$p" ] && herdr pane close "$p" >/dev/null 2>&1 || true
    done
  fi

  # 串行 recruit：右柱 stack（right → down），chief 在上
  CHIEF_PANE=$(par_recruit "$WS" "triad-chief" "$CHIEF_CMD" "$CWD" stack) \
    || { err "triad chief recruit 失败"; exit 2; }
  _triad_write_side chief "$CHIEF_PANE" "$CHIEF_CMD"
  echo "parallel: triad opened chief pane=$CHIEF_PANE cmd=$CHIEF_CMD"

  A_PANE=$(par_recruit "$WS" "triad-a" "$A_CMD" "$CWD" stack) \
    || { err "triad a recruit 失败（chief=$CHIEF_PANE 仍保留）"; exit 2; }
  _triad_write_side a "$A_PANE" "$A_CMD"
  echo "parallel: triad opened a pane=$A_PANE cmd=$A_CMD"

  B_PANE=$(par_recruit "$WS" "triad-b" "$B_CMD" "$CWD" stack) \
    || { err "triad b recruit 失败（chief=$CHIEF_PANE a=$A_PANE 仍保留）"; exit 2; }
  _triad_write_side b "$B_PANE" "$B_CMD"
  echo "parallel: triad opened b pane=$B_PANE cmd=$B_CMD"

  _triad_round_clear chief; _triad_round_clear a; _triad_round_clear b
  _triad_write_session
  _triad_print_usage
}

cmd_status() {
  local json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json|-j) json=1; shift ;;
      *) err "unknown arg: $1"; exit 1 ;;
    esac
  done
  _triad_load_session
  local st_chief st_a st_b rc=false ra=false rb=false
  st_chief=$(_triad_agent_status "${CHIEF_PANE:-}")
  st_a=$(_triad_agent_status "${A_PANE:-}")
  st_b=$(_triad_agent_status "${B_PANE:-}")
  _triad_round_ready chief "$st_chief" "${CHIEF_PANE:-}" && rc=true
  _triad_round_ready a "$st_a" "${A_PANE:-}" && ra=true
  _triad_round_ready b "$st_b" "${B_PANE:-}" && rb=true
  if [ "$json" = 1 ]; then
    jq -n \
      --arg mode triad --arg triad_mode "$MODE" --arg layout stack --arg pace peer-driven \
      --arg cp "${CHIEF_PANE:-}" --arg ap "${A_PANE:-}" --arg bp "${B_PANE:-}" \
      --arg cc "${CHIEF_CMD:-}" --arg ac "${A_CMD:-}" --arg bc "${B_CMD:-}" \
      --arg cs "$st_chief" --arg as "$st_a" --arg bs "$st_b" \
      --arg cwd "${CWD:-$PWD}" \
      --argjson rc "$rc" --argjson ra "$ra" --argjson rb "$rb" \
      '{mode:$mode,triad_mode:$triad_mode,layout:$layout,pace:$pace,cwd:$cwd,
        chief:{slot:"chief",pane:$cp,cmd:$cc,status:$cs,ready:$rc},
        a:{slot:"a",pane:$ap,cmd:$ac,status:$as,ready:$ra},
        b:{slot:"b",pane:$bp,cmd:$bc,status:$bs,ready:$rb}}'
    return 0
  fi
  echo "parallel: triad status (peer-driven；take 以 par_result 为准；urgency 序)"
  {
    printf '%s\t  chief  pane=%s  status=%s  %s  cmd=%s\n' \
      "$(par_status_urgency "$st_chief")" \
      "${CHIEF_PANE:-?}" "$st_chief" "$([ "$rc" = true ] && echo READY || echo busy)" "${CHIEF_CMD:-?}"
    printf '%s\t  a      pane=%s  status=%s  %s  cmd=%s\n' \
      "$(par_status_urgency "$st_a")" \
      "${A_PANE:-?}" "$st_a" "$([ "$ra" = true ] && echo READY || echo busy)" "${A_CMD:-?}"
    printf '%s\t  b      pane=%s  status=%s  %s  cmd=%s\n' \
      "$(par_status_urgency "$st_b")" \
      "${B_PANE:-?}" "$st_b" "$([ "$rb" = true ] && echo READY || echo busy)" "${B_CMD:-?}"
  } | sort -n -k1,1 | cut -f2-
  echo "  pace=peer-driven  完成真源=tokens.par_result（triad-<role>#<chief-attempt>）"
}

# 令1：fire = 只派首席，火即返（永不阻塞；无 --wait）
cmd_fire() {
  local msg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --wait) err "fire 禁止 --wait（收割用 take/collect）；已忽略"; shift ;;
      --) shift; msg="${msg:+$msg }$*"; break ;;
      -*) err "unknown arg: $1"; exit 1 ;;
      *) msg="${msg:+$msg }$1"; shift ;;
    esac
  done
  msg=$(printf '%s' "$msg" | sed 's/^ //')
  [ -n "$msg" ] || { err "fire 消息为空"; exit 1; }
  _triad_load_session
  [ -n "${CHIEF_PANE:-}" ] || { err "无 triad session（先 par.sh triad open）"; exit 2; }
  local tid att
  read -r tid att < <(_triad_round_mark_prompt chief "$CHIEF_PANE")
  _triad_replied_reset
  msg=$(printf '%s%s' "$msg" "$(_triad_chief_protocol "$att")")
  herdr agent prompt "$CHIEF_PANE" "$msg" >/dev/null 2>&1 \
    || { err "fire chief 失败 pane=$CHIEF_PANE"; exit 2; }
  _triad_arm_after_prompt chief "$CHIEF_PANE"
  echo "parallel: triad fire chief pane=$CHIEF_PANE tid=$tid#$att mode=$MODE (async)"
}

# 令2：take = 只收割已 READY（非阻塞）
# rc0=有收成 · rc3=全 busy · rc2=无 session
cmd_take() {
  local want=first do_read=0 json=0 slot="" role
  while [ $# -gt 0 ]; do
    case "$1" in
      --all|all) want=all; shift ;;
      --read|-r) do_read=1; shift ;;
      --json|-j) json=1; shift ;;
      --first|first|any) want=first; shift ;;
      -*) err "unknown arg: $1"; exit 1 ;;
      *)
        slot=$1; shift
        role=$(_triad_slot "$slot") || exit 1
        case "$role" in
          chief|a|b) want="slot:$role" ;;
          any) want=first ;;
          all) want=all ;;
          *) err "take 槽位须 chief|a|b|all"; exit 1 ;;
        esac ;;
    esac
  done
  _triad_load_session
  [ -n "${CHIEF_PANE:-}" ] || [ -n "${A_PANE:-}" ] || [ -n "${B_PANE:-}" ] \
    || { err "无 triad session（先 open）"; exit 2; }

  local st_chief st_a st_b tc=false ta=false tb=false
  st_chief=$(_triad_agent_status "${CHIEF_PANE:-}")
  st_a=$(_triad_agent_status "${A_PANE:-}")
  st_b=$(_triad_agent_status "${B_PANE:-}")
  _triad_round_takeable chief "$st_chief" "${CHIEF_PANE:-}" && tc=true
  _triad_round_takeable a "$st_a" "${A_PANE:-}" && ta=true
  _triad_round_takeable b "$st_b" "${B_PANE:-}" && tb=true

  local -a sel_name=() sel_pane=() sel_st=() sel_role=()
  _triad_sel_push() { sel_name+=("$1"); sel_pane+=("$2"); sel_st+=("$3"); sel_role+=("$4"); }
  case "$want" in
    first)
      if [ "$tc" = true ]; then _triad_sel_push chief "$CHIEF_PANE" "$st_chief" chief
      elif [ "$ta" = true ]; then _triad_sel_push a "$A_PANE" "$st_a" a
      elif [ "$tb" = true ]; then _triad_sel_push b "$B_PANE" "$st_b" b
      fi ;;
    all)
      [ "$tc" = true ] && _triad_sel_push chief "$CHIEF_PANE" "$st_chief" chief
      [ "$ta" = true ] && _triad_sel_push a "$A_PANE" "$st_a" a
      [ "$tb" = true ] && _triad_sel_push b "$B_PANE" "$st_b" b
      ;;
    slot:chief) [ "$tc" = true ] && _triad_sel_push chief "$CHIEF_PANE" "$st_chief" chief ;;
    slot:a)     [ "$ta" = true ] && _triad_sel_push a "$A_PANE" "$st_a" a ;;
    slot:b)     [ "$tb" = true ] && _triad_sel_push b "$B_PANE" "$st_b" b ;;
  esac

  local n=${#sel_name[@]}
  if [ "$json" = 1 ]; then
    local i items='[]' tok
    for i in "${!sel_name[@]}"; do
      tok=$(_par_raw_token "${sel_pane[$i]}")
      items=$(jq -c --argjson acc "$items" --arg r "${sel_name[$i]}" \
        --arg p "${sel_pane[$i]}" --arg st "${sel_st[$i]}" --arg tok "$tok" \
        '$acc + [{role:$r,pane:$p,status:$st,par_result:$tok}]')
    done
    jq -n --argjson took "$items" --argjson n "$n" '{took_count:$n, took:$took}'
  else
    local i tok
    for i in "${!sel_name[@]}"; do
      tok=$(_par_raw_token "${sel_pane[$i]}")
      echo "parallel: triad take ${sel_name[$i]} pane=${sel_pane[$i]} status=${sel_st[$i]}"
      [ -n "$tok" ] && echo "  par_result: $tok"
      if [ "$do_read" = 1 ] && [ -n "${sel_pane[$i]}" ]; then
        echo "----- read ${sel_pane[$i]} （佐证；完成真源=par_result）-----"
        herdr pane read "${sel_pane[$i]}" --source recent 2>/dev/null \
          | tr -d '\000' | sed 's/\x1b\[[0-9;]*m//g' | tail -c 12000 || true
        echo "----- end ${sel_pane[$i]} -----"
      fi
    done
    if [ "$n" -ge 1 ]; then
      echo "parallel: triad take done count=$n"
    else
      echo "parallel: triad take none (无本轮 par_result) — 可 fire 或稍后再 take"
    fi
  fi
  # 轮次归档（token 结论落盘，再清 token）
  for i in "${!sel_role[@]}"; do
    _triad_archive_take "${sel_role[$i]}" "${sel_pane[$i]}"
    _triad_round_took "${sel_role[$i]}" "${sel_pane[$i]}"
  done
  [ "$n" -ge 1 ] && return 0
  return 3
}

# 归档 .parallel/triad/<role>/archive/<attempt>-<ts>.md（PAR_TRIAD_ARCHIVE=0 关闭）
_triad_archive_take() {
  local role=$1 pane=$2
  [ "${PAR_TRIAD_ARCHIVE:-1}" = "0" ] && return 0
  local d pending busy harv tid att tok f ts
  d=$(_triad_dir "$role") || return 0
  read -r pending busy harv tid att < <(_triad_round_read "$role")
  # 席位 round 无自身 attempt（脚本不直派席位）：归档锚首席轮次号
  [ "$role" != chief ] && att=$(_triad_chief_attempt)
  tok=$(_par_raw_token "$pane")
  [ -n "$tok" ] || return 0
  mkdir -p "$d/archive"
  ts=$(date +%Y%m%dT%H%M%S 2>/dev/null || date +%s)
  f="$d/archive/${att:-0}-${ts}.md"
  {
    echo "# triad take archive"
    echo
    echo "- role: $role"
    echo "- pane: $pane"
    echo "- tid: $tid"
    echo "- attempt: $att"
    echo "- at: $(date -Iseconds 2>/dev/null || date)"
    echo "- par_result: \`$tok\`"
  } > "$f"
  echo "parallel: triad archive $f"
}

cmd_wait() {
  # 默认 --any：先到先看。all 仅显式齐等。
  local mode=any tmo="${PAR_TRIAD_WAIT_TIMEOUT_MS:-600000}" slot=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --any|any|first) mode=any; shift ;;
      --all|all)       mode=all; shift ;;
      --timeout-ms)
        [ -n "${2:-}" ] || { err "--timeout-ms 需要数值"; exit 1; }
        tmo=$2; shift 2 ;;
      -*) err "unknown arg: $1"; exit 1 ;;
      *)
        slot=$1; shift
        case "$(_triad_slot "$slot")" in
          chief) mode=chief ;; a) mode=a ;; b) mode=b ;;
          all) mode=all ;; any) mode=any ;;
        esac ;;
    esac
  done
  _triad_load_session
  # 等 agent 停后再轮询 par_result（agent wait 只唤醒）
  _triad_poll_token() {
    local role=$1 p=$2 budget_ms=${3:-15000} step=300 elapsed=0
    while [ "$elapsed" -lt "$budget_ms" ]; do
      _triad_try_harvest_from_token "$role" "$p" && return 0
      sleep 0.3
      elapsed=$((elapsed + step))
    done
    _triad_try_harvest_from_token "$role" "$p"
  }
  _triad_wait_one() {
    local p=$1 role=$2 st pending busy harv tid att
    [ -n "$p" ] || { err "无 $role pane（先 open）"; return 1; }
    st=$(_triad_agent_status "$p")
    if _triad_round_takeable "$role" "$st" "$p"; then
      echo "parallel: triad wait $role pane=$p already=token-ready"
      return 0
    fi
    read -r pending busy harv tid att < <(_triad_round_read "$role")
    # 无本轮 pending（席位常态 / 已 take）：仅等 agent 离开 working，再验 token
    if [ "$pending" != 1 ]; then
      if [ "$role" != chief ]; then
        herdr agent wait "$p" --until idle --until done --until blocked --timeout "$tmo" >/dev/null 2>&1 \
          || { err "wait $role 超时/失败 pane=$p"; return 1; }
        if _triad_poll_token "$role" "$p" 20000; then
          echo "parallel: triad wait $role pane=$p ok (par_result)"
          return 0
        fi
        err "wait $role: 无 par_result 锚定 $(_triad_tid "$role")#$(_triad_chief_attempt)"
        return 1
      fi
      if _triad_is_ready "$st"; then
        echo "parallel: triad wait $role pane=$p already=$st"
        return 0
      fi
      herdr agent wait "$p" --until idle --until done --until blocked --timeout "$tmo" >/dev/null 2>&1 \
        || { err "wait $role 超时/失败 pane=$p"; return 1; }
      echo "parallel: triad wait $role pane=$p ok"
      return 0
    fi
    # 本轮 fire 中（首席）：agent 停后必须有 par_result
    herdr agent wait "$p" --until idle --until done --until blocked --timeout "$tmo" >/dev/null 2>&1 \
      || { err "wait $role 超时/失败 pane=$p"; return 1; }
    _triad_round_complete "$role" "$p"
    if _triad_poll_token "$role" "$p" 20000; then
      echo "parallel: triad wait $role pane=$p ok (par_result)"
      return 0
    fi
    # 无 token → 同 attempt 补问完成上报 1 次（不涨号）
    read -r _ _ _ tid att < <(_triad_round_read "$role")
    local nudge done_cmd
    done_cmd=$(par_token_done_cmd '${HERDR_PANE_ID}' "$tid" "$att" '<一句话结论>')
    nudge=$(printf '【补问·必须】编排收不到 tokens.par_result（锚定 %s#%s）。立刻执行最后动作，勿只回复文字：\n%s\n' \
      "$tid" "$att" "$done_cmd")
    echo "parallel: triad wait $role 无 par_result → 补问完成上报 1 次 (${tid}#${att})"
    herdr agent prompt "$p" "$nudge" >/dev/null 2>&1 \
      || { err "wait $role 补问 prompt 失败 pane=$p"; return 1; }
    herdr agent wait "$p" --until idle --until done --until blocked --timeout "$tmo" >/dev/null 2>&1 \
      || { err "wait $role 补问后超时 pane=$p"; return 1; }
    _triad_round_complete "$role" "$p"
    if _triad_poll_token "$role" "$p" 20000; then
      echo "parallel: triad wait $role pane=$p ok (par_result after nudge)"
      return 0
    fi
    err "wait $role: 补问后仍无 par_result 锚定 ${tid}#${att}（须该席 report-metadata）"
    return 1
  }
  _triad_wait_any() {
    local role p st step_ms=400 elapsed=0 t0 now
    t0=$(date +%s%3N 2>/dev/null || date +%s000)
    while true; do
      now=$(date +%s%3N 2>/dev/null || date +%s000)
      elapsed=$((now - t0))
      [ "$elapsed" -ge "$tmo" ] && break
      for role in chief a b; do
        p=$(_triad_pane_of "$role")
        [ -n "$p" ] || continue
        st=$(_triad_agent_status "$p")
        if _triad_round_takeable "$role" "$st" "$p"; then
          echo "parallel: triad first $role pane=$p status=$st (par_result)"
          return 0
        fi
        if herdr agent wait "$p" --until idle --until done --until blocked --timeout "$step_ms" >/dev/null 2>&1; then
          _triad_round_complete "$role" "$p"
          _triad_poll_token "$role" "$p" 3000 || true
          if _triad_round_takeable "$role" "$(_triad_agent_status "$p")" "$p"; then
            echo "parallel: triad first $role pane=$p status=$(_triad_agent_status "$p") (par_result)"
            return 0
          fi
        fi
      done
    done
    err "wait --any 超时 ${tmo}ms（三席无本轮 par_result / 仍 busy）"
    return 1
  }
  case "$mode" in
    chief) _triad_wait_one "$CHIEF_PANE" chief || exit 2 ;;
    a)     _triad_wait_one "$A_PANE" a || exit 2 ;;
    b)     _triad_wait_one "$B_PANE" b || exit 2 ;;
    any)   _triad_wait_any || exit 2 ;;
    all)
      fail=0
      _triad_wait_one "$CHIEF_PANE" chief || fail=1
      _triad_wait_one "$A_PANE" a || fail=1
      _triad_wait_one "$B_PANE" b || fail=1
      [ "$fail" = 0 ] || exit 2
      ;;
  esac
}

# 编排糖：wait → take（人类兜底；主路径靠席位回注，fire 永不阻塞）
cmd_collect() {
  local wait_mode=all take_args=(--all) do_read=1 tmo="${PAR_TRIAD_WAIT_TIMEOUT_MS:-600000}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --any|any|first) wait_mode=any; take_args=(--first); shift ;;
      --all|all)       wait_mode=all; take_args=(--all); shift ;;
      --read|-r) do_read=1; shift ;;
      --no-read) do_read=0; shift ;;
      --timeout-ms)
        [ -n "${2:-}" ] || { err "--timeout-ms 需要数值"; exit 1; }
        tmo=$2; shift 2 ;;
      --json|-j) take_args+=(--json); shift ;;
      -*) err "unknown arg: $1"; exit 1 ;;
      *)
        case "$(_triad_slot "$1")" in
          chief) wait_mode=chief; take_args=(chief) ;;
          a)     wait_mode=a;     take_args=(a) ;;
          b)     wait_mode=b;     take_args=(b) ;;
          all)   wait_mode=all;   take_args=(--all) ;;
          any)   wait_mode=any;   take_args=(--first) ;;
          *) err "collect 槽位须 chief|a|b|all|any"; exit 1 ;;
        esac
        shift ;;
    esac
  done
  [ "$do_read" = 1 ] && take_args+=(--read)
  echo "parallel: triad collect（wait→take 兜底糖；fire 仍异步）"
  case "$wait_mode" in
    chief) cmd_wait chief --timeout-ms "$tmo" || exit $? ;;
    a)     cmd_wait a --timeout-ms "$tmo" || exit $? ;;
    b)     cmd_wait b --timeout-ms "$tmo" || exit $? ;;
    any)   cmd_wait --any --timeout-ms "$tmo" || exit $? ;;
    all)   cmd_wait --all --timeout-ms "$tmo" || exit $? ;;
  esac
  cmd_take "${take_args[@]}"
  return $?
}

# relay：席位回话的脚本闸控通道（代码兜底铁规 2/3/4；raw herdr 绕过属违规）
#   par-triad.sh relay <triad-chief|triad-a|triad-b> "<msg>"
# 发送者 = $HERDR_PANE_ID 对照 session 三席。
# rc0 发成；rc2 无 session；rc4 目标非三席/自注（隔离闸）；rc5 目标非 idle|done|blocked
# （状态闸，先 agent wait 再 relay）；rc6 发送者不在三席（主窗隔离）；rc7 本轮回话额度用完。
cmd_relay() {
  local target="" msg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --) shift; msg="${msg:+$msg }$*"; break ;;
      -*) err "unknown arg: $1"; exit 1 ;;
      *)
        if [ -z "$target" ]; then target=$1; else msg="${msg:+$msg }$1"; fi
        shift ;;
    esac
  done
  [ -n "$target" ] && [ -n "$msg" ] || { err "用法: relay <triad-chief|triad-a|triad-b> \"<msg>\""; exit 2; }
  _triad_load_session
  [ -n "${CHIEF_PANE:-}" ] || { err "无 triad session（先 par.sh triad open）"; exit 2; }

  # 发送者：$HERDR_PANE_ID 须在三席（主窗/外部隔离）
  local sender="" self="${HERDR_PANE_ID:-}"
  case "$self" in
    "${CHIEF_PANE:-__none__}") sender=chief ;;
    "${A_PANE:-__none__}")     sender=a ;;
    "${B_PANE:-__none__}")     sender=b ;;
  esac
  [ -n "$sender" ] || { err "relay 拒绝：发送者 pane=${self:-?} 不在 triad 三席（主窗隔离）"; exit 6; }

  # 目标：只接受三席别名（隔离闸）
  local trole tpane
  trole=$(_triad_slot "$target") || { err "relay 拒绝：目标 «$target» 非 triad-chief|a|b"; exit 4; }
  case "$trole" in
    chief|a|b) ;;
    *) err "relay 拒绝：目标 «$target» 非 triad-chief|a|b（隔离闸）"; exit 4 ;;
  esac
  tpane=$(_triad_pane_of "$trole")
  [ -n "$tpane" ] || { err "relay 拒绝：目标 $trole 无 pane"; exit 4; }
  [ "$trole" != "$sender" ] || { err "relay 拒绝：禁止自注 $sender → $trole"; exit 4; }

  # 状态闸：目标须 idle|done|blocked
  local st
  st=$(_triad_agent_status "$tpane")
  _triad_is_ready "$st" || {
    err "relay 闸门拦：$trole pane=$tpane status=$st（先 herdr agent wait $tpane --until idle --until done --until blocked 再 relay）"
    exit 5
  }

  # 回话上限：席位（a/b）每轮（首席 attempt）≤1 次
  local att mark
  att=$(_triad_chief_attempt)
  if [ "$sender" != chief ]; then
    mark="$(_triad_dir "$sender")/replied-$att"
    [ ! -f "$mark" ] || { err "relay 拒绝：$sender 本轮(#$att)回话额度已用完（上限 1 次/轮）"; exit 7; }
  fi

  herdr agent prompt "$tpane" "$msg" >/dev/null 2>&1 \
    || { err "relay prompt 失败 pane=$tpane"; exit 2; }
  [ "$sender" != chief ] && : > "$mark"
  echo "PAR-TRIAD-RELAY-PASS from=$sender to=$trole att=$att"
}

cmd_close() {
  # 显式收尾：临时允许关窗
  export PAR_CLOSE_PANE=1
  _triad_load_session
  local p role d
  for p in "${CHIEF_PANE:-}" "${A_PANE:-}" "${B_PANE:-}"; do
    [ -n "$p" ] || continue
    par_close_task_pane "$p" stack
  done
  for role in chief a b; do
    d=$(_triad_dir "$role")
    rm -f "$d/pane" "$d/round" 2>/dev/null || true
    [ -d "$d" ] && echo discarded > "$d/state" 2>/dev/null || true
  done
  if [ -f "$TRIAD_ROOT/session" ]; then
    echo "closed_at=$(date -Iseconds 2>/dev/null || date)" >> "$TRIAD_ROOT/session"
  fi
  echo "parallel: triad closed"
}

# ── entry ──
sub=${1:-open}
[ $# -gt 0 ] && shift || true
case "$sub" in
  open|start|up) cmd_open "$@" ;;
  status|st|ls|poll|ready) cmd_status "$@" ;;
  fire|f)        cmd_fire "$@" ;;
  take|t|harvest) cmd_take "$@" ;;
  relay|r)       cmd_relay "$@" ;;
  collect|c|auto-take) cmd_collect "$@" ;;  # wait→take 兜底糖
  wait|w)        cmd_wait "$@" ;;
  close|down|stop) cmd_close "$@" ;;
  -h|--help|help) usage ;;
  *)
    case "$sub" in
      --*) cmd_open "$sub" "$@" ;;
      *) err "usage: par-triad.sh open|fire|take|collect|status|wait|close …"; exit 2 ;;
    esac
    ;;
esac
