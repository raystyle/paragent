#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/par-stub.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../par-lib.sh"

# par_ws:取 focused workspace
[ "$(par_ws)" = "wT" ] && pass "ws-focused" || fail "par_ws=$(par_ws)"

# par_ws 失败路径:herdr 返回空 workspaces → rc≠0 且 stdout 为空
STUB_DIR2=$(mktemp -d)
cat > "$STUB_DIR2/herdr" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "workspace list" ] && echo '{"result":{"workspaces":[]}}' || echo '{"result":{}}'
EOF
chmod +x "$STUB_DIR2/herdr"
OUT=$(PATH="$STUB_DIR2:$PATH" par_ws) && fail "ws-empty 应 rc!=0" || pass "ws-empty-fails"
[ -z "$OUT" ] && pass "ws-empty-stdout" || fail "ws-empty stdout非空: $OUT"

# par_matrix_resolve
[ "$(par_matrix_resolve '@dev/a')" = "kimi -m kimi-code/k3" ] && pass "matrix-dev-a" || fail "dev/a"
[ "$(par_matrix_resolve research/c)" = "codex -m deepseek-v4-pro-cx" ] && pass "matrix-res-c" || fail "res/c"
[ "$(par_matrix_resolve '@review/a')" = "claude --model claude-opus-4-8-cc[1m]" ] && pass "matrix-review-a" || fail "review/a"
[ "$(par_matrix_resolve '@review/b')" = "codex -m gpt-5.6-sol-cx" ] && pass "matrix-review-b" || fail "review/b"
[ "$(par_matrix_resolve 'pi --model x')" = "pi --model x" ] && pass "matrix-passthrough" || fail "passthrough"

# par_recruit 默认 tab: tab create → agent start
: > "$STUB_LOG"
PANE=$(par_recruit wT t1 "pi --model m" /tmp) || fail "recruit-default rc"
[ "$PANE" = "wT:p9" ] && pass "recruit-default-pane" || fail "pane=$PANE"
grep -q "tab create" "$STUB_LOG" && pass "recruit-default-tab" || fail "default 应 tab create"
grep -q "pane split" "$STUB_LOG" && fail "default 不应 split" || pass "default-no-split"
grep -q "agent start t1 --kind pi --pane wT:p9" "$STUB_LOG" && pass "recruit-start-args" || fail "start args"

# par_recruit 显式 tab
: > "$STUB_LOG"
PANE=$(par_recruit wT t2 "kimi -m kimi-code/k3" /tmp tab) || fail "recruit-tab rc"
grep -q "tab create" "$STUB_LOG" && pass "recruit-tab" || fail "no tab create"
grep -q "pane split" "$STUB_LOG" && fail "tab 不应 split" || pass "tab-no-split"

# par_recruit 显式 stack（覆盖）: pane split → agent start
: > "$STUB_LOG"
PANE=$(par_recruit wT t1s "pi --model m" /tmp stack) || fail "recruit-stack rc"
grep -q "pane split" "$STUB_LOG" && pass "recruit-split" || fail "no split"
grep -q "tab create" "$STUB_LOG" && fail "stack 不应 tab create" || pass "stack-no-tab"

# par_await_sentinel:done / blocked / timeout 三态
export STUB_TOKEN="PAR-DONE t1#1 ok"
[ "$(par_await_sentinel 5000 wT:p9 t1 1)" = done ] && pass "await-done" || fail "await done"
export STUB_TOKEN="PAR-BLOCKED t1#1 why"
[ "$(par_await_sentinel 5000 wT:p9 t1 1)" = blocked ] && pass "await-blocked" || fail "await blocked"
unset STUB_TOKEN; export STUB_TOKEN=""
[ "$(par_await_sentinel 200 wT:p9 t1 1)" = timeout ] && pass "await-timeout" || fail "await timeout"

# 串台防护:别的 task-id 的上报 token 不算
export STUB_TOKEN="PAR-DONE other#1 ok"
[ "$(par_await_sentinel 200 wT:p9 t1 1)" = timeout ] && pass "await-no-crosstalk" || fail "crosstalk"
unset STUB_TOKEN; export STUB_TOKEN=""

# par_delivery_met:artifact + commit 两信号
TD=$(mktemp -d); echo x > "$TD/artifact.md"
par_delivery_met "$TD" 0 "" && pass "delivery-artifact-only" || fail "delivery0"
mkdir -p "$TD/wt"; git -C "$TD/wt" init -q; git -C "$TD/wt" -c user.name=t -c user.email=t@t commit -qm init --allow-empty
par_delivery_met "$TD" 1 "$(git -C "$TD/wt" rev-parse HEAD)" && fail "delivery-no-commit应失败" || pass "delivery-no-commit-rejected"
git -C "$TD/wt" -c user.name=t -c user.email=t@t commit -qm second --allow-empty
BASE=$(git -C "$TD/wt" rev-parse HEAD~1)
par_delivery_met "$TD" 1 "$BASE" && pass "delivery-new-commit" || fail "delivery1"

# par_delivery_met review 结构 lint（P-1 模板写死）：五节缺一不收
TD2=$(mktemp -d); echo x > "$TD2/artifact.md"
par_delivery_met "$TD2" 0 "" review && fail "review 无节应拒" || pass "delivery-review-naked-rejected"
cat > "$TD2/artifact.md" <<'EOF'
# review t1#1
## 结论
通过
## P0
无
## P1
无
## 存疑
无
## 证据
读了 diff
EOF
par_delivery_met "$TD2" 0 "" review && pass "delivery-review-full" || fail "review 五节齐应收"
sed -i '/^## P1/d' "$TD2/artifact.md"
par_delivery_met "$TD2" 0 "" review && fail "review 缺 P1 应拒" || pass "delivery-review-missing-p1-rejected"
# research 结构 lint（P-2）：三节（结论/证据/存疑）缺一不收
TD3=$(mktemp -d); echo 散文 > "$TD3/artifact.md"
par_delivery_met "$TD3" 0 "" research && fail "research 无节应拒" || pass "delivery-research-naked-rejected"
printf '# research t1#1\n## 结论\nok\n## 证据\n无\n## 存疑\n无\n' > "$TD3/artifact.md"
par_delivery_met "$TD3" 0 "" research && pass "delivery-research-full" || fail "research 三节齐应收"
sed -i '/^## 存疑/d' "$TD3/artifact.md"
par_delivery_met "$TD3" 0 "" research && fail "research 缺存疑应拒" || pass "delivery-research-missing-rejected"
# dev 模式不受 lint
par_delivery_met "$TD" 1 "$BASE" && pass "delivery-dev-no-lint" || fail "dev 不应 lint"
echo "PASS test-lib"
