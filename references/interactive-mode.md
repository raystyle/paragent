# interactive-mode — 并行合作/交流（两令制）

> 用法正本：`../../references/parallel.md`（四原语卡）。本文件 = discuss 细则。

入口：`par.sh discuss` → `parallel/scripts/par-discuss.sh`。

## 形态（三窗）

| 窗 | 谁开 | 默认 |
|---|---|---|
| **主窗** | 人类自定（不代开） | 编排中枢 |
| **右上 a** | `discuss open` | Claude Opus 4.8 |
| **右下 b** | `discuss open` | Codex GPT 顶档 |

## 两令制（唯一正确节奏）

**禁止**把「派发 + 齐等收割」合成**一条**长 command。必须拆成两个命令，才能异步渐进、并行多任务：

| 令 | 命令 | 行为 | 阻塞？ |
|---|---|---|---|
| **1 fire** | `par.sh discuss fire a\|b "…"` | **只派发**，火即返 | 否 |
| **2 take** | `par.sh discuss take [--all] [--read]` | **只收**已 READY | 否（无则 rc3） |

**编排糖（非第三令）**：`par.sh discuss collect [--all\|a\|b] [--read]` = `wait` → `take`。  
主控「派完自动收」用它；**不**把阻塞塞进 `fire`（fire 永异步）。

```text
主窗  fire a ──► working ──┐
     fire b ──► working ──┤
                          │  （可立刻 fire 第三题 / 干别的）
     take --read  ◄───────┘  谁 READY 先吐谁
     fire a "跟进…"           另一席仍可 busy
     take --all --read
     ── 或主控终验 ──
     collect --all --read     # wait 双席 → take（你不必再说「收」）
```

```bash
par.sh discuss open
# ── 令1：连发 ──
par.sh discuss fire a "议题A"
par.sh discuss fire b "议题B"
# ── 令2：收割（非阻塞）──
par.sh discuss take --read           # rc0 有货 · rc3 全 busy（稍后再 take）
par.sh discuss take --all --read     # 本拍所有 READY
par.sh discuss fire a "跟进A"        # 可继续派，不必等 b
par.sh discuss take b --read         # 指定席
# ── 编排糖：主控派完自动收（双席终验）──
par.sh discuss collect --all --read  # = wait all + take --all --read
```

**反模式（禁止）**

```bash
# 一个 command 里 wait all / 长阻塞 = 同步 barrier，毁并行
par.sh discuss prompt a "…" && par.sh discuss prompt b "…" && par.sh discuss wait all
# fire 带 --wait（已禁）；阻塞只走 wait / collect
```

| 旧名 | 新名 |
|---|---|
| `prompt`（默认无 --wait） | **`fire`** |
| `poll` / `wait --any` | **`take`**（非阻塞收） |
| `wait all` | 仅收尾，讨论期禁用 |

### take 语义（完成真源 = `par_result`，与 wave 同源）

| 状态 | 含义 |
|---|---|
| READY / harvestable | 本轮 `tokens.par_result` 锚定 `discuss-<role>#<attempt>` **且** 非空结论（PAR-DONE/BLOCKED） |
| busy | working、pending 未过闸、或 fire 后 stale idle（防误收） |
| rc | **0** 有收成 · **3** 无本轮 token · **2** 无 session |

`fire` 会：clear 旧 token、写 round（tid/attempt）、消息尾追加 report-metadata 指令。  
`take --read` **仅佐证**（扫终端不判完成）；`take` 后清 harvestable + token，并归档  
`.parallel/discuss-*/archive/<attempt>-<ts>.md`（`PAR_DISCUSS_ARCHIVE=0` 关闭）。  
归档回看：`discuss archive [--json]`（清单/汇总，逐条 role/attempt/时间/结论；rc3=无归档）。  
子席最后动作必须：

```bash
herdr pane report-metadata "$HERDR_PANE_ID" --source parallel \
  --token "par_result=PAR-DONE discuss-claude#1 <一句话>"
```

## 开席 / 关席

```bash
par.sh discuss open [--a @review/a] [--b @review/b]
par.sh discuss status [--json]
par.sh discuss close                 # 仅显式关右席
```

`close-tasks` **跳过** discuss。兼容：`prompt`/`poll`/`wait` 仍可用，但文档与主路径以 **fire/take** 为准。
