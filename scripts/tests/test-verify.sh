#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/par-stub.sh"
V=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../par-verify.sh")   # cd $FIX 前解析成绝对路径

FIX=$(mktemp -d); cd "$FIX"; git init -q; git -c user.name=t -c user.email=t@t commit -qm init --allow-empty
TD=.parallel/v1; mkdir -p "$TD/wt"; echo wT:p9 > "$TD/pane"
printf 'mode=dev\ncmd=pi\ncwd=%s\nattempt=1\n' "$FIX/$TD/wt" > "$TD/meta"; echo done > "$TD/state"

# verify 一次过
bash "$V" v1 --cmd "true" && pass "verify-pass-rc" || fail "v1 rc"
grep -q PASS "$TD/verify.log" && pass "verify-pass-log" || fail "v1 log"
[ "$(cat $TD/state)" = verified ] && pass "verify-pass-state" || fail "v1 state"

# verify 失败→补发修复(stub 副作用写 ok 文件)→复审过
TD2=.parallel/v2; mkdir -p "$TD2/wt"; echo wT:p9 > "$TD2/pane"
printf 'mode=dev\ncmd=pi\ncwd=%s\nattempt=1\n' "$FIX/$TD2/wt" > "$TD2/meta"; echo done > "$TD2/state"
# brief fixture 原写 FIX 根,但 verify 在 wt 内跑(cd $TD/wt)——ok 文件须落在 wt 内同一相对路径
export STUB_ON_AGENT_WAIT='mkdir -p "'"$FIX"'/.parallel/v2/wt/.parallel/v2" && touch "'"$FIX"'/.parallel/v2/wt/.parallel/v2/ok"'
export STUB_TOKEN="PAR-DONE v2#2 修好了"
bash "$V" v2 --cmd "test -f .parallel/v2/ok" --retry 1 && pass "verify-retry-pass" || fail "v2 rc"
grep -q "agent prompt" "$STUB_LOG" && pass "verify-retry-补发" || fail "v2 未补发"

# retry 耗尽 → rc2 + state=verify-failed;FAIL 摘要走 stderr 不走 stdout
TD3=.parallel/v3; mkdir -p "$TD3/wt"; echo wT:p9 > "$TD3/pane"
printf 'mode=dev\ncmd=pi\ncwd=%s\nattempt=1\n' "$FIX/$TD3/wt" > "$TD3/meta"; echo done > "$TD3/state"
export STUB_ON_AGENT_WAIT=""; export STUB_TOKEN="PAR-DONE v3#2 没修"
bash "$V" v3 --cmd "false" --retry 1 --timeout-min 1 1>"$FIX/out.txt" 2>"$FIX/err.txt"; [ $? -eq 2 ] && pass "verify-fail-rc2" || fail "v3 rc"
[ "$(cat $TD3/state)" = verify-failed ] && pass "verify-fail-state" || fail "v3 state"
grep -q "verify v3 FAIL" "$FIX/err.txt" && pass "verify-fail-stderr" || fail "v3 FAIL 摘要不在 stderr"
! grep -q "FAIL" "$FIX/out.txt" && pass "verify-fail-stdout-clean" || fail "v3 stdout 不应含 FAIL 摘要"

# 无 wt 目录(非 dev 任务)→ rc2 + stderr 含「缺失」
TD4=.parallel/v4; mkdir -p "$TD4"; echo wT:p9 > "$TD4/pane"
printf 'mode=research\ncmd=pi\ncwd=%s\nattempt=1\n' "$FIX" > "$TD4/meta"; echo done > "$TD4/state"
bash "$V" v4 --cmd "true" 2>"$FIX/err4.txt"; [ $? -eq 2 ] && pass "verify-no-wt-rc2" || fail "v4 rc"
grep -q "缺失" "$FIX/err4.txt" && pass "verify-no-wt-stderr" || fail "v4 stderr 无缺失提示"

# 数值参数校验:非数字 --retry rc1 拒绝
bash "$V" v1 --cmd "true" --retry abc >/dev/null 2>&1; [ $? -eq 1 ] && pass "verify-retry-nonnum-rc1" || fail "--retry abc 未拒绝"

# task-id 非法值:大写/下划线均 rc1 拒绝(与 par-run 一致)
bash "$V" A1 --cmd "true" >/dev/null 2>&1; [ $? -eq 1 ] && pass "verify-tid-uppercase-rc1" || fail "tid A1 未拒绝"
bash "$V" a_b --cmd "true" >/dev/null 2>&1; [ $? -eq 1 ] && pass "verify-tid-underscore-rc1" || fail "tid a_b 未拒绝"
echo "PASS test-verify"
