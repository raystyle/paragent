#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/par-stub.sh"
RUN=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../par-run.sh")   # cd $FIX 前解析成绝对路径

FIX=$(mktemp -d); cd "$FIX"; git init -q; git -c user.name=t -c user.email=t@t commit -qm init --allow-empty

# happy(research):上报 token done + stub 副作用写 artifact → done
export STUB_ON_AGENT_WAIT='printf "# research t1#1\n## 结论\nok\n## 证据\n无\n## 存疑\n无\n" > "'"$FIX"'/.parallel/t1/artifact.md"'
export STUB_TOKEN="PAR-DONE t1#1 完成"
bash "$RUN" t1 "pi --model m" --mode research --brief "测试任务" --timeout-min 1 \
  && pass "run-done-rc" || fail "run t1 rc=$?"
[ "$(cat .parallel/t1/state)" = done ] && pass "run-done-state" || fail "state=$(cat .parallel/t1/state)"
grep -q "PAR-DONE t1#1" .parallel/t1/task.md && pass "run-taskmd-契约" || fail "task.md 无完成上报约定"
grep -q "PAR-DONE t1#1" "$STUB_LOG" && pass "run-dispatch-内联契约" || fail "dispatch prompt 未内联上报格式"

# blocked:上报 token blocked → state=blocked
export STUB_ON_AGENT_WAIT=""; export STUB_TOKEN="PAR-BLOCKED t2#1 需要人"
bash "$RUN" t2 "pi" --mode research --brief x --timeout-min 1; [ $? -eq 2 ] && pass "run-blocked-rc2" || fail "t2 rc"
[ "$(cat .parallel/t2/state)" = blocked ] && pass "run-blocked-state" || fail "t2 state"

# 虚报:token done 但 artifact 不写 → grace(PAR_GRACE_MAX=1 加速)后质问(要求 #2 新 token)仍缺 → stalled
export STUB_ON_AGENT_WAIT=""; export STUB_ON_AGENT_WAIT_AUTO=""; export STUB_TOKEN=""; export STUB_AUTO=1
export PAR_GRACE_MAX=1
BEFORE=$(grep -c "agent prompt" "$STUB_LOG")
bash "$RUN" t3 "pi" --mode research --brief x --timeout-min 1; [ $? -eq 2 ] && pass "run-fake-rc2" || fail "t3 rc"
[ "$(cat .parallel/t3/state)" = stalled ] && pass "run-fake-stalled" || fail "t3 state=$(cat .parallel/t3/state)"
AFTER=$(grep -c "agent prompt" "$STUB_LOG")
[ $((AFTER - BEFORE)) -ge 2 ] && pass "run-fake-质问补发" || fail "虚报未补发(agent prompt 增量 $((AFTER - BEFORE)) < 2)"
unset PAR_GRACE_MAX

# 质问轮次递增:#1 虚报(无 artifact) → 质问要求 #2(旧 token 留在 pane,不 +1 会秒配) → 补 artifact + #2 → done
export STUB_AUTO=1
export STUB_ON_AGENT_WAIT_AUTO='[ "$TID#$ATT" = t9#2 ] && printf "# research t9#2\n## 结论\n补齐\n## 证据\n无\n## 存疑\n无\n" > "'"$FIX"'/.parallel/t9/artifact.md"'
export PAR_GRACE_MAX=1
BEFORE=$(grep -c "agent prompt" "$STUB_LOG")
bash "$RUN" t9 "pi" --mode research --brief x --timeout-min 1 \
  && pass "run-retry-done" || fail "t9 质问轮应 done(秒配旧 token 会误 stalled)"
[ "$(cat .parallel/t9/state)" = done ] && pass "run-retry-state" || fail "t9 state=$(cat .parallel/t9/state)"
grep -q "PAR-DONE t9#2" "$STUB_LOG" && pass "run-retry-质问要#2" || fail "质问未要求 #2 新 token"
AFTER=$(grep -c "agent prompt" "$STUB_LOG")
[ $((AFTER - BEFORE)) -eq 2 ] && pass "run-retry-一次质问" || fail "t9 prompt 增量 $((AFTER - BEFORE)) ≠ 2"
unset PAR_GRACE_MAX; export STUB_AUTO=0; export STUB_ON_AGENT_WAIT_AUTO=""

# develop 模式:建 worktree + 分支 par/t4;artifact+commit 齐 → done
export STUB_ON_AGENT_WAIT='cd "'"$FIX"'/.parallel/t4/wt" && git -c user.name=t -c user.email=t@t commit -qm work --allow-empty && echo ok > "'"$FIX"'/.parallel/t4/artifact.md"'
export STUB_TOKEN="PAR-DONE t4#1 develop完成"
bash "$RUN" t4 "pi" --mode develop --brief x --timeout-min 1 \
  && pass "run-develop-done" || fail "t4 rc=$?"
[ -d .parallel/t4/wt ] && git branch --list "par/t4" | grep -q par/t4 && pass "run-develop-worktree" || fail "t4 worktree"

# task-id 非法值:大写/下划线均 rc1 拒绝(挡路径穿越与正则元字符)
bash "$RUN" A1 "pi" --mode research --brief x >/dev/null 2>&1; [ $? -eq 1 ] && pass "run-tid-uppercase-rc1" || fail "tid A1 未拒绝"
bash "$RUN" a_b "pi" --mode research --brief x >/dev/null 2>&1; [ $? -eq 1 ] && pass "run-tid-underscore-rc1" || fail "tid a_b 未拒绝"

# 数值参数校验:非数字 --timeout-min rc1 拒绝
bash "$RUN" t5 "pi" --mode research --brief x --timeout-min abc >/dev/null 2>&1; [ $? -eq 1 ] && pass "run-tmo-nonnum-rc1" || fail "--timeout-min abc 未拒绝"

# 上报/交付竞态:artifact 延迟 2s 落盘(上报先命中;bg 写须 >/dev/null 关管道,否则命令替换等 bg 退出造假象)
# grace 重试后判 done,且不发质问(竞态误质问→pi 不提交→卡死误 stalled,实战两次)
export STUB_ON_AGENT_WAIT='( sleep 2; printf "# research t6#1\n## 结论\nlate\n## 证据\n无\n## 存疑\n无\n" > "'"$FIX"'/.parallel/t6/artifact.md" ) >/dev/null 2>&1 &'
export STUB_TOKEN="PAR-DONE t6#1 稍慢"
BEFORE=$(grep -c "agent prompt" "$STUB_LOG")
bash "$RUN" t6 "pi" --mode research --brief x --timeout-min 1 \
  && pass "run-grace-done" || fail "t6 竞态误判 stalled(应 grace 后 done)"
[ "$(cat .parallel/t6/state)" = done ] && pass "run-grace-state" || fail "t6 state=$(cat .parallel/t6/state)"
AFTER=$(grep -c "agent prompt" "$STUB_LOG")
[ $((AFTER - BEFORE)) -eq 1 ] && pass "run-grace-无质问" || fail "grace 期内不应补发质问(增量 $((AFTER - BEFORE)) ≠ 1)"

# 弹性 grace:早产上报,artifact 延迟 8s 落盘(超旧固定 grace 6s) → 弹性等待后 done,不发质问
export STUB_ON_AGENT_WAIT='( sleep 8; printf "# research t7#1\n## 结论\nlate\n## 证据\n无\n## 存疑\n无\n" > "'"$FIX"'/.parallel/t7/artifact.md" ) >/dev/null 2>&1 &'
export STUB_TOKEN="PAR-DONE t7#1 早产"
BEFORE=$(grep -c "agent prompt" "$STUB_LOG")
bash "$RUN" t7 "pi" --mode research --brief x --timeout-min 1 \
  && pass "run-egrace-done" || fail "t7 弹性 grace 误判(应 done)"
[ "$(cat .parallel/t7/state)" = done ] && pass "run-egrace-state" || fail "t7 state=$(cat .parallel/t7/state)"
AFTER=$(grep -c "agent prompt" "$STUB_LOG")
[ $((AFTER - BEFORE)) -eq 1 ] && pass "run-egrace-无质问" || fail "弹性 grace 期内不应补发质问(增量 $((AFTER - BEFORE)) ≠ 1)"

# 无 token 永不 done：预写旧 artifact + idle → timeout（禁 sentinel-missing→done）
export STUB_ON_AGENT_WAIT=""; export STUB_TOKEN=""
mkdir -p .parallel/t8; echo 旧产物 > .parallel/t8/artifact.md
export PAR_SLICE_SECS=1
BEFORE=$(grep -c "agent prompt" "$STUB_LOG")
bash "$RUN" t8 "pi" --mode research --brief x --timeout-min 1; [ $? -eq 2 ] && pass "run-nosentinel-rc2" || fail "t8 无 token 应 rc2"
[ "$(cat .parallel/t8/state)" = timeout ] && pass "run-nosentinel-timeout" || fail "t8 state=$(cat .parallel/t8/state) 应 timeout"
! grep -q "sentinel-missing" .parallel/t8/.await 2>/dev/null && pass "run-nosentinel-无sentinel-done" || fail "t8 不应 sentinel-missing→done"
AFTER=$(grep -c "agent prompt" "$STUB_LOG")
[ $((AFTER - BEFORE)) -eq 1 ] && pass "run-nosentinel-无质问" || fail "无 token 不应补发质问(增量 $((AFTER - BEFORE)) ≠ 1)"
unset PAR_SLICE_SECS

# 空结论 token 不算完成
export STUB_ON_AGENT_WAIT='echo x > "'"$FIX"'/.parallel/t10/artifact.md"'
export STUB_TOKEN="PAR-DONE t10#1"
bash "$RUN" t10 "pi" --mode research --brief x --timeout-min 1; [ $? -eq 2 ] && pass "run-empty-concl-rc2" || fail "t10 空结论应失败"
[ "$(cat .parallel/t10/state)" != done ] && pass "run-empty-concl-not-done" || fail "t10 空结论不得 done"

# 旧 artifact + 新 token 但未刷新产物 → 仍非 done（基线门禁）
export STUB_ON_AGENT_WAIT=""
mkdir -p .parallel/t11; echo 旧 > .parallel/t11/artifact.md
export STUB_TOKEN="PAR-DONE t11#1 有结论"
export PAR_GRACE_MAX=1
bash "$RUN" t11 "pi" --mode research --brief x --timeout-min 1; [ $? -eq 2 ] && pass "run-stale-art-rc2" || fail "t11 旧 artifact 应失败"
[ "$(cat .parallel/t11/state)" != done ] && pass "run-stale-art-not-done" || fail "t11 旧 artifact 不得 done"
unset PAR_GRACE_MAX

# review（P-1 模板写死）：骨架预写进 artifact.md；agent 填实五节 → done
export STUB_ON_AGENT_WAIT='grep -q "^## P0" "'"$FIX"'/.parallel/t12/artifact.md" && echo seen >> "'"$FIX"'/skel.log"; printf "# review t12#1\n## 结论\n通过\n## P0\n无\n## P1\n无\n## 存疑\n无\n## 证据\n读了diff\n" > "'"$FIX"'/.parallel/t12/artifact.md"'
export STUB_TOKEN="PAR-DONE t12#1 审完"
bash "$RUN" t12 "pi" --mode review --brief "审 diff" --timeout-min 1 \
  && pass "run-review-done" || fail "t12 rc=$?"
[ "$(cat .parallel/t12/state)" = done ] && pass "run-review-state" || fail "t12 state=$(cat .parallel/t12/state)"
grep -q seen "$FIX/skel.log" 2>/dev/null && pass "run-review-骨架预写" || fail "t12 artifact 未见预写骨架"
grep -q "五节标题固定" .parallel/t12/task.md && pass "run-review-taskmd-模板" || fail "t12 task.md 缺模板说明"

# review 缺节：agent 交了散文（无五节）→ lint 硬卡 → 质问后仍缺 → stalled
export STUB_ON_AGENT_WAIT='echo 散文无节 > "'"$FIX"'/.parallel/t13/artifact.md"'
export STUB_ON_AGENT_WAIT_AUTO='echo 散文无节 > "'"$FIX"'/.parallel/t13/artifact.md"'
export STUB_TOKEN=""; export STUB_AUTO=1; export PAR_GRACE_MAX=1
bash "$RUN" t13 "pi" --mode review --brief x --timeout-min 1; [ $? -eq 2 ] && pass "run-review-lint-rc2" || fail "t13 rc"
[ "$(cat .parallel/t13/state)" = stalled ] && pass "run-review-lint-stalled" || fail "t13 state=$(cat .parallel/t13/state) 应 stalled"
unset PAR_GRACE_MAX; export STUB_AUTO=0; export STUB_ON_AGENT_WAIT_AUTO=""

echo "PASS test-run"
