# paragent — herdr 并行 agent 技能（CLI 主 + 薄 skill）

高级 herdr 技能：把 herdr 工作台变成多 agent 并行编排面。
**CLI（`bin/par` → `par`）是唯一实现**；skill（`skills/par`）只是路由薄层。

## 五原语

| 原语 | 何时 | 一条命令 |
|---|---|---|
| **develop** 并行分支/开叉 | 多任务零文件重叠改代码 | `par wave --mode develop t1=@develop/a t2=@develop/b` → verify → 人确认 → merge |
| **research** 并行研究/分析 | 多路只读探索 | `par wave --mode research t1=@research/a t2=@research/b` |
| **review** 并行 review/审核 | 双轨交叉审 | `par wave --mode review t1=@review/a t2=@review/b`（预写 task.md） |
| **discuss** 并行合作/交流 | 主窗人控 + 右双席异步 | `par discuss open` → `discuss fire a\|b` → `discuss take\|collect` → `discuss close` |
| **triad** 三席 | 首席派发零轮询；席位看状态互注回话 | `par triad open [--mode …]` → `triad fire "题"` → `triad take\|collect` → `triad close` |

完成真源 = herdr metadata `par_result` token（**禁扫终端判完成**）。
review/research 交付 = 填实预写骨架 artifact（结构 lint 硬门禁）；triad 回话走 `relay` 闸控通道。

## 安装

```bash
git clone https://github.com/raystyle/paragent && bash paragent/scripts/install.sh
# 幂等：依赖自检（herdr/jq/git）→ ~/.paragent-home 指针 → 全局 CLI ~/.local/bin/par
gh skill install raystyle/paragent --all   # 薄 skill（路由层；CLI 不在其内）
```

## 维持

```bash
par gate            # 合并前门禁（bash -n + 全量 stub 回归）
par smoke [--live]  # 冒烟（stub 全量 + 可选 live discuss token 轮）
par nightly install # 夜间 stub smoke cron（默认 03:15）
```

## 文档

- 用法正本：`references/parallel.md`（原语卡）
- 协议细则：`references/{develop,research,review,interactive,triad}-mode.md` · `DISCIPLINE.md`
- 生产级路线：`references/production-roadmap.md`（L1/L2/L3）
