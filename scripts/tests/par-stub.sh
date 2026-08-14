# par-stub.sh — 测试接缝:PATH 注入假 herdr/jq 真实;记录调用、按场景应答
# 用法: . tests/par-stub.sh; 设 STUB_* 变量
# state 协议接缝:agent wait(rc/side-effect)+ pane get(tokens.par_result);
# pane 编号: tab create / pane split 共用计数(首个 wT:p9)
# agent prompt 从文本提取 PAR-DONE <tid>#<att> 锚点存 per-pane
STUB_DIR=$(mktemp -d)
STUB_LOG="$STUB_DIR/herdr-calls.log"
: > "$STUB_LOG"
# 场景变量(由测试设置)
STUB_TOKEN=""             # pane get 返回的 tokens.par_result(per-pane token 文件优先)
STUB_ON_AGENT_WAIT=""     # agent wait 时执行的副作用命令(如写 artifact)
STUB_AUTO=0               # 1=agent wait 自动按锚点写 token(PAR-DONE <tid>#<att> ok)
STUB_ON_AGENT_WAIT_AUTO="" # AUTO 模式副作用,可用 \$TID/\$ATT/\$PANE
STUB_AUTO_NO_TOKEN=0      # 1=AUTO 模式不写默认 token(模拟上报缺席)
STUB_WAIT_FAIL=0          # 1=agent wait 恒失败(超时/agent_not_found)
STUB_WAIT_SECS=0          # agent wait 失败前 sleep 秒数
STUB_AGENT_STATUS=idle    # agent get 返回的 agent_status
STUB_START_FAIL=0         # agent start 恒失败
cat > "$STUB_DIR/herdr" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
cmd=$1; shift
_next_pane() {
  n=$(( $(cat "$STUB_DIR/panenum" 2>/dev/null || echo 8) + 1 )); echo "$n" > "$STUB_DIR/panenum"
  echo "$n"
}
case "$cmd $1" in
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"wT","focused":true}]}}' ;;
  "tab create")
    n=$(_next_pane)
    printf '{"result":{"tab":{"tab_id":"wT:t%d"},"root_pane":{"pane_id":"wT:p%d","tab_id":"wT:t%d"}}}\n' "$((n-8))" "$n" "$((n-8))" ;;
  "pane layout")
    # 主栏 + 可选右柱(已有 split 数记在 stackn)
    sn=$(cat "$STUB_DIR/stackn" 2>/dev/null || echo 0)
    if [ "$sn" = 0 ]; then
      echo '{"result":{"layout":{"panes":[{"pane_id":"wT:p1","focused":true,"rect":{"x":0,"y":0,"width":100,"height":50}}]}}}'
    else
      # 简化:主 + 最底右
      printf '{"result":{"layout":{"panes":[{"pane_id":"wT:p1","focused":true,"rect":{"x":0,"y":0,"width":50,"height":50}},{"pane_id":"wT:p%d","focused":false,"rect":{"x":50,"y":%d,"width":50,"height":25}}]}}}\n' "$((8+sn))" "$((sn*10))"
    fi ;;
  "pane split")
    n=$(_next_pane)
    sn=$(( $(cat "$STUB_DIR/stackn" 2>/dev/null || echo 0) + 1 )); echo "$sn" > "$STUB_DIR/stackn"
    printf '{"result":{"pane":{"pane_id":"wT:p%d"}}}\n' "$n" ;;
  "pane rename"|"pane close"|"tab close"|"pane report-agent"|"agent rename") : ;;
  "pane report-metadata")
    # clear-token / --token par_result=…；pane id 含 :
    pane=""; tokv=""
    for a in "$@"; do
      case "$a" in
        --clear-token) ;;
        --token) ;;
        --source) ;;
        parallel|par_result) ;;
        wT:*|*:*) pane=$a ;;
        par_result=*) tokv=${a#par_result=} ;;
        *=*)
          # --token 的下一参常是 key=value
          case "$a" in par_result=*|*=*) 
            k=${a%%=*}; v=${a#*=}
            [ "$k" = "par_result" ] && tokv=$v
          ;; esac
          ;;
      esac
    done
    # 也扫 --token 后的整段
    prev=""
    for a in "$@"; do
      if [ "$prev" = "--token" ]; then
        case "$a" in
          par_result=*) tokv=${a#par_result=} ;;
        esac
      fi
      prev=$a
      case "$a" in wT:*|*:*) pane=$a ;; esac
    done
    if [[ "$*" == *"--clear-token"* ]] && [ -n "$pane" ]; then
      rm -f "$STUB_DIR/token-$pane"
    elif [ -n "$pane" ] && [ -n "$tokv" ]; then
      printf '%s' "$tokv" > "$STUB_DIR/token-$pane"
    fi
    echo '{"result":{"type":"ok"}}' ;;
  "agent start")    [ "${STUB_START_FAIL:-0}" = 1 ] && exit 1; echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent prompt")
    # fire 主消息重置 wait 计数；补问不重置（让第 2 次 wait 写出 token）
    if [[ "$*" == *"完成上报·必须"* ]] && [[ "$*" != *"补问"* ]]; then
      rm -f "$STUB_DIR/waitc-$2"
    fi
    # 从消息提取 PAR-DONE tid#att 锚点（ix fire 会嵌入完成上报指令）
    if [[ "$*" =~ PAR-DONE[[:space:]]+([A-Za-z0-9_-]+)#([0-9]+) ]]; then
      echo "${BASH_REMATCH[1]}#${BASH_REMATCH[2]}" > "$STUB_DIR/anchor-$2"
    fi
    echo '{"result":{"type":"agent_prompted"}}' ;;
  "agent get")
    # per-pane 覆盖：$STUB_DIR/status-<pane> 优先于全局 STUB_AGENT_STATUS
    pane=$2
    if [ -f "$STUB_DIR/status-$pane" ]; then st=$(cat "$STUB_DIR/status-$pane"); else st=${STUB_AGENT_STATUS:-idle}; fi
    printf '{"result":{"agent":{"agent":"pi","agent_status":"%s"}}}\n' "$st" ;;
  "agent wait")
    pane=$2
    [ "${STUB_WAIT_FAIL:-0}" = 1 ] && { sleep "${STUB_WAIT_SECS:-0}"; exit 1; }
    [ -n "${STUB_ON_AGENT_WAIT:-}" ] && eval "$STUB_ON_AGENT_WAIT"
    # 写 par_result：STUB_AUTO=1（wave 交付测）或 STUB_WRITE_ANCHOR_TOKEN=1（ix 测）
    # STUB_AUTO_NO_TOKEN=1：前 N 次 wait 不写（补问测）；HARD=始终不写
    anchor=$(cat "$STUB_DIR/anchor-$pane" 2>/dev/null || true)
    wc=$(( $(cat "$STUB_DIR/waitc-$pane" 2>/dev/null || echo 0) + 1 ))
    echo "$wc" > "$STUB_DIR/waitc-$pane"
    _write_tok=0
    if [ "${STUB_AUTO:-0}" = 1 ] || [ "${STUB_WRITE_ANCHOR_TOKEN:-0}" = 1 ]; then
      _write_tok=1
    fi
    if [ "${STUB_AUTO_NO_TOKEN_HARD:-0}" = 1 ]; then
      _write_tok=0
    elif [ "${STUB_AUTO_NO_TOKEN:-0}" = 1 ] && [ "$wc" -le "${STUB_AUTO_NO_TOKEN_WAITS:-1}" ]; then
      _write_tok=0
    fi
    if [ "${STUB_AUTO:-0}" = 1 ]; then
      TID=${anchor%#*}; ATT=${anchor#*#}; TID=${TID:-t}; ATT=${ATT:-1}
      PANE=$pane; export TID ATT PANE
      [ -n "${STUB_ON_AGENT_WAIT_AUTO:-}" ] && eval "$STUB_ON_AGENT_WAIT_AUTO"
    fi
    if [ -n "$anchor" ] && [ "$_write_tok" = 1 ]; then
      TID=${anchor%#*}; ATT=${anchor#*#}; TID=${TID:-t}; ATT=${ATT:-1}
      printf 'PAR-DONE %s#%s ok' "$TID" "$ATT" > "$STUB_DIR/token-$pane"
    fi
    echo '{"result":{"agent":{"agent_status":"done"}}}'; exit 0 ;;
  "pane get")
    pane=$2; tok=""
    [ -f "$STUB_DIR/token-$pane" ] && tok=$(cat "$STUB_DIR/token-$pane")
    [ -z "$tok" ] && tok=${STUB_TOKEN:-}
    # token 优先路径下 agent wait 可能不跑：首次 pane get 带 token 时触发副作用（写 artifact）
    if [ -n "$tok" ] && [ -n "${STUB_ON_AGENT_WAIT:-}" ] && [ ! -f "$STUB_DIR/side-$pane" ]; then
      touch "$STUB_DIR/side-$pane"
      eval "$STUB_ON_AGENT_WAIT" || true
    fi
    if [ -n "$tok" ]; then
      printf '{"result":{"pane":{"tokens":{"par_result":"%s"}}}}\n' "$tok"
    else
      echo '{"result":{"pane":{"tokens":{}}}}'
    fi ;;
  "pane wait-output") exit 1 ;;
  *) echo '{"result":{}}' ;;
esac
EOF
chmod +x "$STUB_DIR/herdr"
export STUB_DIR STUB_LOG
export PATH="$STUB_DIR:$PATH"
export HERDR_ENV=1
unset HERDR_WORKSPACE_ID   # 隔离外层真实 herdr 会话,保证 par_ws 走 stub 的 workspace list
export STUB_TOKEN STUB_ON_AGENT_WAIT STUB_AUTO STUB_ON_AGENT_WAIT_AUTO STUB_AUTO_NO_TOKEN \
       STUB_AUTO_NO_TOKEN_HARD STUB_AUTO_NO_TOKEN_WAITS STUB_WRITE_ANCHOR_TOKEN \
       STUB_WAIT_FAIL STUB_WAIT_SECS STUB_AGENT_STATUS STUB_START_FAIL
stub_herdr_scenario() { :; }   # 各测试直接设 STUB_* 变量
pass() { echo "ok: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }
