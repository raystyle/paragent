#!/usr/bin/env bash
# test-wave.sh — par-wave.sh 渐进批量派发 + par-run --launch-only
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/par-stub.sh"
RUN=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../par-run.sh")
WAVE=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../par-wave.sh")

export HOME=$(mktemp -d)
FIX=$(mktemp -d); cd "$FIX"; git init -q; git -c user.name=t -c user.email=t@t commit -qm init --allow-empty

# ── par-run --launch-only:启动即返回(state=working,stdout=pane,不监听终态) ──
export STUB_TOKEN=""
OUT=$(bash "$RUN" lo1 "pi --model m" --mode research --brief x --launch-only) || fail "lo1 rc=$?"
[ "$OUT" = "wT:p9" ] && pass "lo-pane-echo" || fail "lo1 stdout=$OUT"
[ "$(cat .parallel/lo1/state)" = working ] && pass "lo-state-working" || fail "lo1 state"
grep -qE "^(agent wait|pane wait-output)" "$STUB_LOG" && fail "launch-only 不应监听终态" || pass "lo-no-await"

# ── par-wave research: 默认 tab,3 任务渐进启动 ──
: > "$STUB_LOG"
export STUB_AUTO=1
export STUB_ON_AGENT_WAIT_AUTO='printf "# research $TID#$ATT\n## 结论\nx\n## 证据\n无\n## 存疑\n无\n" > "'"$FIX"'/.parallel/$TID/artifact.md"'
bash "$WAVE" --mode research --timeout-min 1 w1="@research/a" w2="@research/b" w3=pi \
  && pass "wave-rc" || fail "wave rc=$?"

for t in w1 w2 w3; do
  [ "$(cat .parallel/$t/state)" = done ] && pass "wave-$t-done" || fail "$t state=$(cat .parallel/$t/state)"
done

# research 默认 tab，不开右侧 split
grep -q "tab create" "$STUB_LOG" && pass "wave-research-tab" || fail "research 应 tab create"
grep -q "pane split" "$STUB_LOG" && fail "research 默认不应 pane split" || pass "wave-no-split"

# 串行: w1 prompt 早于 w2 tab create 早于 w2 prompt
l() { grep -n "$1" "$STUB_LOG" | head -1 | cut -d: -f1; }
P1=$(l "agent prompt.*\.parallel/w1/task")
# 第 2 次 tab create（第 1 次属 w1）
T2=$(grep -n "tab create" "$STUB_LOG" | sed -n '2p' | cut -d: -f1)
P2=$(l "agent prompt.*\.parallel/w2/task")
[ -n "$P1" ] && [ -n "$T2" ] && [ "$P1" -lt "$T2" ] && pass "wave-serial-1" || fail "w1 prompt($P1) 应早于 w2 tab($T2)"
[ -n "$P2" ] && [ -n "$T2" ] && [ "$T2" -lt "$P2" ] && pass "wave-serial-2" || fail "w2 tab($T2) 应早于 w2 prompt($P2)"

# meta 记录矩阵解析
grep -q 'cmd=grok -m grok-4.5' .parallel/w1/meta && pass "wave-meta-matrix" || fail "w1 meta cmd=$(cat .parallel/w1/meta)"

# ── par-wave dev: 默认 tab + worktree 交付需新 commit ──
: > "$STUB_LOG"
export STUB_ON_AGENT_WAIT_AUTO='
  echo x > "'"$FIX"'/.parallel/$TID/artifact.md"
  git -C "'"$FIX"'/.parallel/$TID/wt" -c user.name=t -c user.email=t@t commit -qm work --allow-empty 2>/dev/null || true
'
bash "$WAVE" --mode dev --timeout-min 1 d1="@dev/a" \
  && pass "wave-dev-rc" || fail "wave-dev rc=$?"
grep -q "tab create" "$STUB_LOG" && pass "wave-dev-tab" || fail "dev 应 tab create"
[ "$(cat .parallel/d1/state)" = done ] && pass "wave-dev-done" || fail "d1 state=$(cat .parallel/d1/state 2>/dev/null)"

# 坏 tid
bash "$WAVE" --mode research Bad_Tid=pi 2>/dev/null; [ $? -eq 1 ] && pass "wave-bad-tid-rc1" || fail "坏 tid 应 rc1"

# ── par-wave review: 一等 mode，无 worktree，只读契约 ──
rm -rf .parallel; : > "$STUB_LOG"
export STUB_AUTO=1
export STUB_ON_AGENT_WAIT_AUTO='printf "# review $TID#$ATT\n## 结论\n通过\n## P0\n无\n## P1\n无\n## 存疑\n无\n## 证据\n读了diff\n" > "'"$FIX"'/.parallel/$TID/artifact.md"'
bash "$WAVE" --mode review --timeout-min 1 ra=@review/a rb=@review/b >/tmp/wave-rev.out 2>&1 \
  && pass "wave-review-rc" || fail "wave-review rc=$? out=$(cat /tmp/wave-rev.out)"
grep -q "tab create" "$STUB_LOG" && pass "wave-review-tab" || fail "review 应 tab create"
[ ! -d .parallel/ra/wt ] && pass "wave-review-no-wt" || fail "review 不应 worktree"
grep -qE 'mode=review' .parallel/ra/meta && pass "wave-review-meta-a" || fail "ra meta=$(cat .parallel/ra/meta)"
grep -qE 'mode=review' .parallel/rb/meta && pass "wave-review-meta-b" || fail "rb meta=$(cat .parallel/rb/meta)"
[ ! -d .parallel/rb/wt ] && pass "wave-review-rb-no-wt" || fail "rb 也不应 worktree"
grep -qE '只读审阅' .parallel/ra/task.md && pass "wave-review-task" || fail "task 缺审阅契约: $(head -20 .parallel/ra/task.md)"
grep -qE '只读审阅' .parallel/rb/task.md && pass "wave-review-task-b" || fail "rb task 缺审阅契约"
grep -q '唯一允许写' .parallel/ra/task.md && pass "wave-review-write-exception" || fail "task 须声明 artifact 写例外"
grep -q 'cmd=claude --model claude-opus-4-8-cc' .parallel/ra/meta \
  && pass "wave-review-matrix-a" || fail "ra cmd=$(grep ^cmd= .parallel/ra/meta)"
grep -q 'cmd=codex -m gpt-5.6-sol-cx' .parallel/rb/meta \
  && pass "wave-review-matrix-b" || fail "rb cmd=$(grep ^cmd= .parallel/rb/meta)"
[ "$(cat .parallel/ra/state)" = done ] && [ "$(cat .parallel/rb/state)" = done ] \
  && pass "wave-review-both-done" || fail "states ra=$(cat .parallel/ra/state) rb=$(cat .parallel/rb/state)"
# 旧写法：mode research + @review 轨仍可启动且无 worktree
: > "$STUB_LOG"
bash "$WAVE" --mode research --timeout-min 1 old=@review/a >/tmp/wave-old.out 2>&1 \
  && pass "wave-old-review-track-rc" || fail "旧 research+@review 应可用 out=$(cat /tmp/wave-old.out)"
[ ! -d .parallel/old/wt ] && pass "wave-old-review-no-wt" || fail "旧写法也不应 worktree"
bash "$WAVE" --mode nope t1=@review/a 2>/dev/null; [ $? -eq 1 ] && pass "wave-bad-mode-rc1" || fail "坏 mode 应 rc1"

echo "PASS test-wave"
