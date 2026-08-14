# 并行原语 · 生产级别路线图（终版）

> 正本用法：`../../references/parallel.md`。  
> 本文只定：**什么叫生产级**、**现在到哪**、**还差什么**。  
> 验收 = **代码门禁 + 回归 + 确定产物**（退出码 / 标记 / 日志），不靠提示词告诫。  
> **冻结日：2026-08-07 · skill 0.6.10** — 阶段 A/B/C 收工；后续只走 §9 挂载/增强。

---

## 1. 生产级定义（三档 · 定案）

| 档 | 标签 | 含义 | 能否标「生产」 |
|---|---|---|---|
| **L1** | 主路径可用 | 入口通；`par_result` 真源硬；stub 绿；本机 live 冒过烟 | **可上生产主路径** |
| **L2** | 生产加固 | 失败可观测/可重试；防误收串台；关键路径自动回归 | **可标生产级** |
| **L3** | 完整生产（门禁） | 多端指纹 · smoke · 归档 · 装机 check | **代码侧完整生产** |
| **维持** | 挂载在跑 | nightly cron · 值守 live · 合并前 gate 习惯 | **完整生产在维持** |

**硬规则（五原语共用）**

1. 完成真源 = `tokens.par_result` 锚定 `<tid>#<attempt>` + 非空结论（**禁**仅靠 `agent_status` / 扫终端）。  
2. 入口唯一：全局 CLI `par`（`bin/par`）；skill 只路由。  
3. 布局：wave/run 默认 tab；discuss 仅 stack 右双席且只 `discuss close`。  
4. 错误靠脚本退出码 + 标记文件，不靠「记得要 report」。

---

## 2. 进度总表（2026-08-07 · 0.6.10）

| 层 | 状态 | 版本/入口 |
|---|---|---|
| **L1** 主路径 | **完成** | 阶段 A |
| **L2** 生产加固 | **完成** | **0.6.8** 阶段 B |
| **L3** 门禁脚本 | **完成** | **0.6.9** 阶段 C |
| **维持脚本** | **完成** | **0.6.10** `par gate` · `par nightly` |
| **nightly cron 挂载** | **完成 2026-08-13** | `par nightly install`（03:15 本地，首跑 PAR-NIGHTLY-PASS） |
| **值守 live smoke** | **完成 2026-08-13** | `par smoke --live`（M-2）PAR-SMOKE-PASS |
| **remote 版本例行** | **完成 2026-08-13** | `par version-check --remote`（M-3）全树 0.7.3；mac 不可达（No route to host） |

### 五原语档位

| 原语 | 档 | 依据 | 仍开缺口 |
|---|---|---|---|
| **develop** | **L2** | worktree + token + artifact + verify/merge；wave 测 | merge 人环（刻意）；live 非常态化 |
| **research** | **L2** | 只读 + token + artifact；wave 测 | explorer 契约靠预写 task |
| **review** | **L2** | 一等 `--mode review`；双轨测 + live 双轨 done | P0/P1 模板靠约定；nightly live 未挂 |
| **discuss** | **L3−** | par_result · 补问 · 串台/重复 take · archive · smoke | cron 未挂；archive 检索未做 |
| **triad**（0.7.0） | **L1+** | 三席 chief+a/b · 协议尾正本（triad-mode.md）· stub 绿（test-triad）· token 锚 `triad-<role>#<首席attempt>` · **live 冒烟过**（fire→双席报 token→回注 chief→take 3/3 归档）· **闸门代码兜底**（0.7.3 relay rc4/5/6/7，P-5） | 席位守协议率未量化 |

**总判：可标生产级（L2）；L3 代码门禁齐；完整生产「在维持」差 cron/习惯挂载。**

---

## 3. 验收清单（已关闭）

### L1

- [x] 文档正本一条命令链（`parallel.md`）  
- [x] `par_result` 同源（含 discuss 0.6.6）  
- [x] stub：`scripts/tests/run-all.sh` ALL PASS  
- [x] 本机 live 冒烟：discuss fire→take rc3→collect；review 双轨 done  
- [x] 失败三行：§5 · `par help`

### L2（0.6.8）

| ID | 项 | 状态 |
|---|---|---|
| L2-1 | discuss 无 token 补问 1 次 | [x] |
| L2-2 | attempt 串台 + 重复 take | [x] |
| L2-3 | review/research artifact grace | [x] |
| L2-4 | `par help` 短卡 | [x] |
| L2-5 | layout-heal 修台链 | [x] |

### L3（0.6.9）

| ID | 项 | 入口 | 状态 |
|---|---|---|---|
| L3-1 | 多端版本/指纹 | `par version-check [--remote]` | [x] |
| L3-2 | smoke stub + 可选 live | `par smoke [--live]` | [x] |
| L3-3 | discuss take 归档 | `discuss-*/archive/<attempt>-<ts>.md` | [x] |
| L3-4 | 装机只读 | `install.sh --check` · `--dry-run` | [x] |

### 维持入口（0.6.10）

| ID | 项 | 入口 | 状态 |
|---|---|---|---|
| M-4 | 合并前门禁 | `par gate`（`--quick` / 默认 / `--full`） | [x] **脚本齐**；合并前跑 |
| M-1 | nightly 脚本 + 日志 | `par nightly run\|status` · 日志 `~/.local/state/workspace-par/nightly/` | [x] **脚本齐** |
| M-1b | **nightly cron 挂载** | `par nightly install`（默认 03:15） | [x] **2026-08-13 已挂**（首跑 PASS） |

---

## 4. 分期（历史 · 不再重开字母）

| 阶段 | 目标 | 结果 |
|---|---|---|
| **A** | 锁 L1 | 完成 · 维持 |
| **B** | 冲 L2 | **完成 · 0.6.8** |
| **C** | 冲 L3 门禁 | **完成 · 0.6.9** |
| **—** | 维持脚本 | **完成 · 0.6.10**（gate + nightly 工具） |

行为协议不变则**不**再开阶段 D；只勾 §9。

---

## 5. 主控运维三行（失败时）

```text
1) cat .parallel/<tid>|discuss-*/state 与 round（discuss）
2) herdr pane get <pane> | jq .result.pane.tokens.par_result
3) 退出码：take rc3=无本轮 token；wait 非0=停了但没 report-metadata
```

补救：同议题再 `discuss fire`（新 attempt）或子席执行文末 report 指令。

合并前：

```bash
par gate
```

---

## 6. 非目标（明确不做）

- 不把 discuss 改成第三种 wave mode。  
- 不引入默认布局 hook。  
- 不在本 skill 签发 mesh/SSH（center）。  
- 不为「绝对完整」无限扩家目录白名单。  
- 不把远端无值守 live CI 机器人做成 skill 默认。

---

## 7. 版本纪律

| 变更 | 版本 |
|---|---|
| 文档/路线图 only | patch |
| 完成协议/门禁行为 | patch 或 minor + CHANGE 摘要 |
| 破坏性 CLI | minor + 正本迁移说明 |

---

## 8. 一句话定案（今日收工）

1. **生产级：已到**（L2 @ 0.6.8；L3 门禁 @ 0.6.9；gate/nightly 工具 @ 0.6.10）。  
2. **nightly cron 已挂**（2026-08-13，03:15 本地）：例行 `par nightly status` 看 last=PASS/FAIL。  
3. **合并前习惯**：`par gate`（M-4 脚本已齐）。  
4. **其余**（P/O）进 §9，无 deadline。

---

## 9. 待办 backlog（收工后 · 只记账）

> 做完勾掉并 patch 说明。**不做** §6。

### 9.1 维持挂载（优先）

| ID | 项 | 怎么勾掉 | 状态 |
|---|---|---|---|
| **M-1b** | **nightly cron** | `par nightly install`；次日 `status` 见 last=PASS/FAIL | [x] **2026-08-13** 已挂（03:15；首跑 PASS；次日复验 status） |
| M-2 | 值守 live smoke | 有会话：`par smoke --live` 跑通一轮 | [x] **2026-08-13** PAR-SMOKE-PASS（discuss 双席 token 轮 OK） |
| M-3 | remote 版本例行 | 刷 skill 后 `par version-check --remote` 无意外 DRIFT | [x] **2026-08-13** 本机 5 树 + lan-home-linux 2 树全 0.7.3；mac 不可达属主机离线（center host-check 域） |
| M-4 | 合并前 gate | 习惯：改并行相关必 `par gate` | [x] 工具齐；习惯自持 |

手工/立即等价（不装 cron 时）：

```bash
par nightly run          # 等价一次 stub smoke + 落盘
par nightly status
# 真正挂载（待做）:
par nightly install      # 默认 15 3 * * * 本地
par nightly uninstall    # 卸
```

### 9.2 原语增强（按需）

| ID | 项 | 状态 |
|---|---|---|
| P-1 | review P0/P1 模板写死 | [x] **0.7.4**（2026-08-13）：骨架预写 artifact.md + par_delivery_met review 结构 lint 硬门禁 |
| P-2 | research explorer 可校验清单 | [x] **0.7.5**（2026-08-13）：骨架预写 + par_delivery_met research 三节 lint（结论/证据/存疑） |
| P-3 | discuss archive list/汇总 | [x] **0.7.6**（2026-08-13）：`discuss archive [--json]` 清单/汇总（rc3=无归档） |
| P-4 | merge checklist 三行（不自动化合并） | [x] **0.7.7**（2026-08-14）：par-merge 逐任务打印 state/verify/diffstat 三行 |
| P-5 | triad 闸门代码兜底（live 双席共识：状态闸门/回话上限/主窗隔离仅提示词层；候选=fire 时脚本侧写 per-seat replied 标记、take 前脚本验目标态） | [x] **0.7.3**（2026-08-13）：relay 子命令代码闸（rc4/5/6/7）+ fire 重置 replied 标记；take 验态经评估**否定**（席位报 token 后进 peer 阶段仍 working，锚定收割本就安全）并固化回归用例 take-peer-phase-working-ok |

### 9.3 观测

| ID | 项 | 状态 |
|---|---|---|
| O-1 | live 踩失败三行文案 | [x] **0.7.8**（2026-08-14）：smoke FAIL 附排查三行（日志路径/live 高发因/stub 单跑） |
| O-2 | smoke 日志统一落盘约定 | [x] **0.7.8**（2026-08-14）：smoke 每次 `<ts>.log`+`last.log`+stage out 落 `~/.local/state/workspace-par/smoke/`（同 nightly 形制） |

### 9.4 延后

- 远端 CI 机器人 · 家目录白名单扩面 · discuss 并 wave — 见 §6。

---

## 10. 今日进度清单（关闭）

| 项 | 结果 |
|---|---|
| 阶段 A L1 | 完成 |
| 阶段 B L2（0.6.8） | 完成 |
| 阶段 C L3 门禁（0.6.9） | 完成 |
| M-4 `par gate`（0.6.10） | 完成 · 全量 `PAR-GATE-PASS` 已验 |
| M-1 nightly **脚本**（0.6.10） | 完成 |
| M-1b nightly **cron** | **完成 2026-08-13**（03:15 已挂，首跑 PASS） |
| 工作台清理 | 完成（discuss 关 · layout-heal · 三 space 各 1 主席） |
| 路线图终版 | **本文** |

**维持已挂载（2026-08-13）**：nightly cron 03:15 · M-2 live smoke PASS · M-3 全树 0.7.3。
§9 剩余 = P/O 增强项，无 deadline。
