# par-lib.sh — workspace 并行原语 herdr 层(herdr >= 0.7.5;自包含)
# 契约:成功 stdout 单行;失败 stderr 单行 + return 1
#
# 完成判定协议(state 驱动,2026-07 实测 herdr 0.7.5 结论):
#   1. 受管 agent(herdr agent start 起的 pi/claude/...)回合完成 → agent_status=done(原生检测,
#      持续不回落);herdr agent wait <pane> --until idle --until done --until blocked 可靠等待,已处目标态立即 rc0,
#      超时/进程退出(agent_not_found) rc≠0。--timeout 单位 ms,--until 可重复;无 --until 默认 idle|done|blocked。
#   2. herdr pane report-agent --state 只对 herdr 无检测的 pane(纯 shell)生效;受管 agent 上被
#      检测循环覆盖(blocked/working/unknown 均不 stick)。故 blocked 不能靠 report state 传递,
#      report-agent 仅作 best-effort(未受管 pane 上有效)。
#   3. report-agent --message 不进 agent get/pane get(无 custom_status 字段),仅事件流,作人类可读。
#   4. herdr pane report-metadata <pane> --source <id> --token k=v:token 持久(实测 ≥12s 不消)、
#      可覆盖写、可 --clear-token,pane get 的 .result.pane.tokens 可查 → done/blocked 的结构化区分通道。
#   5. CLI 怪癖:report-agent/report-metadata 的 PANE_ID 必须是第一个参数(选项跟后),且不支持 --opt=value。
err() { echo "parallel: $*" >&2; }

# 本 lib 所在目录 / 技能根（task.md 绝对路径用）
PAR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAR_SKILL_DIR="$(cd "$PAR_LIB_DIR/.." && pwd)"
PAR_HOME="${PAR_HOME:-$(cd "$PAR_LIB_DIR/.." && pwd)}"
# dyn_title 侧栏集成（可选）：指向外部 layout_lib/snippet；缺省空 = 不写 dyn（herdr 官方默认 sidebar 无 $dyn_title）
PAR_LAYOUT_LIB="${PAR_LAYOUT_LIB:-}"
PAR_SIDEBAR_SNIP="${PAR_SIDEBAR_SNIP:-}"
# urgency 序（借鉴 herdr-pane-navigator）：blocked < done < working < idle < 其他
# status 面板按此排序——最需人处理的席浮前
par_status_urgency() {
  case "$1" in
    blocked) echo 0 ;; done) echo 1 ;; working) echo 2 ;; idle) echo 3 ;; *) echo 4 ;;
  esac
}

# 矩阵档案：local=主控满矩阵；remote=远程 CPA 子集（见 matrix-remote.json / models.md）
# 覆盖：PAR_MATRIX_PROFILE=local|remote · 或轨前缀 @remote/develop/a · PAR_MATRIX_JSON 强制表路径
PAR_MATRIX_PROFILE="${PAR_MATRIX_PROFILE:-local}"
PAR_MATRIX_JSON_LOCAL="${PAR_MATRIX_JSON_LOCAL:-$PAR_SKILL_DIR/references/matrix.json}"
PAR_MATRIX_JSON_REMOTE="${PAR_MATRIX_JSON_REMOTE:-$PAR_SKILL_DIR/references/matrix-remote.json}"
PAR_MATRIX_JSON="${PAR_MATRIX_JSON:-}"

# ── metadata token 约定（可复用；默认 parallel / par_result）──
# 其它子系统可 export PAR_META_SOURCE / PAR_META_KEY 后复用 helper。
par_meta_source() { printf '%s' "${PAR_META_SOURCE:-parallel}"; }
par_meta_key()    { printf '%s' "${PAR_META_KEY:-par_result}"; }
# 完成/卡住 token 值体（不含 key=）
par_token_done_val()    { printf 'PAR-DONE %s#%s %s' "$1" "$2" "${3:-ok}"; }
par_token_blocked_val() { printf 'PAR-BLOCKED %s#%s %s' "$1" "$2" "${3:-blocked}"; }
# 完整 shell 命令（给 task.md / 子 agent）
par_token_done_cmd() {
  local pane=${1:-'${HERDR_PANE_ID}'} tid=$2 att=$3 note=${4:-'<一句话结论>'}
  printf 'herdr pane report-metadata "%s" --source %s --token "%s=%s"' \
    "$pane" "$(par_meta_source)" "$(par_meta_key)" "$(par_token_done_val "$tid" "$att" "$note")"
}
par_token_blocked_cmd() {
  local pane=${1:-'${HERDR_PANE_ID}'} tid=$2 att=$3 note=${4:-'<原因>'}
  printf 'herdr pane report-metadata "%s" --source %s --token "%s=%s"' \
    "$pane" "$(par_meta_source)" "$(par_meta_key)" "$(par_token_blocked_val "$tid" "$att" "$note")"
}

par_ws() {
  if [ -n "${HERDR_WORKSPACE_ID:-}" ]; then echo "$HERDR_WORKSPACE_ID"; return 0; fi
  local ws; ws=$(herdr workspace list \
    | jq -r '(.result.workspaces[]|select(.focused==true).workspace_id)//.result.workspaces[0].workspace_id' \
    | head -1)
  # workspaces 为空时 jq 输出字面量 null,一并视为失败
  { [ -n "$ws" ] && [ "$ws" != null ]; } || { err "workspace list 为空(不在 herdr 会话?)"; return 1; }
  echo "$ws"
}

par_preflight() {
  [ "${HERDR_ENV:-}" = 1 ] || { err "HERDR_ENV != 1 (not in herdr session)"; return 1; }
  for c in herdr jq git; do command -v "$c" >/dev/null 2>&1 || { err "$c not found"; return 1; }; done
}

# par_yolo_cmd <model-cmd> → stdout 注入 herdr 交互启动用的免交互旗标
# herdr agent start 走**交互 TUI**，仅靠 config.toml/settings 仍会在新目录弹 trust/审批；
# 启动 argv 必须带危险旁路旗标（与 agent-cli-ensure 的 yolo 配置双保险）。
par_yolo_cmd() {
  local cmd=$1 bin
  bin=$(basename "${cmd%% *}")
  case "$bin" in
    codex)
      # bypass 与 -a/-s 互斥（codex CLI 拒：cannot be used with --ask-for-approval）
      # 只注 bypass + hook-trust；config.toml yolo 作双保险
      case " $cmd " in *" --dangerously-bypass-approvals-and-sandbox "*) ;;
        *) cmd="$cmd --dangerously-bypass-approvals-and-sandbox" ;;
      esac
      # herdr SessionStart hooks 未 trust 时会弹 TUI 卡住（非 401）
      case " $cmd " in *" --dangerously-bypass-hook-trust "*) ;;
        *) cmd="$cmd --dangerously-bypass-hook-trust" ;;
      esac
      # 若上游误带 -a/-s，剥掉以免与 bypass 冲突
      cmd=$(printf '%s' "$cmd" | sed -E \
        -e 's/ --ask-for-approval(=[^ ]+)? / /g' \
        -e 's/ -a( +[^ -][^ ]*|=[^ ]+) / /g' \
        -e 's/ --sandbox(=[^ ]+)? / /g' \
        -e 's/ -s( +[^ -][^ ]*|=[^ ]+) / /g')
      cmd=$(printf '%s' "$cmd" | tr -s ' ')
      ;;
    claude)
      case " $cmd " in *" --dangerously-skip-permissions "*) ;;
        *) cmd="$cmd --dangerously-skip-permissions" ;;
      esac
      case " $cmd " in *" --permission-mode "*) ;;
        *) cmd="$cmd --permission-mode bypassPermissions" ;;
      esac
      ;;
    # pi/kimi/grok：交互弹窗主要靠 seed_trust；无统一 yolo 旗标
  esac
  printf '%s' "$cmd"
}

# par_seed_trust <agent-cmd> <dir> — 幂等消除 claude/codex/grok 首入目录弹窗(flock 串行)
# 必须对**实际 cwd**（含 worktree / .parallel/*/wt / 远程研究目录）调用，仅信任 $HOME 不够。
par_seed_trust() {
  local bin dir abs
  bin=$(basename "${1%% *}"); dir=$2
  # 规范化绝对路径（相对路径会导致 trust key 对不上 herdr cwd）
  if [ -d "$dir" ]; then
    abs=$(cd "$dir" 2>/dev/null && pwd -P) || abs=$dir
  else
    abs=$dir
  fi
  case "$bin" in
    claude)
      [ -f "$HOME/.claude.json" ] || printf '{}' > "$HOME/.claude.json"
      ( flock -w 10 9 || exit 1
        local t="$HOME/.claude.json.par-tmp.$$"
        # trust 对话框 + 该目录当项目信任
        jq --arg d "$abs" '
          .projects[$d] = ((.projects[$d] // {}) + {
            hasTrustDialogAccepted: true,
            hasCompletedProjectOnboarding: true
          })
        ' "$HOME/.claude.json" > "$t" && mv "$t" "$HOME/.claude.json" || rm -f "$t"
      ) 9>"$HOME/.claude.json.par-lock" ;;
    codex)
      mkdir -p "$HOME/.codex"; [ -f "$HOME/.codex/config.toml" ] || : > "$HOME/.codex/config.toml"
      ( flock -w 10 9 || exit 1
        # 强制 yolo 两行（旧机可能只有 cpa 无 yolo）
        grep -qE '^sandbox_mode\s*=' "$HOME/.codex/config.toml" 2>/dev/null \
          || printf 'sandbox_mode = "danger-full-access"\n' >> "$HOME/.codex/config.toml"
        grep -qE '^approval_policy\s*=' "$HOME/.codex/config.toml" 2>/dev/null \
          || printf 'approval_policy = "never"\n' >> "$HOME/.codex/config.toml"
        # 幂等改写为 yolo（若曾被改成 read-only / on-request）
        local t="$HOME/.codex/config.toml.par-tmp.$$"
        sed -e 's/^sandbox_mode\s*=.*/sandbox_mode = "danger-full-access"/' \
            -e 's/^approval_policy\s*=.*/approval_policy = "never"/' \
          "$HOME/.codex/config.toml" > "$t" && mv "$t" "$HOME/.codex/config.toml" || rm -f "$t"
        grep -qF "[projects.\"$abs\"]" "$HOME/.codex/config.toml" 2>/dev/null \
          || printf '\n[projects."%s"]\ntrust_level = "trusted"\n' "$abs" >> "$HOME/.codex/config.toml"
      ) 9>"$HOME/.codex/config.toml.par-lock" ;;
    grok)
      mkdir -p "$HOME/.grok"
      ( flock -w 10 9 || exit 1
        grep -qF "[folders.\"$abs\"]" "$HOME/.grok/trusted_folders.toml" 2>/dev/null \
          || printf '\n[folders."%s"]\ntrusted = true\ndecided_at = %s\n' "$abs" "$(date +%s)" >> "$HOME/.grok/trusted_folders.toml"
      ) 9>"$HOME/.grok/trusted_folders.toml.par-lock" ;;
  esac
}

# ── 模型矩阵解析（matrix.json / matrix-remote.json；case 兜底）──
# 输入: 裸 model-cmd 或 @matrix/track（可省略 @）
#   档案 local（默认）: speed 双轨 · develop/research 三轨 · review 双轨
#   档案 remote: 极速=flash@codex · 开发=glm@claude · 研究=pro@codex · 审阅同 local
#   前缀: @remote/… 强制 remote 表；@local/… 强制 local 表
# 输出: 单行 model-cmd；未知轨 fail（不静默回落）
par_matrix_resolve() {
  local spec=$1 key v profile table
  profile=$(printf '%s' "${PAR_MATRIX_PROFILE:-local}" | tr 'A-Z' 'a-z')
  # 裸命令透传
  case "$spec" in
    @*) key=${spec#@} ;;
    speed/*|fast/*|develop/*|review/*|research/*|local/*|remote/*) key=$spec ;;
    *) printf '%s' "$spec"; return 0 ;;
  esac
  key=$(printf '%s' "$key" | tr 'A-Z' 'a-z')
  case "$key" in
    remote/*) profile=remote; key=${key#remote/} ;;
    local/*)  profile=local;  key=${key#local/}  ;;
  esac
  case "$profile" in
    remote|rem|mirror) profile=remote ;;
    *) profile=local ;;
  esac
  # 表路径：PAR_MATRIX_JSON 强制 > 档案默认
  if [ -n "${PAR_MATRIX_JSON:-}" ] && [ -f "$PAR_MATRIX_JSON" ]; then
    table=$PAR_MATRIX_JSON
  elif [ "$profile" = remote ]; then
    table=${PAR_MATRIX_JSON_REMOTE:-}
  else
    table=${PAR_MATRIX_JSON_LOCAL:-}
  fi
  if [ -n "$table" ] && [ -f "$table" ]; then
    v=$(jq -r --arg k "$key" 'select(type=="object") | .[$k] // empty' "$table" 2>/dev/null || true)
    # 忽略 _ 开头元键
    if [ -n "$v" ] && [ "$v" != null ] && [[ "$key" != _* ]]; then
      printf '%s' "$v"
      return 0
    fi
  fi
  # 内置兜底（与对应 json / models.md 同步）
  if [ "$profile" = remote ]; then
    case "$key" in
      speed/*|fast/*)
        echo 'codex -m deepseek-v4-flash-cx' ;;
      develop/*)
        echo 'claude --model glm-5.2-cc[1m]' ;;
      research/*)
        echo 'codex -m deepseek-v4-pro-cx' ;;
      review/a|review/opus)
        echo 'claude --model claude-opus-4-8-cc[1m]' ;;
      review/b|review/gpt)
        echo 'codex -m gpt-5.6-sol-cx' ;;
      *)
        err "未知远程矩阵轨: $spec（remote 仅 speed→flash · develop→glm · research→pro · review 双轨）"
        return 1 ;;
    esac
    return 0
  fi
  case "$key" in
    speed/a|speed/kimi|speed/hs|fast/a|fast/kimi|fast/hs)
      echo 'pi --model kimi/kimi-for-coding-highspeed-pi' ;;
    speed/b|speed/flash|fast/b|fast/flash)
      echo 'codex -m deepseek-v4-flash-cx' ;;
    develop/a|develop/k3)
      echo 'kimi -m kimi-code/k3' ;;
    develop/b|develop/grok)
      echo 'grok -m grok-4.5' ;;
    develop/c|develop/glm)
      echo 'claude --model glm-5.2-cc[1m]' ;;
    review/a|review/opus)
      echo 'claude --model claude-opus-4-8-cc[1m]' ;;
    review/b|review/gpt)
      echo 'codex -m gpt-5.6-sol-cx' ;;
    research/a|research/grok)
      echo 'grok -m grok-4.5' ;;
    research/b|research/kimi)
      echo 'kimi -m kimi-code/kimi-for-coding' ;;
    research/c|research/pro|research/deepseek)
      echo 'codex -m deepseek-v4-pro-cx' ;;
    *)
      err "未知矩阵轨: $spec（见 parallel/references/matrix.json · models.md）"
      return 1 ;;
  esac
}

# 布局: tab=每任务一 tab（默认；agent 不开右侧窗格）; stack=右侧叠窗（仅 --layout stack）
# 右柱锚点: 无右柱 → main right; 有右柱 → 最底 down（stack 专用）
_par_stack_anchor() {
  herdr pane layout --current 2>/dev/null | python3 -c '
import json,sys
raw=sys.stdin.read()
try:
    d=json.loads(raw[raw.index("{"):])
except Exception:
    sys.exit(1)
panes=(d.get("result",{}).get("layout") or {}).get("panes") or []
if not panes: sys.exit(1)
main=min(panes, key=lambda p: (p["rect"]["x"], 0 if p.get("focused") else 1))
mx=main["rect"]["x"]
right=[p for p in panes if p["rect"]["x"] > mx + 2]
if not right:
    print(main["pane_id"], "right", "0.45")
else:
    bottom=max(right, key=lambda p: p["rect"]["y"]+p["rect"]["height"])
    print(bottom["pane_id"], "down", "0.5")
'
}

# par_open_pane <label> <cwd> <layout:tab|stack> [ws] → stdout pane_id
# tab:   新 tab 根窗格（默认；develop/research/审阅一律）
# stack: 当前 tab 右侧叠开（flock 串行 split；仅显式 --layout stack）
par_open_pane() {
  local label=$1 cwd=$2 layout=${3:-tab} ws=${4:-} pane
  case "$layout" in
    tab)
      local tc tid
      if [ -n "$ws" ]; then
        tc=$(herdr tab create --workspace "$ws" --label "$label" --cwd "$cwd" --no-focus)
      else
        tc=$(herdr tab create --label "$label" --cwd "$cwd" --no-focus)
      fi
      pane=$(printf '%s' "$tc" | jq -r '.result.root_pane.pane_id')
      if [ -z "$pane" ] || [ "$pane" = null ]; then
        tid=$(printf '%s' "$tc" | jq -r '.result.tab.tab_id // .result.root_pane.tab_id // empty')
        [ -n "$tid" ] && herdr tab close "$tid" >/dev/null 2>&1
        err "tab create returned no pane_id for $label"; return 1
      fi
      ;;
    stack)
      local lock anchor target dir ratio sj
      lock="${XDG_RUNTIME_DIR:-/tmp}/workspace-par-layout.lock"
      (
        flock -w 30 8 || { err "stack layout lock timeout"; exit 1; }
        anchor=$(_par_stack_anchor) || { err "layout anchor failed"; exit 1; }
        # shellcheck disable=SC2086
        set -- $anchor
        target=$1; dir=$2; ratio=$3
        sj=$(herdr pane split "$target" --direction "$dir" --ratio "$ratio" --cwd "$cwd" --no-focus 2>&1) \
          || { err "pane split failed: $sj"; exit 1; }
        pane=$(printf '%s' "$sj" | jq -r '.result.pane.pane_id // empty')
        [ -n "$pane" ] && [ "$pane" != null ] || { err "split returned no pane_id for $label"; exit 1; }
        printf '%s' "$pane" > "${lock}.pane"
      ) 8>"$lock" || return 1
      pane=$(cat "${lock}.pane" 2>/dev/null)
      rm -f "${lock}.pane"
      [ -n "$pane" ] || return 1
      sleep 0.1
      ;;
    *)
      err "layout 须 tab|stack（got: $layout）"; return 1
      ;;
  esac
  herdr pane rename "$pane" "$label" >/dev/null 2>&1 || true
  echo "$pane"
}

# par_recruit <ws> <label> <agent-cmd> [cwd] [layout:tab|stack] → stdout pane_id
# layout 默认 tab（每任务一 tab）；stack 仅显式传入
# 顺序：seed trust(cwd) → open pane → yolo 旗标注入 → agent start
par_recruit() {
  local ws=$1 label=$2 cmd=$3 cwd=${4:-$PWD} layout=${5:-tab} pane kind args
  # 绝对 cwd，与 trust key / herdr pane cwd 一致
  if [ -d "$cwd" ]; then cwd=$(cd "$cwd" && pwd -P); fi
  cmd=$(par_yolo_cmd "$cmd")
  kind=$(basename "${cmd%% *}"); args=${cmd#* }
  par_seed_trust "$cmd" "$cwd"
  pane=$(par_open_pane "$label" "$cwd" "$layout" "$ws") || return 1
  # 新 tab/split 后 shell 就绪略等，避免 agent_pane_busy / not available shell
  sleep 0.4
  local try
  for try in 1 2 3 4 5; do
    if [ "$args" = "$kind" ]; then
      herdr agent start "$label" --kind "$kind" --pane "$pane" --timeout 90000 >/dev/null 2>&1
    else
      # shellcheck disable=SC2086
      herdr agent start "$label" --kind "$kind" --pane "$pane" --timeout 90000 -- $args >/dev/null 2>&1
    fi && {
      # 启动成功即清旧 par_result，防止上轮 token 串台
      par_clear_result_token "$pane"
      # 侧栏定版：行1 title；dyn 仅当 snippet 绑 $dyn_title（与 layout_lib 同源）
      # 官方默认无 $dyn_title → 不写 / 清残留，禁 frozenset({"*"}) 死写入
      _dyn=$(herdr pane get "$pane" 2>/dev/null | LAYOUT_LIB="$PAR_LAYOUT_LIB" \
        SIDEBAR_SNIP="$PAR_SIDEBAR_SNIP" \
        LABEL="$label" KIND="$kind" python3 -c '
import json,sys,os,importlib.util
try:
  p=json.load(sys.stdin)["result"]["pane"]
except Exception:
  raise SystemExit(0)
lib=os.environ.get("LAYOUT_LIB","")
snip=os.environ.get("SIDEBAR_SNIP","")
label=os.environ.get("LABEL","")
try:
  spec=importlib.util.spec_from_file_location("layout_lib", lib)
  L=importlib.util.module_from_spec(spec); spec.loader.exec_module(L)
  dk=L.discover_dyn_title_kinds(snip) if snip else frozenset()
  pm={p.get("pane_id"): label} if p.get("pane_id") and label else {}
  d=L.want_dyn_title(p, dyn_kinds=dk, parallel_by_pane=pm) or ""
  print(d[:80], end="")
except Exception:
  pass
' 2>/dev/null || true)
      if [ -n "${_dyn:-}" ]; then
        herdr pane report-metadata "$pane" --source skill:par \
          --display-agent "$kind" \
          --title "${kind}-${label}" \
          --token "pane_title=${kind}-${label}" \
          --token "dyn_title=${_dyn}" >/dev/null 2>&1 || true
      else
        herdr pane report-metadata "$pane" --source skill:par \
          --display-agent "$kind" \
          --title "${kind}-${label}" \
          --token "pane_title=${kind}-${label}" \
          --clear-token dyn_title >/dev/null 2>&1 || true
      fi
      herdr agent rename "$pane" --clear >/dev/null 2>&1 || true
      echo "$pane"
      return 0
    }
    [ "$try" -lt 5 ] && sleep 3
  done
  err "$label ($pane) agent start failed"; herdr pane close "$pane" >/dev/null 2>&1; return 1
}

# ── 完成判定：herdr pane report-metadata token 是唯一稳定完成信号 ──
# 子 agent 必须:
#   herdr pane report-metadata "$HERDR_PANE_ID" --source parallel \
#     --token "par_result=PAR-DONE <tid>#<attempt> <结论>"
# 或 PAR-BLOCKED …；编排只认 pane get .tokens.par_result（锚定 tid#attempt）。
# agent_status 仅作唤醒/兜底，不单独判 done。

# 清旧 token，避免上轮 PAR-DONE 串台秒配
par_clear_result_token() {
  local pane=$1 src key
  src=$(par_meta_source); key=$(par_meta_key)
  # PANE_ID 可置尾；成功=rc0
  herdr pane report-metadata --source "$src" --clear-token "$key" "$pane" >/dev/null 2>&1 || true
}

# 收尾关任务窗格（tab 关整 tab；stack 关 pane）。PAR_CLOSE_PANE=0 保留。
# 默认 1=收割后关，避免极限测后 tab 堆积。
par_close_task_pane() {
  local pane=$1 layout=${2:-tab} tab
  [ "${PAR_CLOSE_PANE:-1}" = "1" ] || return 0
  [ -n "$pane" ] || return 0
  if [ "$layout" = tab ]; then
    tab=$(herdr pane get "$pane" 2>/dev/null | jq -r '.result.pane.tab_id // empty' 2>/dev/null || true)
    if [ -n "$tab" ] && [ "$tab" != null ]; then
      herdr tab close "$tab" >/dev/null 2>&1 || herdr pane close "$pane" >/dev/null 2>&1 || true
      return 0
    fi
  fi
  herdr pane close "$pane" >/dev/null 2>&1 || true
}

# 关本仓 .parallel/*/pane 列出的任务窗（不清主栏）
# 跳过 mode=discuss / 目录 discuss-*：并行交互席只允许 par.sh discuss close 显式关
par_close_all_task_panes() {
  local root td pane layout mode base
  root="${1:-$PWD}"
  for td in "$root"/.parallel/*/; do
    [ -d "$td" ] || continue
    base=$(basename "$td")
    case "$base" in
      discuss|discuss-*) continue ;;  # .parallel/discuss/ · discuss-claude · discuss-codex
    esac
    mode=$(sed -n 's/^mode=//p' "${td}meta" 2>/dev/null | head -1)
    [ "$mode" = discuss ] && continue
    pane=$(cat "${td}pane" 2>/dev/null || true)
    layout=$(sed -n 's/^layout=//p' "${td}meta" 2>/dev/null | head -1)
    layout=${layout:-tab}
    [ -n "$pane" ] && par_close_task_pane "$pane" "$layout"
  done
}

# par_dispatch_msg <pane> <msg> → rc0=回执(PAR_DISPATCH_TIMEOUT_MS 内 working|done;失败重发一次)
par_dispatch_msg() {
  local tmo="${PAR_DISPATCH_TIMEOUT_MS:-30000}"
  herdr agent prompt "$1" "$2" --wait --until working --until done --timeout "$tmo" >/dev/null 2>&1 && return 0
  herdr agent prompt "$1" "$2" --wait --until working --until done --timeout "$tmo" >/dev/null 2>&1
}

# 读 tokens.<key> → done|blocked|waiting（锚定 tid#attempt + 非空结论）
# 协议: PAR-DONE <tid>#<attempt> <一句话>  |  PAR-BLOCKED <tid>#<attempt> <原因>
# 空结论 / 仅锚点 / #1 误配 #10 → waiting
_par_report_token() {
  local tok key rest
  key=$(par_meta_key)
  tok=$(herdr pane get "$1" 2>/dev/null | jq -r --arg k "$key" '.result.pane.tokens[$k] // empty' 2>/dev/null) \
    || { echo waiting; return; }
  # 禁换行；结论须非空且限长
  case "$tok" in
    *$'\n'*|*$'\r'*) echo waiting; return ;;
  esac
  case "$tok" in
    "PAR-DONE $2#$3 "*)
      rest=${tok#"PAR-DONE $2#$3 "}
      if [ -n "$rest" ] && [ "${#rest}" -le 200 ]; then echo done; else echo waiting; fi
      ;;
    "PAR-BLOCKED $2#$3 "*)
      rest=${tok#"PAR-BLOCKED $2#$3 "}
      if [ -n "$rest" ] && [ "${#rest}" -le 200 ]; then echo blocked; else echo waiting; fi
      ;;
    *) echo waiting ;;
  esac
}

# 原始 token 字符串（调试/落 .await）
_par_raw_token() {
  local key; key=$(par_meta_key)
  herdr pane get "$1" 2>/dev/null | jq -r --arg k "$key" '.result.pane.tokens[$k] // empty' 2>/dev/null || true
}

# 刷 $dyn_title（仅 snippet 绑了 $dyn_title 时；PAR_DYN_REFRESH=0 关闭）
# dyn_kinds 与 layout_lib.discover_dyn_title_kinds(snippet) 同源；官方默认空 → 清残留、不写。
par_refresh_dyn_title() {
  local pane=$1 tid=${2:-}
  [ "${PAR_DYN_REFRESH:-1}" = "0" ] && return 0
  [ -n "$pane" ] || return 0
  local lib="$PAR_LAYOUT_LIB" snip="$PAR_SIDEBAR_SNIP" want cur
  [ -f "$lib" ] || return 0
  want=$(herdr pane get "$pane" 2>/dev/null | LAYOUT_LIB="$lib" SIDEBAR_SNIP="$snip" TID="$tid" python3 -c '
import json,sys,os,importlib.util
try:
  p=json.load(sys.stdin)["result"]["pane"]
except Exception:
  raise SystemExit(0)
lib=os.environ.get("LAYOUT_LIB","")
snip=os.environ.get("SIDEBAR_SNIP","")
tid=os.environ.get("TID","")
try:
  spec=importlib.util.spec_from_file_location("layout_lib", lib)
  L=importlib.util.module_from_spec(spec); spec.loader.exec_module(L)
  dk=L.discover_dyn_title_kinds(snip) if snip else frozenset()
  pid=p.get("pane_id") or ""
  pm={pid: tid} if pid and tid else {}
  d=L.want_dyn_title(p, dyn_kinds=dk, parallel_by_pane=pm)
  if d is None: raise SystemExit(0)
  print((d or "")[:80], end="")
except Exception:
  pass
' 2>/dev/null) || true
  cur=$(herdr pane get "$pane" 2>/dev/null | jq -r '.result.pane.tokens.dyn_title // empty' 2>/dev/null || true)
  if [ -n "$want" ] && [ "$want" != "$cur" ]; then
    herdr pane report-metadata "$pane" --source skill:par \
      --token "dyn_title=${want}" >/dev/null 2>&1 || true
  elif [ -z "$want" ] && [ -n "$cur" ]; then
    herdr pane report-metadata "$pane" --source skill:par \
      --clear-token dyn_title >/dev/null 2>&1 || true
  fi
  return 0
}

# 单切片: 刷 dyn → 读 token → agent wait 唤醒 → 再读 token
# agent wait 超时/失败不直接判失败；token 未到才 waiting
# wait 切片上限 PAR_DYN_SLICE_MS（默认 15s）以便状态变化后及时刷行2
par_await_sentinel_once() {
  local tmo=$1 pane=$2 tid=$3 attempt=$4 r slice
  par_refresh_dyn_title "$pane" "$tid" || true
  r=$(_par_report_token "$pane" "$tid" "$attempt")
  [ "$r" != waiting ] && { echo "$r"; return; }
  slice=${PAR_DYN_SLICE_MS:-15000}
  [ "$tmo" -gt "$slice" ] 2>/dev/null && tmo=$slice
  # 唤醒：状态变化时尽快返回再 poll token（done 态会立即返回）
  herdr agent wait "$pane" --until idle --until done --until blocked --timeout "$tmo" >/dev/null 2>&1 || true
  par_refresh_dyn_title "$pane" "$tid" || true
  r=$(_par_report_token "$pane" "$tid" "$attempt")
  [ "$r" = waiting ] && sleep 1
  echo "$r"
}

# 多切片等到 token 锚定或总超时
par_await_sentinel() {
  local total=$1 pane=$2 tid=$3 attempt=$4 rem r start
  start=$(date +%s)
  while :; do
    rem=$(( total - ($(date +%s) - start) * 1000 ))
    [ "$rem" -le 0 ] && { echo timeout; return; }
    [ "$rem" -gt 60000 ] && rem=60000
    r=$(par_await_sentinel_once "$rem" "$pane" "$tid" "$attempt")
    [ "$r" != waiting ] && { echo "$r"; return; }
  done
}

# 记录 artifact 基线（size:mtime:inode）；launch / attempt+1 时调用
par_artifact_baseline_write() {
  local td=$1 f="$1/artifact.md" bl="$1/artifact.baseline"
  if [ -f "$f" ]; then
    stat -c '%s:%Y:%i' "$f" > "$bl" 2>/dev/null || echo "0:0:0" > "$bl"
  else
    echo "0:0:0" > "$bl"
  fi
}

# 交付硬门禁（token 之后仍要过）：artifact 非空 + 相对基线已更新（本轮新写）
# 第 4 参 mode=review 时追加结构 lint：P0/P1 模板五节固定标题缺一不收（模板写死，P-1）
par_delivery_met() {
  local td=$1 need=$2 base=$3 mode=${4:-}
  local bl cur
  [ -s "$td/artifact.md" ] || return 1
  bl=$(cat "$td/artifact.baseline" 2>/dev/null || echo "0:0:0")
  cur=$(stat -c '%s:%Y:%i' "$td/artifact.md" 2>/dev/null || true)
  [ -n "$cur" ] || return 1
  # 与 launch 时基线相同 → 旧产物，不算本轮交付
  [ "$cur" != "$bl" ] || return 1
  if [ "$need" = 1 ]; then
    [ -n "$base" ] || return 1
    [ -n "$(git -C "$td/wt" rev-list "${base}..HEAD" 2>/dev/null | head -1)" ] || return 1
  fi
  # 结构 lint（模板写死，P-1/P-2）：review 五节 / research 三节，缺一不收
  local -a secs=()
  case "$mode" in
    review)   secs=('## 结论' '## P0' '## P1' '## 存疑' '## 证据') ;;
    research) secs=('## 结论' '## 证据' '## 存疑') ;;
  esac
  local s
  for s in ${secs[@]+"${secs[@]}"}; do
    grep -q "^$s" "$td/artifact.md" || return 1
  done
  return 0
}

# par_finish <tid> <timeout-min>
# 唯一完成真源: tokens.par_result 锚定 tid#attempt + 非空结论 → 交付校验 → state
# 无 token 永不 done（timeout/blocked/stalled）；禁 sentinel-missing→done
par_finish() {
  local tid=$1 tmo=${2:-15}
  local td="$PWD/.parallel/$tid" pane mode attempt base need r r2
  pane=$(cat "$td/pane" 2>/dev/null) || { err "$td/pane 缺失(先 launch)"; return 1; }
  mode=$(sed -n 's/^mode=//p' "$td/meta" 2>/dev/null); mode=${mode:-research}
  attempt=$(sed -n 's/^attempt=//p' "$td/meta" 2>/dev/null); attempt=${attempt:-1}
  base=$(sed -n 's/^base=//p' "$td/meta" 2>/dev/null)
  need=0; [ "$mode" = develop ] && need=1
  # 无基线时补写（兼容旧 launch）
  [ -f "$td/artifact.baseline" ] || par_artifact_baseline_write "$td"

  local slice_ms=$(( ${PAR_SLICE_SECS:-60} * 1000 )) rem
  local start=$(date +%s)
  local deadline=$(( start + tmo * 60 ))
  local rawtok=""
  r=waiting
  while [ "$r" = waiting ]; do
    [ "$(date +%s)" -ge "$deadline" ] && { r=timeout; break; }
    rem=$(( (deadline - $(date +%s)) * 1000 )); [ "$rem" -gt "$slice_ms" ] && rem=$slice_ms
    # 唯一真源：metadata token（agent idle/done 不升格为完成）
    r=$(par_await_sentinel_once "$rem" "$pane" "$tid" "$attempt")
    [ "$r" != waiting ] && break
  done

  rawtok=$(_par_raw_token "$pane")

  # token=done 但交付未齐：grace 等交付，否则质问要求新 attempt token
  if [ "$r" = done ] && ! par_delivery_met "$td" "$need" "$base" "$mode"; then
    local gmax=$(( tmo * 60 / 2 )) cap=${PAR_GRACE_MAX:-60} gstart=$(date +%s)
    [ "$gmax" -gt "$cap" ] && gmax=$cap; [ "$gmax" -lt 3 ] && gmax=3
    while [ $(( $(date +%s) - gstart )) -lt "$gmax" ]; do
      sleep 3
      par_delivery_met "$td" "$need" "$base" "$mode" && break
    done
  fi
  if [ "$r" = done ] && ! par_delivery_met "$td" "$need" "$base" "$mode"; then
    local attempt2=$(( attempt + 1 ))
    # 清旧 token 再质问，强制新上报；重设 artifact 基线（本 attempt 旧产物不算）
    par_clear_result_token "$pane"
    par_artifact_baseline_write "$td"
    par_dispatch_msg "$pane" "你已 report-metadata $(par_meta_key)，但交付信号缺失(artifact.md 本轮新写$([ $need = 1 ] && echo '+worktree 新 commit'))。补齐后重新: $(par_token_done_cmd '${HERDR_PANE_ID}' "$tid" "$attempt2" '<结论>')（attempt 必须 $attempt2）。" >/dev/null
    sed -i "s/^attempt=.*/attempt=$attempt2/" "$td/meta"
    r2=$(par_await_sentinel $((tmo * 60000 / 2)) "$pane" "$tid" "$attempt2")
    if [ "$r2" = done ]; then
      local gmax2=${PAR_GRACE_MAX:-60} gstart2=$(date +%s)
      while [ $(( $(date +%s) - gstart2 )) -lt "$gmax2" ]; do
        par_delivery_met "$td" "$need" "$base" "$mode" && break
        sleep 3
      done
    fi
    if [ "$r2" = done ] && par_delivery_met "$td" "$need" "$base" "$mode"; then r=done; else r=stalled; fi
    rawtok=$(_par_raw_token "$pane")
  fi
  case "$r" in
    done)    echo done > "$td/state" ;;
    blocked) echo blocked > "$td/state" ;;
    stalled) echo stalled > "$td/state" ;;
    *)       echo timeout > "$td/state" ;;
  esac
  if [ ! -s "$td/.await" ]; then
    printf '%s %s token=%s\n' "$pane" "$r" "${rawtok:--}" > "$td/.await"
  fi
  # 收割后关任务窗（默认开；PAR_CLOSE_PANE=0 保留）
  local layout; layout=$(sed -n 's/^layout=//p' "$td/meta" 2>/dev/null); layout=${layout:-tab}
  par_close_task_pane "$pane" "$layout"
  cat "$td/state"
}
