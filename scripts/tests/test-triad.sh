#!/usr/bin/env bash
# test-triad.sh — 三席原语：stack 三席 + 首席 fire + 协议尾 + token 收割
set -uo pipefail
_TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_TEST_DIR/par-stub.sh"
TRIAD=$(readlink -f "$_TEST_DIR/../par-triad.sh")
PAR_SH=$(readlink -f "$_TEST_DIR/../../bin/par")
PAR_LIB=$(readlink -f "$_TEST_DIR/../par-lib.sh")
# fire 把 PAR-DONE 锚进 prompt；wait 按锚点写 token
export STUB_WRITE_ANCHOR_TOKEN=1
export HOME=$(mktemp -d)
export PAR_TRIAD_ARM_MS=100
FIX=$(mktemp -d); cd "$FIX"
mkdir -p "$HOME/.claude" "$HOME/.codex"
printf '{}' > "$HOME/.claude.json"
: > "$HOME/.codex/config.toml"

# ── open: 三次 pane split + agent start（stack，非 tab）──
: > "$STUB_LOG"
export STUB_AGENT_STATUS=idle
OUT=$(bash "$TRIAD" open --mode research 2>&1) || fail "triad-open rc=$? out=$OUT"
echo "$OUT" | grep -q "triad opened chief" && pass "open-chief" || fail "no chief open: $OUT"
echo "$OUT" | grep -q "triad opened a" && pass "open-a" || fail "no a open"
echo "$OUT" | grep -q "triad opened b" && pass "open-b" || fail "no b open"
grep -c "pane split" "$STUB_LOG" | grep -qE '^[3-9]' && pass "three-split" || fail "expected 3 splits"
grep -q "tab create" "$STUB_LOG" && fail "triad 不应 tab create" || pass "no-tab"
grep -q "agent start triad-chief" "$STUB_LOG" && pass "start-chief" || fail "no agent start chief"
grep -q "agent start triad-a" "$STUB_LOG" && pass "start-a" || fail "no agent start a"
grep -q "agent start triad-b" "$STUB_LOG" && pass "start-b" || fail "no agent start b"

[ -f .parallel/triad/chief/pane ] && pass "chief-pane-file" || fail "no chief/pane"
[ -f .parallel/triad/a/pane ] && pass "a-pane-file" || fail "no a/pane"
[ -f .parallel/triad/b/pane ] && pass "b-pane-file" || fail "no b/pane"
grep -q 'mode=triad' .parallel/triad/chief/meta && pass "meta-mode" || fail "meta mode"
grep -q 'triad_mode=research' .parallel/triad/session && pass "session-mode" || fail "session triad_mode"
CHIEF_PANE=$(cat .parallel/triad/chief/pane)
A_PANE=$(cat .parallel/triad/a/pane)
B_PANE=$(cat .parallel/triad/b/pane)
[ -n "$CHIEF_PANE" ] && [ -n "$A_PANE" ] && [ -n "$B_PANE" ] \
  && [ "$CHIEF_PANE" != "$A_PANE" ] && [ "$A_PANE" != "$B_PANE" ] \
  && pass "three-panes" || fail "pane ids bad"

# ── open 幂等复用 ──
: > "$STUB_LOG"
OUT2=$(bash "$TRIAD" open 2>&1) || fail "triad-reuse rc=$?"
echo "$OUT2" | grep -q "triad reuse" && pass "reuse-msg" || fail "expected reuse: $OUT2"
grep -q "pane split" "$STUB_LOG" && fail "reuse 不应 split" || pass "reuse-no-split"

# ── status --json 三席字段 ──
JSON=$(bash "$TRIAD" status --json) || fail "status-json rc"
echo "$JSON" | jq -e '.mode=="triad" and .triad_mode=="research" and .chief.pane and .a.pane and .b.pane' >/dev/null \
  && pass "status-json-shape" || fail "json=$JSON"

# ── fire：只 prompt 首席；消息含协议关键串 ──
: > "$STUB_LOG"
bash "$TRIAD" fire "调研 X" || fail "fire rc"
grep -q "agent prompt $CHIEF_PANE" "$STUB_LOG" && pass "fire-to-chief" || fail "fire 应只 prompt chief"
grep -q "agent prompt $A_PANE" "$STUB_LOG" && fail "fire 不应直派 a" || pass "fire-not-a"
grep -q "agent prompt $B_PANE" "$STUB_LOG" && fail "fire 不应直派 b" || pass "fire-not-b"
grep -q "triad 协作协议" "$STUB_LOG" && pass "proto-chief" || fail "缺首席协议"
grep -q "席位协议" "$STUB_LOG" && pass "proto-seat" || fail "缺席位协议"
grep -q "状态闸门" "$STUB_LOG" && pass "proto-gate" || fail "缺状态闸门"
grep -q "回话上限" "$STUB_LOG" && pass "proto-replycap" || fail "缺回话上限"
grep -q "禁止等待/轮询" "$STUB_LOG" && pass "proto-nopoll" || fail "缺首席禁轮询条款"
grep -q "PAR-DONE triad-chief#1" "$STUB_LOG" && pass "proto-anchor" || fail "缺首席锚 triad-chief#1"
grep -q "PAR-DONE triad-a#1" "$STUB_LOG" && pass "proto-seat-anchor" || fail "缺席位锚 triad-a#1"
# stub 锚点须锚在 chief（首个 PAR-DONE = 首席的）
[ "$(cat "$STUB_DIR/anchor-$CHIEF_PANE" 2>/dev/null)" = "triad-chief#1" ] \
  && pass "stub-anchor-chief" || fail "stub anchor=$(cat "$STUB_DIR/anchor-$CHIEF_PANE" 2>/dev/null)"

# ── fire 后 stale idle 不得误收；take 非阻塞 rc3 ──
bash "$TRIAD" take --all >/tmp/triad-take0.out 2>&1; TRC=$?
[ "$TRC" -eq 3 ] && pass "take-pending-rc3" || fail "take after fire rc=$TRC out=$(cat /tmp/triad-take0.out)"

# ── wait chief：agent wait 按锚写 token → 可收 ──
: > "$STUB_LOG"
OUT_W=$(bash "$TRIAD" wait chief --timeout-ms 5000 2>&1) || fail "wait-chief rc out=$OUT_W"
grep -q "agent wait $CHIEF_PANE" "$STUB_LOG" && pass "wait-did-wait" || fail "pending 应 agent wait"
OUT_T=$(bash "$TRIAD" take chief 2>&1) || fail "take-chief rc"
echo "$OUT_T" | grep -q 'par_result: PAR-DONE triad-chief#1' \
  && pass "take-shows-par-result" || fail "take 应打印首席 token: $OUT_T"
ls .parallel/triad/chief/archive/*.md >/dev/null 2>&1 && pass "archive-file" || fail "应有 archive/*.md"
bash "$TRIAD" take chief >/dev/null 2>&1; [ $? -eq 3 ] && pass "retake-rc3" || fail "重复 take 应 rc3"

# ── 席位 token 锚 = triad-<role>#<首席attempt>（手工落 token 模拟席位上报）──
ATT=$(sed -n 's/^attempt=//p' .parallel/triad/chief/round)
[ "$ATT" = "1" ] && pass "chief-att-1" || fail "chief attempt=$ATT"
echo "PAR-DONE triad-a#1 a-ok" > "$STUB_DIR/token-$A_PANE"
echo "PAR-DONE triad-b#1 b-ok" > "$STUB_DIR/token-$B_PANE"
OUT_A=$(bash "$TRIAD" take a 2>&1) || fail "take-a rc"
echo "$OUT_A" | grep -q 'PAR-DONE triad-a#1' && pass "take-seat-a" || fail "take a: $OUT_A"
OUT_ALL=$(bash "$TRIAD" take --all 2>&1) || fail "take-all rc"
echo "$OUT_ALL" | grep -q 'PAR-DONE triad-b#1' && pass "take-seat-b" || fail "take all: $OUT_ALL"
ls .parallel/triad/a/archive/1-*.md >/dev/null 2>&1 && pass "seat-archive" || fail "席位应归档且锚首席轮次（1-*.md）"

# ── 新 attempt 不吃旧锚：fire 后席位旧 token 失效 ──
bash "$TRIAD" fire "第二轮" || fail "fire2 rc"
echo "PAR-DONE triad-a#1 stale" > "$STUB_DIR/token-$A_PANE"
bash "$TRIAD" take a >/dev/null 2>&1; [ $? -eq 3 ] && pass "stale-seat-rc3" || fail "旧锚席位 token 不应过闸"
# 新锚可收
echo "PAR-DONE triad-a#2 a2-ok" > "$STUB_DIR/token-$A_PANE"
bash "$TRIAD" take a >/dev/null 2>&1 && pass "new-seat-anchor" || fail "新锚席位 token 应可收"

# ── B1：首席首 wait 无 token → 补问 → 次 wait 写 token → 成功 ──
export STUB_AUTO_NO_TOKEN=1
export STUB_AUTO_NO_TOKEN_WAITS=1
: > "$STUB_LOG"
OUT_N=$(bash "$TRIAD" wait chief --timeout-ms 8000 2>&1) || fail "wait-nudge rc out=$OUT_N"
echo "$OUT_N" | grep -q '补问' && pass "wait-nudge-msg" || fail "应出现补问: $OUT_N"
bash "$TRIAD" take chief >/dev/null 2>&1 && pass "take-after-nudge" || fail "补问后 take 应成功"
unset STUB_AUTO_NO_TOKEN STUB_AUTO_NO_TOKEN_WAITS

# ── collect = wait→take 兜底糖（fire 后单席自动收）──
: > "$STUB_LOG"
export STUB_AGENT_STATUS=working
bash "$TRIAD" fire "collect 题" || fail "collect fire rc"
OUT_C=$(bash "$TRIAD" collect chief --no-read --timeout-ms 8000 2>&1) || fail "collect rc out=$OUT_C"
echo "$OUT_C" | grep -q "triad collect" && pass "collect-banner" || fail "no collect banner: $OUT_C"
grep -q "agent wait" "$STUB_LOG" && pass "collect-did-wait" || fail "collect 应 wait"
export STUB_AGENT_STATUS=idle

# ── relay：脚本闸控回话通道（P-5 代码兜底）──
: > "$STUB_LOG"
bash "$TRIAD" fire "relay 题" || fail "relay fire rc"
grep -q "relay triad-" "$STUB_LOG" && pass "proto-relay" || fail "席位协议应指 relay"
ATT_R=$(sed -n 's/^attempt=//p' .parallel/triad/chief/round)

# 正常回话 a → b（目标 idle）
OUT_R=$(HERDR_PANE_ID="$A_PANE" bash "$TRIAD" relay triad-b "有异议" 2>&1) || fail "relay rc out=$OUT_R"
echo "$OUT_R" | grep -q "PAR-TRIAD-RELAY-PASS from=a to=b att=$ATT_R" \
  && pass "relay-pass" || fail "relay 回显: $OUT_R"
grep -q "agent prompt $B_PANE" "$STUB_LOG" && pass "relay-prompted" || fail "relay 应 prompt b"

# 回话上限：同 attempt 第二次 → rc7
HERDR_PANE_ID="$A_PANE" bash "$TRIAD" relay triad-b "再来" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 7 ] && pass "relay-cap-rc7" || fail "上限应 rc7 got=$RC"

# 新轮 fire → 额度重置 → 可 relay
bash "$TRIAD" fire "relay 二轮" || fail "fire relay2 rc"
OUT_R2=$(HERDR_PANE_ID="$A_PANE" bash "$TRIAD" relay triad-chief "定论" 2>&1) || fail "relay2 rc out=$OUT_R2"
echo "$OUT_R2" | grep -q "to=chief" && pass "relay-after-fire" || fail "新轮应重置额度: $OUT_R2"

# 状态闸：目标 working → rc5
export STUB_AGENT_STATUS=working
HERDR_PANE_ID="$B_PANE" bash "$TRIAD" relay triad-a "x" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 5 ] && pass "relay-gate-rc5" || fail "状态闸应 rc5 got=$RC"
export STUB_AGENT_STATUS=idle

# 隔离：目标非三席 → rc4；自注 → rc4；发送者不在三席（主窗/外部）→ rc6
HERDR_PANE_ID="$A_PANE" bash "$TRIAD" relay wX:p9 "x" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 4 ] && pass "relay-iso-rc4" || fail "隔离闸应 rc4 got=$RC"
HERDR_PANE_ID="$A_PANE" bash "$TRIAD" relay triad-a "x" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 4 ] && pass "relay-self-rc4" || fail "自注应 rc4 got=$RC"
HERDR_PANE_ID="wX:p1" bash "$TRIAD" relay triad-a "x" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 6 ] && pass "relay-outsider-rc6" || fail "主窗/外部应 rc6 got=$RC"

# take 不吃状态闸：席位报完 token 进 peer 阶段仍 working，锚对即可收（防误拒回归）
ATT_NOW=$(sed -n 's/^attempt=//p' .parallel/triad/chief/round)
echo "PAR-DONE triad-a#$ATT_NOW a-peer-phase" > "$STUB_DIR/token-$A_PANE"
export STUB_AGENT_STATUS=working
bash "$TRIAD" take a >/dev/null 2>&1 && pass "take-peer-phase-working-ok" || fail "锚对 working 应收（peer 阶段）"
export STUB_AGENT_STATUS=idle

# ── 公开路由：par.sh triad status --json 纯 stdout ──
JSON_R=$(bash "$PAR_SH" triad status --json 2>/tmp/triad-pass.err) || fail "par.sh triad status rc"
echo "$JSON_R" | jq -e . >/dev/null && pass "route-json-parse" || fail "route json dirty: $JSON_R"
echo "$JSON_R" | grep -q 'PAR-ROUTE-PASS' && fail "PASS 污染 stdout" || pass "route-json-stdout-clean"
grep -q 'PAR-ROUTE-PASS' /tmp/triad-pass.err && pass "route-pass-stderr" || fail "PASS 未进 stderr"

# ── close-tasks 不关 triad 三席 ──
# shellcheck disable=SC1091
. "$PAR_LIB"
: > "$STUB_LOG"
export PAR_CLOSE_PANE=1
par_close_all_task_panes "$FIX"
if grep -E "pane close (wT:p[0-9]+)( |$)" "$STUB_LOG"; then
  fail "close-tasks 误关 triad: $(cat "$STUB_LOG")"
else
  pass "close-tasks-skip-triad"
fi
[ -f .parallel/triad/chief/pane ] && pass "triad-still-registered" || fail "triad pane 文件丢了"

# ── close 显式关三席 ──
: > "$STUB_LOG"
bash "$TRIAD" close || fail "close rc"
grep -q "pane close" "$STUB_LOG" && pass "close-pane" || fail "close 应 pane close"
[ ! -f .parallel/triad/chief/pane ] && pass "close-cleared-chief" || fail "chief pane 未清"
[ ! -f .parallel/triad/a/pane ] && pass "close-cleared-a" || fail "a pane 未清"
[ ! -f .parallel/triad/b/pane ] && pass "close-cleared-b" || fail "b pane 未清"

# ── 坏槽位 / 坏 mode / 空 fire ──
bash "$TRIAD" open >/dev/null 2>&1 || true
bash "$TRIAD" take nope 2>/dev/null; RC=$?
[ "$RC" -ne 0 ] && pass "bad-slot-nonzero" || fail "坏槽位应非 0"
bash "$TRIAD" open --mode bogus 2>/dev/null; RC=$?
[ "$RC" -ne 0 ] && pass "bad-mode-nonzero" || fail "坏 mode 应非 0"
bash "$TRIAD" fire 2>/dev/null; RC=$?
[ "$RC" -ne 0 ] && pass "empty-fire-nonzero" || fail "空 fire 应非 0"

echo "PASS test-triad"
