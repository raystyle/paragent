#!/usr/bin/env bash
# par-ix.sh — 并行交互（两令制 · 异步递进）
# 用法:
#   par-ix.sh open [--a <轨|cmd>] [--b <轨|cmd>] [--cwd DIR] [--force]
#   ── 两令（多任务并行唯一节奏）──
#   par-ix.sh fire <a|b> <msg…>     # 令1：只派发，火即返（=prompt，禁默认齐等）
#   par-ix.sh take [--all] [--read] # 令2：只收割已 READY（非阻塞；无则 rc3）
#   ── 编排糖（非第三令；= wait + take，不污染 fire）──
#   par-ix.sh collect [--all|a|b] [--read] [--timeout-ms N]
#   ── 辅助 ──
#   par-ix.sh status|poll [--json]
#   par-ix.sh wait [--any|a|b|all]  # 可选阻塞；讨论期优先 take 勿 wait all
#   par-ix.sh archive [--json]      # 归档清单/汇总（rc3=无归档）
#   par-ix.sh close
#
# 默认美学: 右上 a=@review/a Opus4.8 · 右下 b=@review/b GPT顶档
# 主窗不代开。交互期不关右窗，仅 ix close。
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/par-lib.sh"

# 交互模式硬规则：任何路径都不得自动关窗
export PAR_CLOSE_PANE=0

IX_ROOT="${PAR_IX_DIR:-$PWD/.parallel/ix}"
IX_CLAUDE_DIR="${IX_ROOT%/ix}/ix-claude"
IX_CODEX_DIR="${IX_ROOT%/ix}/ix-codex"
LABEL_CLAUDE="ix-claude"
LABEL_CODEX="ix-codex"
# 默认美学 = Opus 4.8 + GPT 最高（审阅双轨）
DEFAULT_CLAUDE="@review/a"
DEFAULT_CODEX="@review/b"

usage() {
  sed -n '2,16p' "$0" | sed -n '/^#/s/^# \?//p'
  exit 2
}

# 槽位 → 角色 claude|codex|all|any
_ix_slot() {
  case "$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')" in
    claude|a|left|opus|review/a|ix-claude) echo claude ;;
    codex|b|right|gpt|review/b|ix-codex)   echo codex ;;
    all|both) echo all ;;
    any|first|"") echo any ;;
    *) err "槽位须 a|b|claude|codex|any|all（got: $1）"; return 1 ;;
  esac
}

# agent_status 是否终态形态（未结合本轮 pending）
_ix_is_ready() {
  case "$1" in
    idle|done|blocked) return 0 ;;
    *) return 1 ;;
  esac
}

_ix_agent_status() {
  local pane=$1
  [ -n "$pane" ] || { echo missing; return; }
  herdr agent get "$pane" 2>/dev/null | jq -r '.result.agent.agent_status // "missing"' 2>/dev/null || echo missing
}

# ── 本轮派发基线（防「派发前 idle」被误收；take 只收 fire 完成的席）──
# $d/round: pending · busy_seen · harvestable · tid · attempt
# 完成真源 = tokens.par_result 锚定 tid#attempt + 非空结论（与 wave 同源；禁扫终端当判据）
_ix_round_file() {
  local d; d=$(_ix_dir "$1") || return 1
  printf '%s/round' "$d"
}

_ix_round_tid() {
  # 席级 tid：ix-claude / ix-codex（与 @review 轨解耦，仅作 token 锚）
  printf 'ix-%s' "$1"
}

_ix_round_write() {
  local role=$1 pending=${2:-0} busy=${3:-0} harv=${4:-0}
  local tid=${5:-} att=${6:-} f cur_t cur_a
  f=$(_ix_round_file "$role") || return 1
  mkdir -p "$(dirname "$f")"
  if [ -z "$tid" ] || [ -z "$att" ]; then
    cur_t=$(sed -n 's/^tid=//p' "$f" 2>/dev/null | head -1)
    cur_a=$(sed -n 's/^attempt=//p' "$f" 2>/dev/null | head -1)
    tid=${tid:-${cur_t:-$(_ix_round_tid "$role")}}
    att=${att:-${cur_a:-0}}
  fi
  printf 'pending=%s\nbusy_seen=%s\nharvestable=%s\ntid=%s\nattempt=%s\n' \
    "$pending" "$busy" "$harv" "$tid" "$att" > "$f"
}

_ix_round_read() {
  # stdout: pending busy_seen harvestable tid attempt
  local f pending=0 busy=0 harv=0 tid="" att=0
  f=$(_ix_round_file "$1") || { echo "0 0 0  0"; return; }
  if [ -f "$f" ]; then
    pending=$(sed -n 's/^pending=//p' "$f" | head -1)
    busy=$(sed -n 's/^busy_seen=//p' "$f" | head -1)
    harv=$(sed -n 's/^harvestable=//p' "$f" | head -1)
    tid=$(sed -n 's/^tid=//p' "$f" | head -1)
    att=$(sed -n 's/^attempt=//p' "$f" | head -1)
  fi
  printf '%s %s %s %s %s\n' "${pending:-0}" "${busy:-0}" "${harv:-0}" "${tid:-}" "${att:-0}"
}

_ix_next_attempt() {
  local att
  att=$(sed -n 's/^attempt=//p' "$(_ix_round_file "$1")" 2>/dev/null | head -1)
  echo $(( ${att:-0} + 1 ))
}

# fire：pending + 新 attempt；清旧 par_result 防串台
_ix_round_mark_prompt() {
  local role=$1 pane=$2 tid att
  tid=$(_ix_round_tid "$role")
  att=$(_ix_next_attempt "$role")
  [ -n "$pane" ] && par_clear_result_token "$pane"
  _ix_round_write "$role" 1 0 0 "$tid" "$att"
  printf '%s %s\n' "$tid" "$att"
}

_ix_round_clear() {
  _ix_round_write "$1" 0 0 0
}

# token 判本轮是否可收：done|blocked|waiting
_ix_token_gate() {
  local role=$1 pane=$2 pending busy harv tid att r
  read -r pending busy harv tid att < <(_ix_round_read "$role")
  [ -n "$pane" ] || { echo waiting; return; }
  [ -n "$tid" ] && [ "${att:-0}" -ge 1 ] 2>/dev/null || { echo waiting; return; }
  r=$(_par_report_token "$pane" "$tid" "$att")
  printf '%s\n' "$r"
}

# 若 token 锚定本轮 → harvestable=1
_ix_try_harvest_from_token() {
  local role=$1 pane=$2 gate
  gate=$(_ix_token_gate "$role" "$pane")
  case "$gate" in
    done|blocked)
      _ix_round_write "$role" 0 0 1
      return 0 ;;
  esac
  return 1
}

# 本轮完成 → 可 take（仅 token 过闸后）
_ix_round_mark_harvestable() {
  _ix_round_write "$1" 0 0 1
}

# status/poll 展示用：未 fire 的 idle 可「先看」；已 fire 则须 token 才 READY
# take 一律走 _ix_round_takeable（更严）
_ix_round_ready() {
  local role=$1 st=$2 pane=$3 pending busy harv tid att
  read -r pending busy harv tid att < <(_ix_round_read "$role")
  if [ "$pending" = 1 ]; then
    case "$st" in
      working)
        _ix_round_write "$role" 1 1 0
        return 1 ;;
      done|blocked|idle)
        [ "$st" = idle ] && [ "$busy" != 1 ] && return 1
        [ "$st" = idle ] && _ix_round_write "$role" 1 1 0
        if [ -n "$pane" ] && _ix_try_harvest_from_token "$role" "$pane"; then
          return 0
        fi
        return 1 ;;
      *) return 1 ;;
    esac
  fi
  if [ "$harv" = 1 ]; then
    [ -n "$pane" ] || return 0
    case "$(_ix_token_gate "$role" "$pane")" in done|blocked) return 0 ;; *) return 1 ;; esac
  fi
  # 本轮未 fire（attempt=0）：idle 可先看，不可 take
  _ix_is_ready "$st"
  return $?
}

# take 专用：仅 fire 本轮且 par_result 锚定 tid#attempt 非空
_ix_round_takeable() {
  local role=$1 st=$2 pane=$3 pending busy harv tid att
  # 推进 busy_seen；token 过闸才 harvestable
  _ix_round_ready "$role" "$st" "$pane" >/dev/null 2>&1 || true
  read -r pending busy harv tid att < <(_ix_round_read "$role")
  if [ "$harv" = 1 ]; then
    # 再验 token（防 take 前被清）
    case "$(_ix_token_gate "$role" "$pane")" in
      done|blocked) return 0 ;;
      *) _ix_round_write "$role" 0 0 0; return 1 ;;
    esac
  fi
  return 1
}

# take 收走后清 harvestable + 清 token，避免重复 take
_ix_round_took() {
  local role=$1 pane=$2
  _ix_round_write "$role" 0 0 0
  [ -n "$pane" ] && par_clear_result_token "$pane"
}

# agent wait 返回后：只认 token，不单靠 agent_status
_ix_round_complete() {
  local role=$1 pane=$2
  _ix_round_write "$role" 1 1 0
  _ix_try_harvest_from_token "$role" "$pane" || true
}

# prompt 后短等 busy，尽量记下 busy_seen（不堵死异步；不据此 harvest）
_ix_arm_after_prompt() {
  local role=$1 pane=$2 st i max="${PAR_IX_ARM_MS:-2000}" step=100 n
  n=$((max / step)); [ "$n" -lt 1 ] && n=1
  for i in $(seq 1 "$n"); do
    st=$(_ix_agent_status "$pane")
    case "$st" in
      working|done|blocked)
        _ix_round_write "$role" 1 1 0
        # 极短任务可能已写 token
        _ix_try_harvest_from_token "$role" "$pane" || true
        return 0 ;;
    esac
    sleep 0.1
  done
  return 0
}

_ix_dir() {
  case "$1" in
    claude) echo "$IX_CLAUDE_DIR" ;;
    codex)  echo "$IX_CODEX_DIR" ;;
    *) return 1 ;;
  esac
}

_ix_label() {
  case "$1" in
    claude) echo "$LABEL_CLAUDE" ;;
    codex)  echo "$LABEL_CODEX" ;;
    *) return 1 ;;
  esac
}

_ix_pane_alive() {
  local pane=$1 st
  [ -n "$pane" ] || return 1
  st=$(herdr agent get "$pane" 2>/dev/null | jq -r '.result.agent.agent_status // empty' 2>/dev/null) || return 1
  [ -n "$st" ] && [ "$st" != null ]
}

_ix_read_pane() {
  local d; d=$(_ix_dir "$1") || return 1
  cat "$d/pane" 2>/dev/null || true
}

_ix_write_side() {
  local role=$1 pane=$2 cmd=$3 d
  d=$(_ix_dir "$role") || return 1
  mkdir -p "$d"
  printf '%s\n' "$pane" > "$d/pane"
  printf 'mode=ix\nlayout=stack\nrole=%s\ncmd=%s\nlabel=%s\ncwd=%s\n' \
    "$role" "$cmd" "$(_ix_label "$role")" "${CWD:-$PWD}" > "$d/meta"
  echo working > "$d/state"
}

_ix_write_session() {
  mkdir -p "$IX_ROOT"
  {
    echo "mode=ix"
    echo "layout=stack"
    echo "claude_pane=${CLAUDE_PANE:-}"
    echo "codex_pane=${CODEX_PANE:-}"
    echo "claude_cmd=${CLAUDE_CMD:-}"
    echo "codex_cmd=${CODEX_CMD:-}"
    echo "cwd=${CWD:-$PWD}"
    echo "opened_at=$(date -Iseconds 2>/dev/null || date)"
  } > "$IX_ROOT/session"
}

_ix_load_session() {
  CLAUDE_PANE=$(_ix_read_pane claude)
  CODEX_PANE=$(_ix_read_pane codex)
  if [ -f "$IX_ROOT/session" ]; then
    CLAUDE_CMD=$(sed -n 's/^claude_cmd=//p' "$IX_ROOT/session" | head -1)
    CODEX_CMD=$(sed -n 's/^codex_cmd=//p' "$IX_ROOT/session" | head -1)
    CWD=$(sed -n 's/^cwd=//p' "$IX_ROOT/session" | head -1)
  fi
  CLAUDE_CMD=${CLAUDE_CMD:-}
  CODEX_CMD=${CODEX_CMD:-}
  CWD=${CWD:-$PWD}
}

_ix_print_usage() {
  cat <<EOF
parallel: ix ready（两令制 · 右 stack · 不自动关窗）
  主窗    （人类自定，不代开）
  右上 a  pane=${CLAUDE_PANE}  cmd=${CLAUDE_CMD}
  右下 b  pane=${CODEX_PANE}   cmd=${CODEX_CMD}
  session $IX_ROOT/session

两令制（并行多任务）— 禁止合成「一个大 command」齐等:
  # 令1 fire：只派发（可连发多席/多题）
  par.sh ix fire a "议题A"
  par.sh ix fire b "议题B"
  # 令2 take：只收已 READY（非阻塞；无 ready → rc3，立刻干别的）
  par.sh ix take --read              # 先到的先吐；可再 fire 新题
  par.sh ix take --all --read        # 本拍所有 READY 一次收
  # 循环：fire … / take … / fire 跟进 … / take …

  勿: wait all 包进同一条长命令。可选 wait --any 仅人眼守候。
EOF
}

cmd_open() {
  local force=0 raw_c="$DEFAULT_CLAUDE" raw_x="$DEFAULT_CODEX"
  CWD=$PWD
  while [ $# -gt 0 ]; do
    case "$1" in
      --claude|--a)
        [ -n "${2:-}" ] || { err "$1 需要 <轨|cmd>"; exit 1; }
        raw_c=$2; shift 2 ;;
      --codex|--b)
        [ -n "${2:-}" ] || { err "$1 需要 <轨|cmd>"; exit 1; }
        raw_x=$2; shift 2 ;;
      --cwd)
        [ -n "${2:-}" ] || { err "--cwd 需要目录"; exit 1; }
        CWD=$2; shift 2 ;;
      --force)  force=1; shift ;;
      -h|--help) usage ;;
      *) err "unknown arg: $1"; exit 1 ;;
    esac
  done
  [ -d "$CWD" ] || { err "cwd 不存在: $CWD"; exit 1; }
  CWD=$(cd "$CWD" && pwd -P)
  par_preflight || exit 1
  WS=$(par_ws) || exit 1

  CLAUDE_CMD=$(par_matrix_resolve "$raw_c") || exit 1
  CODEX_CMD=$(par_matrix_resolve "$raw_x") || exit 1

  # 幂等：已有存活 agent 且非 --force → 复用
  local old_c old_x
  old_c=$(_ix_read_pane claude)
  old_x=$(_ix_read_pane codex)
  if [ "$force" != 1 ] && _ix_pane_alive "$old_c" && _ix_pane_alive "$old_x"; then
    CLAUDE_PANE=$old_c
    CODEX_PANE=$old_x
    _ix_write_side claude "$CLAUDE_PANE" "$CLAUDE_CMD"
    _ix_write_side codex  "$CODEX_PANE"  "$CODEX_CMD"
    _ix_round_clear claude
    _ix_round_clear codex
    _ix_write_session
    echo "parallel: ix reuse claude=$CLAUDE_PANE codex=$CODEX_PANE"
    _ix_print_usage
    return 0
  fi

  # 强制重开：先关旧窗（仅本模式登记的）
  if [ "$force" = 1 ]; then
    [ -n "$old_c" ] && par_close_task_pane "$old_c" stack
    [ -n "$old_x" ] && par_close_task_pane "$old_x" stack
    # 上面 close 受 PAR_CLOSE_PANE=0 抑制；强制关
    [ -n "$old_c" ] && herdr pane close "$old_c" >/dev/null 2>&1 || true
    [ -n "$old_x" ] && herdr pane close "$old_x" >/dev/null 2>&1 || true
  fi

  # 串行 recruit：右柱 stack（right → down）
  CLAUDE_PANE=$(par_recruit "$WS" "$LABEL_CLAUDE" "$CLAUDE_CMD" "$CWD" stack) \
    || { err "ix claude recruit 失败"; exit 2; }
  _ix_write_side claude "$CLAUDE_PANE" "$CLAUDE_CMD"
  echo "parallel: ix opened claude pane=$CLAUDE_PANE cmd=$CLAUDE_CMD"

  CODEX_PANE=$(par_recruit "$WS" "$LABEL_CODEX" "$CODEX_CMD" "$CWD" stack) \
    || { err "ix codex recruit 失败（claude=$CLAUDE_PANE 仍保留）"; exit 2; }
  _ix_write_side codex "$CODEX_PANE" "$CODEX_CMD"
  echo "parallel: ix opened codex pane=$CODEX_PANE cmd=$CODEX_CMD"

  _ix_round_clear claude
  _ix_round_clear codex
  _ix_write_session
  _ix_print_usage
}

cmd_status() {
  local json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json|-j) json=1; shift ;;
      *) err "unknown arg: $1"; exit 1 ;;
    esac
  done
  _ix_load_session
  local st_c st_x ra=false rb=false
  st_c=$(_ix_agent_status "${CLAUDE_PANE:-}")
  st_x=$(_ix_agent_status "${CODEX_PANE:-}")
  # status READY：未 fire 的 idle 可先看；已 fire 须 par_result 才 READY
  _ix_round_ready claude "$st_c" "${CLAUDE_PANE:-}" && ra=true
  _ix_round_ready codex "$st_x" "${CODEX_PANE:-}" && rb=true
  if [ "$json" = 1 ]; then
    jq -n \
      --arg mode ix --arg layout stack --arg pace async \
      --arg cp "${CLAUDE_PANE:-}" --arg xp "${CODEX_PANE:-}" \
      --arg cc "${CLAUDE_CMD:-}" --arg xc "${CODEX_CMD:-}" \
      --arg cs "$st_c" --arg xs "$st_x" \
      --arg cwd "${CWD:-$PWD}" \
      --argjson ra "$ra" --argjson rb "$rb" \
      '{mode:$mode,layout:$layout,pace:$pace,cwd:$cwd,
        claude:{slot:"a",pane:$cp,cmd:$cc,status:$cs,ready:$ra},
        codex:{slot:"b",pane:$xp,cmd:$xc,status:$xs,ready:$rb}}'
    return 0
  fi
  echo "parallel: ix status (async progressive；take 以 par_result 为准)"
  printf '  a/claude  pane=%s  status=%s  %s  cmd=%s\n' \
    "${CLAUDE_PANE:-?}" "$st_c" "$([ "$ra" = true ] && echo READY || echo busy)" "${CLAUDE_CMD:-?}"
  printf '  b/codex   pane=%s  status=%s  %s  cmd=%s\n' \
    "${CODEX_PANE:-?}" "$st_x" "$([ "$rb" = true ] && echo READY || echo busy)" "${CODEX_CMD:-?}"
  echo "  pace=async  完成真源=tokens.par_result（tid#attempt）"
}

# 非阻塞扫席：谁 ready 先列出；rc0=至少一席可先看；rc3=全 busy；rc2=无 session
cmd_poll() {
  local json=0 ready_n=0 ra=false rb=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --json|-j) json=1; shift ;;
      *) err "unknown arg: $1"; exit 1 ;;
    esac
  done
  _ix_load_session
  [ -n "${CLAUDE_PANE:-}" ] || [ -n "${CODEX_PANE:-}" ] || { err "无 ix session（先 open）"; exit 2; }
  local st_c st_x
  st_c=$(_ix_agent_status "${CLAUDE_PANE:-}")
  st_x=$(_ix_agent_status "${CODEX_PANE:-}")
  # poll：未 fire 的 idle 算可先看；take 仍要 token
  if _ix_round_ready claude "$st_c" "${CLAUDE_PANE:-}"; then ra=true; ready_n=$((ready_n + 1)); fi
  if _ix_round_ready codex "$st_x" "${CODEX_PANE:-}"; then rb=true; ready_n=$((ready_n + 1)); fi
  if [ "$json" = 1 ]; then
    jq -n \
      --arg cp "${CLAUDE_PANE:-}" --arg xp "${CODEX_PANE:-}" \
      --arg cs "$st_c" --arg xs "$st_x" \
      --argjson ra "$ra" --argjson rb "$rb" \
      --argjson n "$ready_n" \
      '{ready_count:$n,
        slots:[
          {slot:"a",role:"claude",pane:$cp,status:$cs,ready:$ra},
          {slot:"b",role:"codex",pane:$xp,status:$xs,ready:$rb}
        ]}'
  else
    echo "parallel: ix poll ready_count=$ready_n"
    if [ "$ra" = true ]; then
      echo "  READY a/claude pane=${CLAUDE_PANE} status=$st_c"
    else
      echo "  busy  a/claude pane=${CLAUDE_PANE:-?} status=$st_c"
    fi
    if [ "$rb" = true ]; then
      echo "  READY b/codex  pane=${CODEX_PANE} status=$st_x"
    else
      echo "  busy  b/codex  pane=${CODEX_PANE:-?} status=$st_x"
    fi
  fi
  [ "$ready_n" -ge 1 ] && return 0
  return 3
}

cmd_prompt() {
  local slot msg wait=0 tmo="${PAR_IX_PROMPT_TIMEOUT_MS:-120000}" role pane
  [ $# -ge 2 ] || { err "usage: par-ix.sh prompt <a|b|claude|codex> <msg…> [--wait] [--timeout-ms N]"; exit 1; }
  slot=$1; shift
  msg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --wait) wait=1; shift ;;
      --timeout-ms)
        [ -n "${2:-}" ] || { err "--timeout-ms 需要数值"; exit 1; }
        tmo=$2; shift 2 ;;
      --) shift; msg="${msg:+$msg }$*"; break ;;
      *) msg="${msg:+$msg }$1"; shift ;;
    esac
  done
  msg=$(printf '%s' "$msg" | sed 's/^ //')
  [ -n "$msg" ] || { err "prompt 消息为空"; exit 1; }
  role=$(_ix_slot "$slot") || exit 1
  case "$role" in
    claude|codex) ;;
    *) err "prompt 须指定 a|b（单席异步派；勿 all）"; exit 1 ;;
  esac
  _ix_load_session
  case "$role" in
    claude) pane=$CLAUDE_PANE ;;
    codex)  pane=$CODEX_PANE ;;
  esac
  [ -n "$pane" ] || { err "无 $role pane（先 par.sh ix open）"; exit 2; }
  # 本轮 tid#attempt + 清旧 token；消息尾追加完成上报指令
  local tid att done_cmd blocked_cmd
  read -r tid att < <(_ix_round_mark_prompt "$role" "$pane")
  done_cmd=$(par_token_done_cmd '${HERDR_PANE_ID}' "$tid" "$att" '<一句话结论>')
  blocked_cmd=$(par_token_blocked_cmd '${HERDR_PANE_ID}' "$tid" "$att" '<原因>')
  msg=$(printf '%s\n\n【完成上报·必须·最后动作】编排只认 tokens.par_result（锚定 %s#%s + 非空结论）；扫终端不算完成。\n%s\n卡住: %s\n' \
    "$msg" "$tid" "$att" "$done_cmd" "$blocked_cmd")
  # 默认火即返（异步递进）；--wait 仅当明确要堵这一席回执
  if [ "$wait" = 1 ]; then
    herdr agent prompt "$pane" "$msg" --wait --until working --until done --timeout "$tmo" >/dev/null 2>&1 \
      || { err "prompt $role 无回执 pane=$pane"; exit 2; }
    _ix_round_write "$role" 1 1 0
    # 只认 token，不单靠 agent_status
    _ix_try_harvest_from_token "$role" "$pane" || true
  else
    herdr agent prompt "$pane" "$msg" >/dev/null 2>&1 \
      || { err "prompt $role 失败 pane=$pane"; exit 2; }
    # 短等 working + 尝试 token（极短任务）
    _ix_arm_after_prompt "$role" "$pane"
  fi
  echo "parallel: ix fire $role pane=$pane tid=$tid#$att (async$([ "$wait" = 1 ] && echo '+wait' || true))"
}

cmd_wait() {
  # 默认 --any：先到先看。all 仅显式齐等（讨论期不推荐）。
  local mode=any tmo="${PAR_IX_WAIT_TIMEOUT_MS:-600000}" slot=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --any|any|first) mode=any; shift ;;
      --all|all|both)  mode=all; shift ;;
      --timeout-ms)
        [ -n "${2:-}" ] || { err "--timeout-ms 需要数值"; exit 1; }
        tmo=$2; shift 2 ;;
      -*) err "unknown arg: $1"; exit 1 ;;
      *)
        slot=$1; shift
        case "$(_ix_slot "$slot")" in
          claude) mode=claude ;;
          codex)  mode=codex ;;
          all)    mode=all ;;
          any)    mode=any ;;
        esac
        ;;
    esac
  done
  _ix_load_session
  # 等 agent 停后再轮询 par_result（agent wait 只唤醒）
  _ix_poll_token() {
    local name=$1 p=$2 budget_ms=${3:-15000} step=300 elapsed=0
    while [ "$elapsed" -lt "$budget_ms" ]; do
      _ix_try_harvest_from_token "$name" "$p" && return 0
      sleep 0.3
      elapsed=$((elapsed + step))
    done
    _ix_try_harvest_from_token "$name" "$p"
  }
  _ix_wait_one() {
    local p=$1 name=$2 st pending busy harv tid att
    [ -n "$p" ] || { err "无 $name pane（先 open）"; return 1; }
    st=$(_ix_agent_status "$p")
    if _ix_round_takeable "$name" "$st" "$p"; then
      echo "parallel: ix wait $name pane=$p already=token-ready"
      return 0
    fi
    read -r pending busy harv tid att < <(_ix_round_read "$name")
    # 无本轮 pending：未 fire / 已 take —— 仅等 agent 离开 working
    if [ "$pending" != 1 ]; then
      if _ix_is_ready "$st"; then
        echo "parallel: ix wait $name pane=$p already=$st"
        return 0
      fi
      herdr agent wait "$p" --until idle --until done --until blocked --timeout "$tmo" >/dev/null 2>&1 \
        || { err "wait $name 超时/失败 pane=$p"; return 1; }
      echo "parallel: ix wait $name pane=$p ok"
      return 0
    fi
    # 本轮 fire 中：agent 停后必须有 par_result
    herdr agent wait "$p" --until idle --until done --until blocked --timeout "$tmo" >/dev/null 2>&1 \
      || { err "wait $name 超时/失败 pane=$p"; return 1; }
    _ix_round_complete "$name" "$p"
    if _ix_poll_token "$name" "$p" 20000; then
      echo "parallel: ix wait $name pane=$p ok (par_result)"
      return 0
    fi
    # B1：无 token → 同 attempt 补问完成上报 1 次（不涨号）
    read -r _ _ _ tid att < <(_ix_round_read "$name")
    local nudge done_cmd
    done_cmd=$(par_token_done_cmd '${HERDR_PANE_ID}' "$tid" "$att" '<一句话结论>')
    nudge=$(printf '【补问·必须】编排收不到 tokens.par_result（锚定 %s#%s）。立刻执行最后动作，勿只回复文字：\n%s\n' \
      "$tid" "$att" "$done_cmd")
    echo "parallel: ix wait $name 无 par_result → 补问完成上报 1 次 (${tid}#${att})"
    herdr agent prompt "$p" "$nudge" >/dev/null 2>&1 \
      || { err "wait $name 补问 prompt 失败 pane=$p"; return 1; }
    herdr agent wait "$p" --until idle --until done --until blocked --timeout "$tmo" >/dev/null 2>&1 \
      || { err "wait $name 补问后超时 pane=$p"; return 1; }
    _ix_round_complete "$name" "$p"
    if _ix_poll_token "$name" "$p" 20000; then
      echo "parallel: ix wait $name pane=$p ok (par_result after nudge)"
      return 0
    fi
    err "wait $name: 补问后仍无 par_result 锚定 ${tid}#${att}（须子席 report-metadata）"
    return 1
  }
  _ix_wait_any() {
    # 轮询双席 token 可收；pending 席用短 agent wait 推进，不 cancel peer
    local st_c st_x step_ms=400 elapsed=0 t0 now
    t0=$(date +%s%3N 2>/dev/null || date +%s000)
    while true; do
      now=$(date +%s%3N 2>/dev/null || date +%s000)
      elapsed=$((now - t0))
      [ "$elapsed" -ge "$tmo" ] && break
      st_c=$(_ix_agent_status "${CLAUDE_PANE:-}")
      st_x=$(_ix_agent_status "${CODEX_PANE:-}")
      if _ix_round_takeable claude "$st_c" "${CLAUDE_PANE:-}"; then
        echo "parallel: ix first a/claude pane=${CLAUDE_PANE} status=$st_c (par_result)"
        echo "parallel: ix peer b/codex  pane=${CODEX_PANE:-?} status=$st_x (继续跑，可再 poll)"
        return 0
      fi
      if _ix_round_takeable codex "$st_x" "${CODEX_PANE:-}"; then
        echo "parallel: ix first b/codex  pane=${CODEX_PANE} status=$st_x (par_result)"
        echo "parallel: ix peer a/claude pane=${CLAUDE_PANE:-?} status=$st_c (继续跑，可再 poll)"
        return 0
      fi
      # 短 wait 推进 pending/working 席，再试 token
      if [ -n "${CLAUDE_PANE:-}" ]; then
        if herdr agent wait "${CLAUDE_PANE}" --until idle --until done --until blocked --timeout "$step_ms" >/dev/null 2>&1; then
          _ix_round_complete claude "${CLAUDE_PANE}"
          _ix_poll_token claude "${CLAUDE_PANE}" 3000 || true
          if _ix_round_takeable claude "$(_ix_agent_status "${CLAUDE_PANE}")" "${CLAUDE_PANE}"; then
            echo "parallel: ix first a/claude pane=${CLAUDE_PANE} status=$(_ix_agent_status "$CLAUDE_PANE") (par_result)"
            echo "parallel: ix peer b/codex  pane=${CODEX_PANE:-?} status=$(_ix_agent_status "${CODEX_PANE:-}") (继续跑，可再 poll)"
            return 0
          fi
        fi
      fi
      if [ -n "${CODEX_PANE:-}" ]; then
        if herdr agent wait "${CODEX_PANE}" --until idle --until done --until blocked --timeout "$step_ms" >/dev/null 2>&1; then
          _ix_round_complete codex "${CODEX_PANE}"
          _ix_poll_token codex "${CODEX_PANE}" 3000 || true
          if _ix_round_takeable codex "$(_ix_agent_status "${CODEX_PANE}")" "${CODEX_PANE}"; then
            echo "parallel: ix first b/codex  pane=${CODEX_PANE} status=$(_ix_agent_status "$CODEX_PANE") (par_result)"
            echo "parallel: ix peer a/claude pane=${CLAUDE_PANE:-?} status=$(_ix_agent_status "${CLAUDE_PANE:-}") (继续跑，可再 poll)"
            return 0
          fi
        fi
      fi
    done
    err "wait --any 超时 ${tmo}ms（双席无本轮 par_result / 仍 busy）"
    return 1
  }
  case "$mode" in
    claude) _ix_wait_one "$CLAUDE_PANE" claude || exit 2 ;;
    codex)  _ix_wait_one "$CODEX_PANE"  codex  || exit 2 ;;
    any)    _ix_wait_any || exit 2 ;;
    all)
      fail=0
      _ix_wait_one "$CLAUDE_PANE" claude || fail=1
      _ix_wait_one "$CODEX_PANE"  codex  || fail=1
      [ "$fail" = 0 ] || exit 2
      ;;
  esac
}

# 令1：fire = 只派发（prompt 的语义别名；强制异步，去掉 --wait 默认真义）
cmd_fire() {
  # 过滤掉误传的 --wait，两令制 fire 永不阻塞
  local -a args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --wait) err "fire 禁止 --wait（两令制：收割用 take）；已忽略"; shift ;;
      *) args+=("$1"); shift ;;
    esac
  done
  cmd_prompt "${args[@]}"
}

# 令2：take = 只收割已 READY（非阻塞；可并行多任务）
#   take              → 先到的一席
#   take --all        → 当前所有 READY
#   take a|b          → 指定席，未 READY 则 rc3
#   take --read       → 附带 pane 可见文本（recent）
#   take --json       → 机器可读
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
        role=$(_ix_slot "$slot") || exit 1
        case "$role" in
          claude|codex) want="slot:$role" ;;
          any) want=first ;;
          all) want=all ;;
          *) err "take 槽位须 a|b|all"; exit 1 ;;
        esac
        ;;
    esac
  done
  _ix_load_session
  [ -n "${CLAUDE_PANE:-}" ] || [ -n "${CODEX_PANE:-}" ] || { err "无 ix session（先 open）"; exit 2; }

  local st_c st_x ta=false tb=false
  st_c=$(_ix_agent_status "${CLAUDE_PANE:-}")
  st_x=$(_ix_agent_status "${CODEX_PANE:-}")
  # take 只收 par_result 本轮锚定席（不收从未 fire / 无 token 的席）
  _ix_round_takeable claude "$st_c" "${CLAUDE_PANE:-}" && ta=true
  _ix_round_takeable codex "$st_x" "${CODEX_PANE:-}" && tb=true

  local -a sel_name=() sel_pane=() sel_st=() sel_role=()
  _ix_sel_push() {
    sel_name+=("$1"); sel_pane+=("$2"); sel_st+=("$3"); sel_role+=("$4")
  }
  case "$want" in
    first)
      if [ "$ta" = true ]; then _ix_sel_push a/claude "$CLAUDE_PANE" "$st_c" claude
      elif [ "$tb" = true ]; then _ix_sel_push b/codex "$CODEX_PANE" "$st_x" codex
      fi ;;
    all)
      [ "$ta" = true ] && _ix_sel_push a/claude "$CLAUDE_PANE" "$st_c" claude
      [ "$tb" = true ] && _ix_sel_push b/codex "$CODEX_PANE" "$st_x" codex
      ;;
    slot:claude) [ "$ta" = true ] && _ix_sel_push a/claude "$CLAUDE_PANE" "$st_c" claude ;;
    slot:codex)  [ "$tb" = true ] && _ix_sel_push b/codex  "$CODEX_PANE"  "$st_x"  codex  ;;
  esac

  local n=${#sel_name[@]}
  if [ "$json" = 1 ]; then
    local i items='[]' tok
    for i in "${!sel_name[@]}"; do
      local s rolep
      s=${sel_name[$i]%%/*}
      rolep=${sel_name[$i]#*/}
      tok=$(_par_raw_token "${sel_pane[$i]}")
      items=$(jq -c --argjson acc "$items" --arg s "$s" --arg r "$rolep" \
        --arg p "${sel_pane[$i]}" --arg st "${sel_st[$i]}" --arg tok "$tok" \
        '$acc + [{slot:$s,role:$r,pane:$p,status:$st,par_result:$tok}]')
    done
    jq -n --argjson took "$items" --argjson n "$n" '{took_count:$n, took:$took}'
  else
    local i tok
    for i in "${!sel_name[@]}"; do
      tok=$(_par_raw_token "${sel_pane[$i]}")
      echo "parallel: ix take ${sel_name[$i]} pane=${sel_pane[$i]} status=${sel_st[$i]}"
      [ -n "$tok" ] && echo "  par_result: $tok"
      if [ "$do_read" = 1 ] && [ -n "${sel_pane[$i]}" ]; then
        echo "----- read ${sel_pane[$i]} （佐证；完成真源=par_result）-----"
        herdr pane read "${sel_pane[$i]}" --source recent 2>/dev/null \
          | tr -d '\000' | sed 's/\x1b\[[0-9;]*m//g' | tail -c 12000 || true
        echo "----- end ${sel_pane[$i]} -----"
      fi
    done
    if [ "$n" -ge 1 ]; then
      echo "parallel: ix take done count=$n"
    else
      echo "parallel: ix take none (无本轮 par_result) — 可 fire 或稍后再 take"
    fi
  fi
  # L3：轮次归档（token 结论落盘，再清 token）
  local i
  for i in "${!sel_role[@]}"; do
    _ix_archive_take "${sel_role[$i]}" "${sel_pane[$i]}"
    _ix_round_took "${sel_role[$i]}" "${sel_pane[$i]}"
  done
  [ "$n" -ge 1 ] && return 0
  return 3
}

# 归档 .parallel/ix-*/archive/<attempt>-<ts>.md（PAR_IX_ARCHIVE=0 关闭）
_ix_archive_take() {
  local role=$1 pane=$2
  [ "${PAR_IX_ARCHIVE:-1}" = "0" ] && return 0
  local d pending busy harv tid att tok f ts
  d=$(_ix_dir "$role") || return 0
  read -r pending busy harv tid att < <(_ix_round_read "$role")
  tok=$(_par_raw_token "$pane")
  [ -n "$tok" ] || return 0
  mkdir -p "$d/archive"
  ts=$(date +%Y%m%dT%H%M%S 2>/dev/null || date +%s)
  f="$d/archive/${att:-0}-${ts}.md"
  {
    echo "# ix take archive"
    echo
    echo "- role: $role"
    echo "- pane: $pane"
    echo "- tid: $tid"
    echo "- attempt: $att"
    echo "- at: $(date -Iseconds 2>/dev/null || date)"
    echo "- par_result: \`$tok\`"
  } > "$f"
  echo "parallel: ix archive $f"
}

# 编排糖：wait → take（主控「派完自动收」用；两令仍分离，fire 永不阻塞）
#   collect              → wait all + take --all --read（双席终验默认）
#   collect --any        → wait --any + take --first --read
#   collect a|b          → 单席 wait + take
#   collect --no-read    → 不附 pane 正文
#   collect --timeout-ms N
cmd_collect() {
  local wait_mode=all take_args=(--all) do_read=1 tmo="${PAR_IX_WAIT_TIMEOUT_MS:-600000}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --any|any|first) wait_mode=any; take_args=(--first); shift ;;
      --all|all|both)  wait_mode=all; take_args=(--all); shift ;;
      --read|-r) do_read=1; shift ;;
      --no-read) do_read=0; shift ;;
      --timeout-ms)
        [ -n "${2:-}" ] || { err "--timeout-ms 需要数值"; exit 1; }
        tmo=$2; shift 2 ;;
      --json|-j) take_args+=(--json); shift ;;
      -*) err "unknown arg: $1"; exit 1 ;;
      *)
        case "$(_ix_slot "$1")" in
          claude) wait_mode=claude; take_args=(a) ;;
          codex)  wait_mode=codex;  take_args=(b) ;;
          all)    wait_mode=all;    take_args=(--all) ;;
          any)    wait_mode=any;    take_args=(--first) ;;
          *) err "collect 槽位须 a|b|all|any"; exit 1 ;;
        esac
        shift
        ;;
    esac
  done
  [ "$do_read" = 1 ] && take_args+=(--read)
  echo "parallel: ix collect（wait→take 编排糖；fire 仍异步两令）"
  case "$wait_mode" in
    claude) cmd_wait a --timeout-ms "$tmo" || exit $? ;;
    codex)  cmd_wait b --timeout-ms "$tmo" || exit $? ;;
    any)    cmd_wait --any --timeout-ms "$tmo" || exit $? ;;
    all)    cmd_wait --all --timeout-ms "$tmo" || exit $? ;;
  esac
  cmd_take "${take_args[@]}"
  return $?
}

cmd_close() {
  # 显式收尾：临时允许关窗
  export PAR_CLOSE_PANE=1
  _ix_load_session
  local p
  for p in "${CLAUDE_PANE:-}" "${CODEX_PANE:-}"; do
    [ -n "$p" ] || continue
    par_close_task_pane "$p" stack
  done
  # 清登记（保留 session 备份时间戳可选）
  rm -f "$IX_CLAUDE_DIR/pane" "$IX_CODEX_DIR/pane" \
    "$IX_CLAUDE_DIR/round" "$IX_CODEX_DIR/round" 2>/dev/null || true
  for d in "$IX_CLAUDE_DIR" "$IX_CODEX_DIR"; do
    [ -d "$d" ] && echo discarded > "$d/state" 2>/dev/null || true
  done
  if [ -f "$IX_ROOT/session" ]; then
    echo "closed_at=$(date -Iseconds 2>/dev/null || date)" >> "$IX_ROOT/session"
  fi
  echo "parallel: ix closed"
}

# archive：归档清单/汇总（P-3）。扫 .parallel/ix-*/archive/*.md，逐条解 role/attempt/时间/结论
# rc0 有条目；rc3 无归档
cmd_archive() {
  local json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json|-j) json=1; shift ;;
      -h|--help) usage ;;
      *) err "unknown arg: $1"; exit 1 ;;
    esac
  done
  local root="${IX_ROOT%/ix}" f role att at tok n=0
  local items='[]'
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    role=$(sed -n 's/^- role: //p' "$f" | head -1)
    att=$(sed -n 's/^- attempt: //p' "$f" | head -1)
    at=$(sed -n 's/^- at: //p' "$f" | head -1)
    tok=$(sed -n 's/^- par_result: `\(.*\)`$/\1/p' "$f" | head -1)
    n=$((n+1))
    if [ "$json" = 1 ]; then
      items=$(jq -cn --argjson acc "$items" --arg r "${role:-?}" --arg a "${att:-0}" \
        --arg at "${at:-?}" --arg t "${tok:-}" --arg f "$f" \
        '$acc + [{role:$r,attempt:$a,at:$at,par_result:$t,file:$f}]')
    else
      printf '%s #%s  %s  %s\n' "${role:-?}" "${att:-0}" "${at:-?}" "${tok:-（无 par_result）}"
    fi
  done < <(find "$root" -maxdepth 3 -path '*ix-*/archive/*.md' 2>/dev/null | sort)
  if [ "$json" = 1 ]; then
    jq -n --argjson items "$items" --argjson n "$n" '{count:$n, archive:$items}'
  else
    echo "parallel: ix archive count=$n"
  fi
  [ "$n" -ge 1 ] && return 0
  return 3
}

# ── entry ──
sub=${1:-open}
[ $# -gt 0 ] && shift || true
case "$sub" in
  open|start|up) cmd_open "$@" ;;
  status|st|ls)  cmd_status "$@" ;;
  poll|ready)    cmd_poll "$@" ;;
  fire|f)        cmd_fire "$@" ;;
  take|t|harvest) cmd_take "$@" ;;
  archive|ar)    cmd_archive "$@" ;;
  collect|c|auto-take) cmd_collect "$@" ;;  # wait→take 编排糖
  prompt|p|ask)  cmd_prompt "$@" ;;  # 兼容旧名 = fire（可 --wait）
  wait|w)        cmd_wait "$@" ;;
  close|down|stop) cmd_close "$@" ;;
  -h|--help|help) usage ;;
  *)
    case "$sub" in
      --*) cmd_open "$sub" "$@" ;;
      *) err "usage: par-ix.sh open|fire|take|collect|status|poll|wait|close …"; exit 2 ;;
    esac
    ;;
esac
