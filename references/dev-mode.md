# dev-mode — 并行分支/开叉细则

> 用法正本：`../../references/parallel.md`（四原语卡）。本文件 = dev 细则。

## 流程(主 agent 逐步)

```bash
# 0. 规划:grill 拆好,写 .parallel/plan.md + 预写各 .parallel/<tid>/task.md
# 1. 渐进批量派发(一条后台命令;事件驱动:一个 agent 回执 working 才启动下一个,避免并发 recruit 撞 herdr 锁):
bash skills/workspace/scripts/par.sh wave --mode dev t-foo=@dev/a t-bar=@dev/b t-bar2=@dev/c
#    (单任务才用 par-run.sh;--launch-only 只启动不收割,供 par-wave 调用)
# 2. 各任务回调 done 后逐个 verify:
bash skills/workspace/scripts/par.sh verify t-foo --cmd "cargo test foo"
# 3. 全绿 → 汇总评估 diff 报人 → 人确认 → merge:
bash skills/workspace/scripts/par.sh merge t-foo t-bar
```

## 失败处理

| 状态 | 含义 | 主 agent 处置 |
|------|------|---------------|
| failed | 派发期失败(worktree/recruit/dispatch) | 看 stderr 原因,修环境后同 tid 重派 |
| stalled | 虚报/空转(交付信号缺) | 读 `.parallel/<tid>/` 交付物,`herdr agent prompt <pane>` 补发或升档重派(同 tid 幂等) |
| blocked | agent 上报 PAR-BLOCKED(token+终端) | 上浮报人 |
| verify-failed | retry 耗尽 | 升档重派:`par-run.sh <tid> "<更强 model>" --mode dev --attempt N+1` |
| timeout | 墙钟耗尽 | 查 pane 实况,补发或重派 |

## merge 规程

- par-merge.sh 校验 state∈{done,verified} → 打印 **checklist 三行**（state / verify.log PASS|人判豁免 /
  diffstat；脚本不替人看 diff，人确认后才该跑到 merge）→ `git merge --no-ff par/<tid>` → 清 worktree + 删分支。
- 冲突(零重叠拆分时不应发生):脚本自动 abort + rc2 → 回派原 agent(同 pane/同 worktree)rebase 修复后重跑 par-merge。
- merge 顺序:按依赖关系(零重叠时任意顺序均可)。

## discard 规程（不 merge）

极限测 / 失败波 / 明确不要合进主线时：

```bash
bash skills/workspace/scripts/par.sh discard t-foo t-bar
```

- 关任务窗（若 pane 仍在）→ `git worktree remove --force` → `git branch -D par/<tid>` → `state=discarded`。
- **不要**对烟雾弹任务跑 `par.sh merge`（会把探针文件合进 main）。
- `.parallel/<tid>/` 目录默认保留 artifact 备查；全清：`rm -rf .parallel`（仓根已 gitignore）。
