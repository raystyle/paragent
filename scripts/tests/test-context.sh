#!/usr/bin/env bash
# context.sh / matrix.json / token helper 单测（不启真 agent）
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# ROOT = paragent 仓根
CTX="$ROOT/scripts/context.sh"
PAR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/par-lib.sh"
. "$PAR_LIB"

pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# matrix.json 解析（local 默认）
unset PAR_MATRIX_PROFILE PAR_MATRIX_JSON
[ "$(par_matrix_resolve @research/a)" = "grok -m grok-4.5" ] && pass "matrix-json-research-a" || fail "research/a"
[ "$(par_matrix_resolve @review/a)" = "claude --model claude-opus-4-8-cc[1m]" ] && pass "matrix-review-a" || fail "review/a"
[ "$(par_matrix_resolve @review/b)" = "codex -m gpt-5.6-sol-cx" ] && pass "matrix-review-b" || fail "review/b"
[ "$(par_matrix_resolve @speed/flash)" = "codex -m deepseek-v4-flash-cx" ] && pass "matrix-speed-flash" || fail "flash"
par_matrix_resolve @no/such 2>/dev/null && fail "unknown-track-should-fail" || pass "matrix-unknown-fails"

# remote 档案：极速=flash · 开发=glm · 研究=pro · 审阅双轨不变
export PAR_MATRIX_PROFILE=remote
[ "$(par_matrix_resolve @speed/a)" = "codex -m deepseek-v4-flash-cx" ] && pass "remote-speed" || fail "remote-speed=$(par_matrix_resolve @speed/a)"
[ "$(par_matrix_resolve @dev/a)" = "claude --model glm-5.2-cc[1m]" ] && pass "remote-dev" || fail "remote-dev"
[ "$(par_matrix_resolve @research/b)" = "codex -m deepseek-v4-pro-cx" ] && pass "remote-research" || fail "remote-research"
[ "$(par_matrix_resolve @review/a)" = "claude --model claude-opus-4-8-cc[1m]" ] && pass "remote-review-a" || fail "remote-review-a"
[ "$(par_matrix_resolve @review/b)" = "codex -m gpt-5.6-sol-cx" ] && pass "remote-review-b" || fail "remote-review-b"
unset PAR_MATRIX_PROFILE
# 前缀强制 remote（env 仍为 local）
[ "$(par_matrix_resolve @remote/dev/c)" = "claude --model glm-5.2-cc[1m]" ] && pass "prefix-remote-dev" || fail "prefix-remote"

# token helpers
d=$(par_token_done_cmd '${HERDR_PANE_ID}' t1 1 ok)
echo "$d" | grep -q 'par_result=PAR-DONE t1#1 ok' && pass "token-done-cmd" || fail "done-cmd=$d"
echo "$d" | grep -q -- '--source parallel' && pass "token-source" || fail "source"

# context --json 结构
J=$(bash "$CTX" --json 2>/dev/null) || fail "context-json-rc"
echo "$J" | jq -e '.layers.herdr and .harness.codex.stdin=="must_close" and .token.key=="par_result"' >/dev/null \
  && pass "context-json-shape" || fail "json-shape"

# 无效 tid
bash "$CTX" --json --tid __no_tid__ 2>/dev/null && fail "bad-tid-should-fail" || pass "context-bad-tid"

# 有 task 目录时 completion
TD=$(mktemp -d)
mkdir -p "$TD/.parallel/cx1"
echo done > "$TD/.parallel/cx1/state"
echo 'wT:p9' > "$TD/.parallel/cx1/pane"
printf 'mode=research\ncmd=grok -m grok-4.5\nraw=@research/a\nlayout=tab\ncwd=%s\nattempt=1\nbase=\n' "$TD" > "$TD/.parallel/cx1/meta"
J2=$(cd "$TD" && bash "$CTX" --json --tid cx1 2>/dev/null) || fail "context-tid-rc"
echo "$J2" | jq -e '.task.id=="cx1" and (.completion.done|contains("PAR-DONE cx1#1"))' >/dev/null \
  && pass "context-tid-completion" || fail "tid-completion: $J2"

# task.md 绝对路径（par-run 模板逻辑抽样：WS_SKILL_DIR）
[ -n "${PAR_HOME:-}" ] && [ -x "$PAR_HOME/bin/par" ] && pass "par-home-bin-abs" || fail "PAR_HOME=$PAR_HOME"

# yolo 旗标注入（herdr 交互免卡）
yc=$(par_yolo_cmd 'codex -m deepseek-v4-pro-cx')
echo "$yc" | grep -q 'dangerously-bypass-approvals-and-sandbox' && pass "yolo-codex" || fail "yolo-codex=$yc"
echo "$yc" | grep -q 'dangerously-bypass-hook-trust' && pass "yolo-codex-hook" || fail "yolo-hook=$yc"
# bypass 与 -a/-s 互斥：不得再注入
echo "$yc" | grep -qE -- '-a never|--ask-for-approval' && fail "yolo-codex-no-a got=$yc" || pass "yolo-codex-no-a"
echo "$yc" | grep -qE -- '-s danger|--sandbox' && fail "yolo-codex-no-s got=$yc" || pass "yolo-codex-no-s"
# 上游误带 -a 应被剥掉
yc_strip=$(par_yolo_cmd 'codex -m deepseek-v4-pro-cx -a never -s danger-full-access')
echo "$yc_strip" | grep -qE -- '-a never' && fail "yolo-strip-a=$yc_strip" || pass "yolo-strip-a"
echo "$yc_strip" | grep -q 'dangerously-bypass-approvals-and-sandbox' && pass "yolo-strip-keep-bypass" || fail "yolo-strip-bypass"
yc2=$(par_yolo_cmd "claude --model 'glm-5.2-cc[1m]'")
echo "$yc2" | grep -q 'dangerously-skip-permissions' && pass "yolo-claude" || fail "yolo-claude=$yc2"

echo "PASS test-context"
