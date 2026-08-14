#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/par-stub.sh"
M=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../par-merge.sh")   # cd $FIX 前解析成绝对路径

export HOME=$(mktemp -d)   # 隔离外层 git 全局配置
FIX=$(mktemp -d); cd "$FIX"; git init -q
git config user.name t; git config user.email t@t   # merge --no-ff 产 merge commit,需本仓库身份
echo base > f.txt; git add f.txt; git commit -qm init --allow-empty

# 造两个已完成任务(零重叠:各改各的文件)
mk() { # <tid> <file>
  git worktree add -q -B "par/$1" ".parallel/$1/wt" HEAD
  echo "$1" > ".parallel/$1/wt/$2"; git -C ".parallel/$1/wt" add "$2"
  git -C ".parallel/$1/wt" commit -qm "$1"
  echo verified > ".parallel/$1/state"
}
mk m1 a.txt; mk m2 b.txt

bash "$M" m1 m2 && pass "merge-rc" || fail "merge rc"
git log --oneline | grep -q "merge: par/m1" && pass "merge-m1" || fail "m1 未合并"
[ -f a.txt ] && [ -f b.txt ] && pass "merge-files" || fail "文件缺失"
[ ! -d .parallel/m1/wt ] && pass "merge-wt-cleaned" || fail "wt 残留"
! git branch --list "par/m1" | grep -q m1 && pass "merge-branch-deleted" || fail "分支残留"
[ "$(cat .parallel/m1/state)" = merged ] && pass "merge-state-merged" || fail "m1 state 未置 merged"

# state 非 done/verified 拒绝 merge
git worktree add -q -B "par/m3" ".parallel/m3/wt" HEAD
echo working > ".parallel/m3/state"
bash "$M" m3; [ $? -eq 2 ] && pass "merge-reject-not-done" || fail "m3 应拒"

# 冲突:abort + rc2 + 指引
git worktree add -q -B "par/m4" ".parallel/m4/wt" HEAD
echo conflict > ".parallel/m4/wt/f.txt"; git -C ".parallel/m4/wt" add f.txt
git -C ".parallel/m4/wt" commit -qm m4
echo verified > ".parallel/m4/state"
echo other > f.txt; git add f.txt; git commit -qm main-advance
bash "$M" m4; [ $? -eq 2 ] && pass "merge-conflict-rc2" || fail "m4 rc"
# abort 干净的等效可靠断言:无未解决冲突文件 且 f.txt 仍是 main 的 other(未被 merge 污染)
[ -z "$(git diff --name-only --diff-filter=U)" ] && [ "$(cat f.txt)" = other ] \
  && pass "merge-conflict-aborted" || fail "merge 未 abort 干净"

# task-id 非法值:大写/下划线均 rc1 拒绝(与 par-run/par-verify 一致,逐任务校验)
bash "$M" A1 >/dev/null 2>&1; [ $? -eq 1 ] && pass "merge-tid-uppercase-rc1" || fail "tid A1 未拒绝"
bash "$M" a_b >/dev/null 2>&1; [ $? -eq 1 ] && pass "merge-tid-underscore-rc1" || fail "tid a_b 未拒绝"

# merge checklist 三行（P-4）：state/verify/diffstat 逐任务打印
git worktree add -q -B "par/m5" ".parallel/m5/wt" HEAD
echo m5 > ".parallel/m5/wt/c.txt"; git -C ".parallel/m5/wt" add c.txt
git -C ".parallel/m5/wt" commit -qm m5
echo done > ".parallel/m5/state"
printf '== verify 第 1 轮: true ==\nPASS\n' > ".parallel/m5/verify.log"
OUT_CK=$(bash "$M" m5) || fail "m5 merge rc"
echo "$OUT_CK" | grep -q 'checklist m5:' && pass "checklist-header" || fail "缺 checklist 头: $OUT_CK"
echo "$OUT_CK" | grep -q '1) state=done' && pass "checklist-state" || fail "checklist 缺 state 行"
echo "$OUT_CK" | grep -q '2) verify.log: PASS' && pass "checklist-verify-pass" || fail "checklist verify 应 PASS: $OUT_CK"
echo "$OUT_CK" | grep -q '3) diff: 1 file changed' && pass "checklist-diffstat" || fail "checklist 缺 diffstat: $OUT_CK"
# 无 verify.log → 人判豁免文案
git worktree add -q -B "par/m6" ".parallel/m6/wt" HEAD
echo m6 > ".parallel/m6/wt/d.txt"; git -C ".parallel/m6/wt" add d.txt
git -C ".parallel/m6/wt" commit -qm m6
echo done > ".parallel/m6/state"
OUT_CK2=$(bash "$M" m6) || fail "m6 merge rc"
echo "$OUT_CK2" | grep -q '2) verify.log: 无 verify 记录（人判豁免）' \
  && pass "checklist-verify-none" || fail "无 verify.log 应人判豁免: $OUT_CK2"
echo "PASS test-merge"
