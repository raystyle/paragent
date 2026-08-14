---
name: par
license: MIT
description: "herdr 并行 agent 编排（薄路由；实现=全局 CLI `par`）：五原语 develop 并行分支/research 研究/review 审核/discuss 交流/triad 三席。TRIGGER when: 并行分支开叉/合作交流/研究分析/review 审核、wave/run/discuss/triad、par_result、并行 merge/discard。BLOCKING: 一切并行编排除查状态外一律 `par` CLI（references/parallel.md 为正本）。SKIP: 工作台修台/布局/mirror（workspace skill）、凭据/Vault（center）。"
compatibility: "herdr 0.7.5+、jq、git、python3；先 bash scripts/install.sh 装 CLI。"
metadata:
  author: rayh4c
  version: "1.1.0"
  user-invocable: "true"
  form: routing
---

# par skill（薄路由 · 实现 = 全局 CLI `par`）

> 本 skill 只路由；一切执行走 `par <verb>`（`bin/par`，install.sh 装到 PATH）。

## 铁律

1. **完成真源 = `tokens.par_result`**（锚 `<tid>#<attempt>`）；禁扫终端判完成。
2. **fire 即返**；收割 `take`（非阻塞 rc3=无货）/ `collect`（wait→take 兜底糖）。
3. triad 席位回话只走 `par relay`（闸控：rc4 隔离 / rc5 状态闸 / rc6 主窗 / rc7 上限）。
4. review/research 交付 = 填实预写骨架 artifact（结构 lint 硬门禁，缺节不收）。
5. merge 不自动化：`par merge` 只过 checklist（state/verify/diffstat），人确认才跑。
6. 零明文 key；模型轨看 `references/models.md`。
7. 交互席（discuss/triad）仅 `discuss close` / `triad close` 关；`close-tasks` 跳过它们。

## 路由

| 要做什么 | 命令 |
|---|---|
| 并行分支/开叉 develop | `par wave --mode develop t1=@develop/a t2=@develop/b` → `par verify <tid> --cmd …` → 人确认 → `par merge` |
| 并行研究/分析 | `par wave --mode research t1=@research/a t2=@research/b` |
| 并行 review 双轨 | `par wave --mode review t1=@review/a t2=@review/b`（预写 task.md） |
| 单任务 | `par run <tid> @develop/a [--mode …] [--brief "…"]` |
| 并行交流 discuss | `par discuss open` → `par discuss fire a\|b "…"` → `par discuss take\|collect` → `par discuss close` |
| 三席 triad | `par triad open [--mode …]` → `par triad fire "题"` → `take\|collect` → `par triad close` |
| 归档回看 | `par discuss archive [--json]` |
| 自发现 | `par context [--json] [--tid <id>]` |
| 丢弃任务 | `par discard <tid>…` |
| 清任务窗 | `par close-tasks` |
| 门禁/冒烟 | `par gate [--quick\|--full]` · `par smoke [--live]` |
| 夜间值守 | `par nightly install\|run\|status` |
| 装机/版本 | `par install` · `par version-check [--remote]` |

## 深链（按需）

`references/parallel.md`（正本原语卡）· `DISCIPLINE.md` · `{develop,research,review,interactive,triad}-mode.md` · `models.md` · `production-roadmap.md`
