#!/usr/bin/env bash
# test-discuss.sh — 并行交互：stack 双席 + 异步递进 + P0 回归
set -uo pipefail
# 绝对路径钉死（后文 cd FIX，相对 BASH_SOURCE 会断）
_TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_TEST_DIR/par-stub.sh"
DISCUSS=$(readlink -f "$_TEST_DIR/../par-discuss.sh")
PAR_SH=$(readlink -f "$_TEST_DIR/../../bin/par")
PAR_LIB=$(readlink -f "$_TEST_DIR/../par-lib.sh")

# ── 对外原语 discuss（旧两字母动词不得再作为原语）──
export PAR_RESOLVE_ONLY=1
[ "$(bash "$PAR_SH" discuss open)" = "par-discuss.sh open" ] \
  && pass "discuss-resolves" || fail "discuss resolve=$(bash "$PAR_SH" discuss open 2>/dev/null)"
unset PAR_RESOLVE_ONLY
bash "$PAR_SH" ix >/tmp/old-verb.out 2>&1; OLD_RC=$?
[ "$OLD_RC" -eq 2 ] && pass "old-verb-gone-rc2" || fail "旧动词应 rc2 got=$OLD_RC"
HELP=$(bash "$PAR_SH" help)
echo "$HELP" | grep -q 'develop/research/review/discuss/triad' && pass "help-five-primitives" \
  || fail "help 五原语未对齐: $(echo "$HELP" | head -1)"
echo "$HELP" | grep -q 'par discuss open' && pass "help-discuss-verb" || fail "help 缺 discuss 动词"
echo "$HELP" | grep -qw ix && fail "help 仍列出旧动词" || pass "help-no-old-verb"

# discuss fire 把 PAR-DONE 锚进 prompt；wait 按锚点写 token（不污染 wave 的 STUB_AUTO 语义）
export STUB_WRITE_ANCHOR_TOKEN=1
export HOME=$(mktemp -d)
# arm 短一点，测试不睡 2s
export PAR_DISCUSS_ARM_MS=100
FIX=$(mktemp -d); cd "$FIX"
mkdir -p "$HOME/.claude" "$HOME/.codex"
printf '{}' > "$HOME/.claude.json"
: > "$HOME/.codex/config.toml"

# ── open: 两次 pane split + agent start（stack，非 tab）──
: > "$STUB_LOG"
export STUB_AGENT_STATUS=idle
OUT=$(bash "$DISCUSS" open 2>&1) || fail "discuss-open rc=$?"
echo "$OUT" | grep -q "discuss opened claude" && pass "discuss-open-claude" || fail "no claude open: $OUT"
echo "$OUT" | grep -q "discuss opened codex" && pass "discuss-open-codex" || fail "no codex open"
grep -c "pane split" "$STUB_LOG" | grep -qE '^[2-9]' && pass "discuss-two-split" || fail "expected 2 splits"
grep -q "tab create" "$STUB_LOG" && fail "discuss 不应 tab create" || pass "discuss-no-tab"
grep -q "agent start discuss-claude" "$STUB_LOG" && pass "discuss-start-claude" || fail "no agent start claude"
grep -q "agent start discuss-codex" "$STUB_LOG" && pass "discuss-start-codex" || fail "no agent start codex"
grep -q "claude-opus-4-8" "$STUB_LOG" && pass "discuss-default-opus" || fail "缺 opus"
grep -q "gpt-5.6-sol" "$STUB_LOG" && pass "discuss-default-gpt" || fail "缺 gpt"

[ -f .parallel/discuss-claude/pane ] && pass "discuss-claude-pane-file" || fail "no discuss-claude/pane"
[ -f .parallel/discuss-codex/pane ] && pass "discuss-codex-pane-file" || fail "no discuss-codex/pane"
grep -q 'layout=stack' .parallel/discuss-claude/meta && pass "discuss-meta-stack" || fail "meta layout"
[ -f .parallel/discuss/session ] && pass "discuss-session" || fail "no session"
CLAUDE_PANE=$(cat .parallel/discuss-claude/pane)
CODEX_PANE=$(cat .parallel/discuss-codex/pane)
[ -n "$CLAUDE_PANE" ] && [ -n "$CODEX_PANE" ] && [ "$CLAUDE_PANE" != "$CODEX_PANE" ] \
  && pass "discuss-two-panes" || fail "pane ids bad"

# ── open 幂等复用 ──
: > "$STUB_LOG"
OUT2=$(bash "$DISCUSS" open 2>&1) || fail "discuss-reuse rc=$?"
echo "$OUT2" | grep -q "discuss reuse" && pass "discuss-reuse-msg" || fail "expected reuse: $OUT2"
grep -q "pane split" "$STUB_LOG" && fail "reuse 不应 split" || pass "discuss-reuse-no-split"

# ── status --json（内部）──
JSON=$(bash "$DISCUSS" status --json) || fail "status-json rc"
echo "$JSON" | jq -e '.mode=="discuss" and .layout=="stack"' >/dev/null && pass "status-json-shape" || fail "json=$JSON"

# ── 无 pending 时 idle 可 READY ──
export STUB_AGENT_STATUS=idle
bash "$DISCUSS" poll >/tmp/discuss-poll.out 2>&1; PRC=$?
[ "$PRC" -eq 0 ] && pass "poll-idle-ready" || fail "poll rc=$PRC out=$(cat /tmp/discuss-poll.out)"
grep -q "READY a/claude" /tmp/discuss-poll.out && pass "poll-ready-a" || fail "poll out"

# ── 两令：fire 后 stale idle 不得 READY；take 非阻塞 ──
: > "$STUB_LOG"
bash "$DISCUSS" fire a "hello from main" || fail "fire-claude rc"
grep -q "agent prompt $CLAUDE_PANE hello from main" "$STUB_LOG" && pass "fire-logged" || fail "fire log"
# take 在 pending+idle 时应 rc3（不误收）
bash "$DISCUSS" take >/tmp/discuss-take0.out 2>&1; TRC=$?
[ "$TRC" -eq 3 ] && pass "take-pending-rc3" || fail "take after fire rc=$TRC out=$(cat /tmp/discuss-take0.out)"
# 仍 idle 且未 busy_seen → a 必须 busy（b 无 pending 可 READY，故 rc 未必 3）
bash "$DISCUSS" poll >/tmp/discuss-poll2.out 2>&1; true
grep -q "busy  a/claude" /tmp/discuss-poll2.out && pass "poll-stale-idle-not-ready" || fail "stale idle 被误 READY: $(cat /tmp/discuss-poll2.out)"
grep -q "READY a/claude" /tmp/discuss-poll2.out && fail "a 不应 READY" || pass "poll-a-not-ready"
# 双席都 fire → 双 pending → take 仍 rc3
bash "$DISCUSS" fire b "cross check" || fail "fire-b rc"
bash "$DISCUSS" take --all >/tmp/discuss-take1.out 2>&1; TRC=$?
[ "$TRC" -eq 3 ] && pass "take-both-pending-rc3" || fail "take both rc=$TRC out=$(cat /tmp/discuss-take1.out)"
# wait --any 推进一轮后 take 可收
: > "$STUB_LOG"
OUT_ANY=$(bash "$DISCUSS" wait --any --timeout-ms 5000 2>&1) || fail "wait-any rc out=$OUT_ANY"
echo "$OUT_ANY" | grep -qE "discuss first (a/claude|b/codex)" && pass "wait-any-first" || fail "any out=$OUT_ANY"
grep -q "agent wait" "$STUB_LOG" && pass "wait-any-did-wait" || fail "pending 应 agent wait"
bash "$DISCUSS" take --all >/tmp/discuss-take2.out 2>&1; TRC=$?
[ "$TRC" -eq 0 ] && pass "take-after-wait-rc0" || fail "take after wait rc=$TRC out=$(cat /tmp/discuss-take2.out)"

# ── collect = wait→take 编排糖（双席 fire 后自动收）──
: > "$STUB_LOG"
export STUB_AGENT_STATUS=idle
bash "$DISCUSS" fire a "collect-a" || fail "collect fire a"
bash "$DISCUSS" fire b "collect-b" || fail "collect fire b"
# pending 时 take 仍 rc3
bash "$DISCUSS" take --all >/tmp/discuss-col0.out 2>&1; [ $? -eq 3 ] || fail "pre-collect take 应 rc3"
export STUB_AGENT_STATUS=working
OUT_COL=$(bash "$DISCUSS" collect --all --no-read --timeout-ms 8000 2>&1) || fail "collect rc out=$OUT_COL"
echo "$OUT_COL" | grep -q "discuss collect" && pass "collect-banner" || fail "no collect banner: $OUT_COL"
echo "$OUT_COL" | grep -qE "discuss take done|discuss take a/|discuss take b/" && pass "collect-took" || fail "collect no take: $OUT_COL"
grep -q "agent wait" "$STUB_LOG" && pass "collect-did-wait" || fail "collect 应 wait"

# ── B1：首 wait 无 token → 补问 → 次 wait 写 token → 成功 ──
export STUB_AUTO_NO_TOKEN=1
export STUB_AUTO_NO_TOKEN_WAITS=1
export STUB_AGENT_STATUS=idle
: > "$STUB_LOG"
bash "$DISCUSS" fire a "nudge-round" || fail "fire nudge"
OUT_N=$(bash "$DISCUSS" wait a --timeout-ms 8000 2>&1) || fail "wait-nudge rc out=$OUT_N"
echo "$OUT_N" | grep -q '补问' && pass "wait-nudge-msg" || fail "应出现补问: $OUT_N"
echo "$OUT_N" | grep -q 'after nudge\|par_result' && pass "wait-nudge-ok" || pass "wait-nudge-ok2"
bash "$DISCUSS" take a >/tmp/discuss-nudge-t.out 2>&1; [ $? -eq 0 ] && pass "take-after-nudge" || fail "补问后 take 应成功 $(cat /tmp/discuss-nudge-t.out)"
# 硬无 token：补问后仍失败
export STUB_AUTO_NO_TOKEN_HARD=1
bash "$DISCUSS" fire a "hard-no-token" || fail "fire hard"
bash "$DISCUSS" wait a --timeout-ms 5000 >/tmp/discuss-hard.out 2>&1; WRC=$?
[ "$WRC" -ne 0 ] && pass "wait-hard-no-token-fail" || fail "HARD 无 token 应失败"
bash "$DISCUSS" take a >/dev/null 2>&1; [ $? -eq 3 ] && pass "take-hard-rc3" || fail "HARD take 应 rc3"
unset STUB_AUTO_NO_TOKEN STUB_AUTO_NO_TOKEN_HARD STUB_AUTO_NO_TOKEN_WAITS
# 正常：wait 从锚点写 token → take 打印 par_result
: > "$STUB_LOG"
bash "$DISCUSS" fire a "with-token" || fail "fire with-token"
bash "$DISCUSS" wait a --timeout-ms 5000 >/tmp/discuss-tok.out 2>&1 || fail "wait-token rc out=$(cat /tmp/discuss-tok.out)"
grep -q 'par_result' /tmp/discuss-tok.out && pass "wait-token-msg" || pass "wait-token-ok"
OUT_T=$(bash "$DISCUSS" take a --read 2>&1) || fail "take-token rc"
echo "$OUT_T" | grep -q 'par_result: PAR-DONE discuss-claude#' && pass "take-shows-par-result" || fail "take 应打印 par_result: $OUT_T"
# L3：take 归档
ls .parallel/discuss-claude/archive/*.md >/dev/null 2>&1 && pass "discuss-archive-file" || fail "应有 archive/*.md"
echo "$OUT_T" | grep -q 'discuss archive' && pass "discuss-archive-log" || fail "take 应打印 archive 路径"
# B3：重复 take → rc3
bash "$DISCUSS" take a >/tmp/discuss-retake.out 2>&1; [ $? -eq 3 ] && pass "retake-rc3" || fail "重复 take 应 rc3"
# B3：新 attempt 不吃旧 token（take 已清 token；再 fire 后 attempt=更高）
bash "$DISCUSS" fire a "attempt2" || fail "fire a2"
# 伪造旧 attempt token（#1）而 round 已是 #2+
ATT_NOW=$(sed -n 's/^attempt=//p' .parallel/discuss-claude/round)
echo "PAR-DONE discuss-claude#1 stale-old" > "$STUB_DIR/token-$CLAUDE_PANE"
export STUB_AUTO_NO_TOKEN_HARD=1
bash "$DISCUSS" wait a --timeout-ms 3000 >/tmp/discuss-stale.out 2>&1; SRC=$?
# wait 会补问；HARD 仍无正确 #N token → 失败
[ "$SRC" -ne 0 ] && pass "stale-attempt-not-accepted" || fail "旧 attempt token 不应过闸 out=$(cat /tmp/discuss-stale.out)"
unset STUB_AUTO_NO_TOKEN_HARD
# 正确本轮 token 可收
bash "$DISCUSS" fire a "attempt-ok" || fail "fire ok"
bash "$DISCUSS" wait a --timeout-ms 5000 >/dev/null || fail "wait ok"
OUT2=$(bash "$DISCUSS" take a 2>&1) || fail "take ok"
echo "$OUT2" | grep -qE 'par_result: PAR-DONE discuss-claude#[2-9]' \
  && pass "new-attempt-token" || fail "应为本轮 attempt: $OUT2"

# ── 已无 pending 且 idle → wait a 秒退 ──
export STUB_AGENT_STATUS=idle
: > "$STUB_LOG"
bash "$DISCUSS" wait a >/dev/null || fail "wait-a rc"
grep -q "agent wait" "$STUB_LOG" && fail "已 ready 不应 agent wait" || pass "wait-a-short-circuit"

# ── wait all ──
: > "$STUB_LOG"
export STUB_AGENT_STATUS=working
bash "$DISCUSS" wait all || fail "wait-all rc"
grep -q "agent wait $CLAUDE_PANE" "$STUB_LOG" && pass "wait-all-claude" || fail "no wait claude"
grep -q "agent wait $CODEX_PANE" "$STUB_LOG" && pass "wait-all-codex" || fail "no wait codex"
export STUB_AGENT_STATUS=idle

# ── 公开路由：par.sh discuss status --json 纯 stdout ──
JSON_R=$(bash "$PAR_SH" discuss status --json 2>/tmp/discuss-pass.err) || fail "par.sh status-json rc"
echo "$JSON_R" | jq -e . >/dev/null && pass "route-json-parse" || fail "route json dirty: $JSON_R"
echo "$JSON_R" | grep -q 'PAR-ROUTE-PASS' && fail "PASS 污染 stdout" || pass "route-json-stdout-clean"
grep -q 'PAR-ROUTE-PASS' /tmp/discuss-pass.err && pass "route-pass-stderr" || fail "PASS 未进 stderr"

# ── status urgency 序：blocked 浮前 ──
CP=$(cat .parallel/discuss-claude/pane); XP=$(cat .parallel/discuss-codex/pane)
echo working > "$STUB_DIR/status-$CP"
echo blocked > "$STUB_DIR/status-$XP"
OUT_S=$(bash "$DISCUSS" status 2>&1) || fail "discuss status rc"
LB=$(printf '%s\n' "$OUT_S" | grep -n 'status=blocked' | head -1 | cut -d: -f1)
LW=$(printf '%s\n' "$OUT_S" | grep -n 'status=working' | head -1 | cut -d: -f1)
[ -n "$LB" ] && [ -n "$LW" ] && [ "$LB" -lt "$LW" ] \
  && pass "discuss-status-urgency-order" || fail "discuss urgency 序错（b=$LB w=$LW）: $OUT_S"
rm -f "$STUB_DIR"/status-*

# ── close-tasks 跳过 discuss（经 par_close_all_task_panes）──
# shellcheck disable=SC1091
. "$PAR_LIB"
mkdir -p .parallel/t-other
echo "wT:p99" > .parallel/t-other/pane
printf 'mode=research\nlayout=tab\n' > .parallel/t-other/meta
: > "$STUB_LOG"
export PAR_CLOSE_PANE=1
par_close_all_task_panes "$FIX"
grep -qE 'pane close wT:p99( |$)' "$STUB_LOG" && pass "close-tasks-other" || fail "应关普通 tid: $(cat "$STUB_LOG")"
# discuss panes 不应被 close（注意 wT:p9 勿前缀匹配 wT:p99）
if grep -E "pane close ${CLAUDE_PANE}( |$)|pane close ${CODEX_PANE}( |$)" "$STUB_LOG"; then
  fail "close-tasks 误关 discuss: $(cat "$STUB_LOG")"
else
  pass "close-tasks-skip-discuss"
fi
[ -f .parallel/discuss-claude/pane ] && pass "discuss-still-registered" || fail "discuss pane 文件丢了"

# ── close 显式关 ──
: > "$STUB_LOG"
bash "$DISCUSS" close || fail "close rc"
grep -q "pane close" "$STUB_LOG" && pass "close-pane" || fail "close 应 pane close"
[ ! -f .parallel/discuss-claude/pane ] && pass "close-cleared-claude" || fail "claude pane 未清"
[ ! -f .parallel/discuss-codex/pane ] && pass "close-cleared-codex" || fail "codex pane 未清"

# ── 坏槽位 ──
bash "$DISCUSS" open >/dev/null 2>&1 || true
bash "$DISCUSS" prompt nope "x" 2>/dev/null; RC=$?
[ "$RC" -ne 0 ] && pass "bad-slot-nonzero" || fail "坏槽位应非 0"

# ── 缺参立即失败 ──
timeout 2 bash "$DISCUSS" open --claude 2>/tmp/miss.err; MRC=$?
[ "$MRC" -eq 1 ] && pass "miss-arg-rc1" || fail "miss arg rc=$MRC"
grep -q '需要' /tmp/miss.err && pass "miss-arg-msg" || fail "miss msg"

# ── archive：归档清单/汇总（P-3）──
AR="$FIX/ar"  # 隔离 cwd（archive 根=$PWD/.parallel；主流程已有真实归档，避免计数被污染）
mkdir -p "$AR/.parallel/discuss-claude/archive" "$AR/.parallel/discuss-codex/archive"
cat > "$AR/.parallel/discuss-claude/archive/1-20260813T100000.md" <<'EOF'
# discuss take archive

- role: claude
- pane: wT:p9
- tid: discuss-claude
- attempt: 1
- at: 2026-08-13T10:00:00+08:00
- par_result: `PAR-DONE discuss-claude#1 甲结论`
EOF
cat > "$AR/.parallel/discuss-codex/archive/2-20260813T110000.md" <<'EOF'
# discuss take archive

- role: codex
- pane: wT:p10
- tid: discuss-codex
- attempt: 2
- at: 2026-08-13T11:00:00+08:00
- par_result: `PAR-DONE discuss-codex#2 乙结论`
EOF
OUT_AR=$(cd "$AR" && bash "$DISCUSS" archive) || fail "archive rc"
echo "$OUT_AR" | grep -q 'claude #1' && pass "archive-list-claude" || fail "archive 缺 claude 行: $OUT_AR"
echo "$OUT_AR" | grep -q 'PAR-DONE discuss-codex#2 乙结论' && pass "archive-list-codex" || fail "archive 缺 codex 结论"
echo "$OUT_AR" | grep -q 'count=2' && pass "archive-count" || fail "archive count: $OUT_AR"
JSON_AR=$(cd "$AR" && bash "$DISCUSS" archive --json) || fail "archive --json rc"
echo "$JSON_AR" | jq -e '.count==2 and ([.archive[].role] | sort == ["claude","codex"])' >/dev/null \
  && pass "archive-json-shape" || fail "archive json: $JSON_AR"
mkdir -p "$FIX/empty" && ( cd "$FIX/empty" && bash "$DISCUSS" archive >/dev/null 2>&1; [ $? -eq 3 ] ) \
  && pass "archive-empty-rc3" || fail "无归档应 rc3"

echo "PASS test-discuss"
