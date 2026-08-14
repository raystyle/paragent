# 并行五原语 — 用法正本（只读本文件即可开干）

入口唯一：全局 CLI `par`（`bin/par`，`bash scripts/install.sh` 装到 PATH）→ `scripts/par-*.sh`。  
skill（`skills/par`）只路由；深钻纪律/模型才进 `references/DISCIPLINE.md` · `references/*`。

## 五原语一张表

| 原语 | 中文名 | 场景 | 布局 | 默认轨 | 主命令链 |
|---|---|---|---|---|---|
| **develop** | 并行分支/开叉 | 并行改代码（任务间**零文件重叠**） | tab + worktree | `@develop/a\|b\|c` | `wave --mode develop` → `verify` → 人确认 → `merge` |
| **research** | 并行研究/分析 | 并行只读探索 | tab | `@research/a\|b\|c` | `wave --mode research` → 收 artifact → 主控汇总 |
| **review** | 并行 review/审核 | 双轨交叉审阅 | tab | `@review/a` + `@review/b` | `wave --mode review t1=@review/a t2=@review/b`（预写 task.md） |
| **discuss** | 并行合作/交流 | 主窗人控 + 右双席异步多题 | **stack** 右双席 | 默认 Opus + GPT | `discuss open` → `fire` → `take`/`collect` → `discuss close` |
| **triad** | 三席（合成 research/review/discuss） | 首席派发零轮询；席位看状态互注回话 | **stack** 右三席 chief/a/b | chief=`@develop/a` + `@review/a\|b` | `triad open [--mode …]` → `triad fire "题"` → `triad take`/`collect` → `triad close` |

| | develop | research | review | discuss | triad |
|---|---|---|---|---|---|
| 写仓库？ | 是（worktree） | **否** | **否** | 视议题（默认可只读） | 视议题 |
| merge？ | 人确认后 `merge` | 无 | 无 | 无 | 无 |
| 完成信号 | `par_result`（`<tid>#attempt`） | 同左 | 同左 | `discuss-<role>#attempt` | `triad-<role>#<首席attempt>` |
| 关窗 | wave 默认可关任务 tab | 同左 | 同左 | **仅** `discuss close` | **仅** `triad close` |

## 口语 → 命令

```bash
# 并行分支/开叉（develop）
par wave --mode develop t-foo=@develop/a t-bar=@develop/b
par verify t-foo --cmd "cargo test …"   # 规划定的 verify
# 人确认 diff 后
par merge t-foo t-bar

# 并行研究/分析（research）
par wave --mode research t1=@research/a t2=@research/b t3=@research/c

# 并行 review/审核（一等 mode=review；只读；默认 @review 双轨）
par wave --mode review t-a=@review/a t-b=@review/b

# 并行合作/交流（discuss 两令；禁 fire 阻塞）
par discuss open
par discuss fire a "议题A"
par discuss fire b "议题B"
par discuss take --all --read          # 非阻塞；无货 rc3
par discuss collect --all --read       # 编排糖：wait→take（主控自动收）
par discuss close

# 三席（triad：合成 research/review/discuss；首席零轮询，席位看状态互注）
par triad open --mode research    # chief + a + b 右 stack 三席
par triad fire "题目"             # 只派首席；席位由首席派发、互看状态回话
par triad take --all --read       # 非阻塞；锚 triad-<role>#<首席attempt>
par triad collect --all --read    # 兜底糖：wait→take
par triad close
# 席位回话走 relay（代码闸：状态闸门/回话上限 1 次/轮/主窗隔离）；细则 triad-mode.md

# 共用
par run <tid> @develop/a --mode develop --brief "…"
par context --json | --tid <id>
par discard <tid>…                # 不 merge，卸 worktree
par close-tasks | close-side
par gate                          # 合并前 M-4：run-all + layout-contract
par nightly install|run|status    # 夜间 M-1：stub smoke + 日志落盘
par help
```

## 矩阵轨（记 a/b/c 即可）

| 矩阵 | a | b | c |
|---|---|---|---|
| `@develop` | k3@kimi | grok-4.5 | glm-5.2@claude |
| `@research` | grok-4.5 | kimi-for-coding | deepseek-pro@codex |
| `@review` | opus-4.8@claude | gpt-5.6-sol@codex | — |
| `@speed` | kimi-hs@pi | flash@codex | — |

远程会话：`export PAR_MATRIX_PROFILE=remote`（`@develop/*`→claude glm，`@research/*`→deepseek-pro；`@review` 不变）。  
表文件：`references/matrix.json` · `references/matrix-remote.json`。也可裸 model-cmd。

## 完成协议（五原语共用 · 禁扫终端）

子 agent 最后动作：

```bash
herdr pane report-metadata "$HERDR_PANE_ID" --source parallel \
  --token "par_result=PAR-DONE <tid>#1 <一句话结论>"
```

wave/run 锚 `<tid>#<attempt>`；discuss 锚 `discuss-<role>#<attempt>`；triad 锚 `triad-<role>#<首席attempt>`。  
编排只认 `pane get → tokens.par_result`；`agent wait` 仅唤醒。  
无 token **永不** done；交付另要 artifact 相对 baseline 更新（develop 另要 worktree commit）。

## 主控选型（30 秒）

1. 要**改代码多路** → **develop**（并行分支/开叉）  
2. 要**只读摸清/调研** → **research**（并行研究/分析）  
3. 要**双模型交叉审 diff/提交** → **review**（并行 review/审核，@review 双轨）  
4. 要**主窗边聊边派、异步多题** → **discuss**（并行合作/交流，fire/take，勿 wait 齐等）  
5. 要**首席派发 + 席位互看状态自驱动**（不想主控轮询）→ **triad**（三席，合成 research/review/discuss；`triad open --mode …`）

不确定路径：先 `par context --json`。

## 运维三行（失败时）

```text
1) cat .parallel/<tid>/state  或  .parallel/discuss-claude/round · discuss-codex/round
2) herdr pane get <pane> | jq -r '.result.pane.tokens.par_result'
3) 退出码：take rc3 = 无本轮 token；wait 非 0 = 停了但没 report-metadata（discuss 会补问 1 次）
```

补救：同题再 `discuss fire`（新 attempt）或子席执行文末 `report-metadata` 指令。

## 生产级别（1.1.0）

| 档 | 含义 | 现状 |
|---|---|---|
| **L1** 主路径可用 | token 真源 + stub 绿 + live 冒烟 | **齐** |
| **L2** 生产加固 | 补问 · help · 串台测 | **齐** |
| **L3** 门禁 | version-check · smoke · archive · install --check | **齐** |
| **维持** | `par gate` · `par nightly` | **脚本齐** |

路线图正本（进度 + 待办）：`references/production-roadmap.md`。

## 深链（默认不读）

| 文件 | 何时打开 |
|---|---|
| `references/production-roadmap.md` | **生产级定义 / 分期 / 验收门禁** |
| `references/DISCIPLINE.md` | 完成门禁 / 人机边界 / 失败重派 |
| `references/develop-mode.md` | develop verify 失败、worktree 细节 |
| `references/research-mode.md` | research explorer 契约、artifact 结构 |
| `references/review-mode.md` | review 审阅契约、P0/P1 交付 |
| `references/interactive-mode.md` | discuss 两令边界、collect 语义 |
| `references/triad-mode.md` | triad 三席协议（状态闸门/回话上限/防 ping-pong） |
| `references/models.md` | 换模型、远程矩阵、档位 |
| `references/planning.md` | grill 规划清单 |

## 边界

| 层 | 职责 |
|---|---|
| herdr | pane / session / agent runtime |
| **workspace（本 skill）** | `par` 路由 + 矩阵 + token 完成 |
| center | mesh / Vault / SSH 证（本 skill 不签发） |
