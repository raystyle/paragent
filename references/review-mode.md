# review-mode — 并行 review/审核细则

> 用法正本：`../../references/parallel.md`（四原语卡）。本文件 = review 细则。

## 一等 mode

```bash
par.sh wave --mode review t-a=@review/a t-b=@review/b
# 等价语义：只读、无 worktree、tab 布局、交付 artifact.md + par_result
# 默认轨：@review/a = Opus · @review/b = GPT
```

**不要**再写 `wave --mode research … @review/*`（旧写法仍可用 research 轨，但 review 原语应走 `--mode review`）。

## 契约（预写进 task.md）

```markdown
你是只读审阅 agent。除本任务交付外 **严禁** 改仓库/系统状态。
**唯一允许写**: `.parallel/<tid>/artifact.md` + 最后 report-metadata 完成 token。
- 高效：并行读 diff / 关键文件 / 测试与文档
- 结论写 artifact.md：填实预写骨架（五节固定标题，缺一门禁不收）：
  ## 结论（通过|有条件通过|不通过）→ ## P0 / ## P1（每条 文件:行号 — 问题 — 证据）
  → ## 存疑 → ## 证据
- 完成上报: herdr pane report-metadata "$HERDR_PANE_ID" --source parallel \
    --token "par_result=PAR-DONE <tid>#1 <一句话结论>"
```

**模板写死（0.7.4，P-1）**：首 launch 骨架预写进 `artifact.md`（基线前，填实才算本轮交付）；
`par_delivery_met` 对 review 加结构 lint——`## 结论 / ## P0 / ## P1 / ## 存疑 / ## 证据`
五节缺一 → 交付门禁不过（质问 → 仍缺 → stalled）。
## 与 research 的差别

| | research | review |
|---|---|---|
| mode | `research` | **`review`** |
| 默认轨 | `@research/*` | **`@review/a` + `@review/b`** |
| 产出侧重 | 探索结论 / 多路分歧 | **门禁判定 + P0/P1** |
| worktree | 无 | 无 |
| merge | 无 | 无 |

## 主控流程

1. 预写各 `.parallel/<tid>/task.md`（范围：commit / PR / 工作区 diff / 文件列表）。  
2. `par.sh wave --mode review t-a=@review/a t-b=@review/b`。  
3. 收齐 artifact → 交叉比对 → 汇总报人。  
4. 不 merge；改代码走 **develop** 原语。
