# triad-mode — 三席原语细则（chief + a/b · 状态驱动互话）

> 用法正本：`../../references/parallel.md`（原语卡）。本文件 = triad 协议正本。

入口：`par.sh triad` → `parallel/scripts/par-triad.sh`。

## 形态（三席）

| 窗 | 谁开 | agent 名 | 默认轨 |
|---|---|---|---|
| **主窗** | 人类自定（不代开） | — | 人类监督/干预 |
| **右上 chief** | `triad open` | `triad-chief` | `@dev/a`（k3@kimi） |
| **右中 a** | `triad open` | `triad-a` | `@review/a`（Opus） |
| **右下 b** | `triad open` | `triad-b` | `@review/b`（GPT 顶档） |

三席右 stack（right → down 串行 recruit）；`close-tasks` 跳过 triad，仅 `triad close` 关。

## 控制流（主控零轮询）

```text
人/主控  par.sh triad fire "题目"          # 只 prompt 首席，火即返（禁 --wait）
chief    拆题 → herdr agent prompt triad-a/triad-b "<子题+席位协议>"   # 派发即返，不 wait
席位     清旧 token → 做题 → 长文落 artifact 文件 → report-metadata 报 token
         → peer 阶段：agent wait 对方（idle|done|blocked）→ 读对方 token
         → 有异议才回话：状态闸门验目标 → agent prompt triad-chief（或 peer）
chief    被回话注入唤醒 → 综合 → report-metadata PAR-DONE triad-chief#N
人/主控  triad take [--all] [--read]       # 非阻塞；rc0 有货 / rc3 无 / rc2 无 session
         triad collect --all --read        # 兜底糖 = wait→take（席位失联时）
```

**核心转移**：等待责任在主控脚本 → 席位 agent 自己的回合内。herdr 无事件推送
（`notification` 仅桌面 toast），席位底层仍 `agent wait` 阻塞等，但主控 fire 后即自由。

## 铁规（防死循环 / 注入安全）

1. **完成真源 = `tokens.par_result`**，锚定 `triad-<role>#<首席 attempt>` + 非空结论；
   状态只做唤醒触发；扫终端不判完成。
2. **回话状态闸门（硬性）**：注入任何席之前目标 `agent_status` 须 ∈ idle|done|blocked；
   `working|unknown` **禁止注入**。**代码兜底 = `relay` 子命令**（rc5 拦，先 `agent wait` 再 relay）。
   回话路由：**异议/质疑直注对方席**（`triad-<peer>`，让对方答辩）；**定论/汇总回 chief**。
3. **回话上限**：每席每轮互注合计**最多 1 次**；报完 token 即停，禁止主动开启第 2 轮。
   **代码兜底**：relay 按 `.parallel/triad/<role>/replied-<首席att>` 标记计额（rc7 拒），fire 新轮自动清零。
4. **主窗隔离**：禁止向 `triad-chief|triad-a|triad-b` 以外的窗格 prompt。
   **代码兜底**：relay 只接受三席别名（rc4），发送者 `$HERDR_PANE_ID` 不在三席拒发（rc6）。
   chief 是独立 agent 窗格，人类可同窗打字干预（闸门保护 + herdr 串行化输入）。
   注：relay 是纪律路径的代码闸；agent 用 raw herdr 绕过属违规，不作对抗式拦截。
5. **长结论落文件**：`.parallel/triad/<role>/artifact-<att>.md`，正文只回路径
   （官方建议：宽窗口 read 有行数上限，alt-screen 内容不可恢复）。
6. **chief 不监听**：拆题派发即返；不 `agent wait` 任何席、不 collect；靠席位回注唤醒。

## mode brief（`triad open --mode`，仅换分工模板与默认轨语义，不改结构）

| mode | 分工 |
|---|---|
| `research` | 拆 2 路只读探索子题；席位禁写仓库；产出 = 结论 + artifact 路径 |
| `review` | 双席交叉审同一对象：a 找正确性问题，b 找设计/边界问题；互审对方结论后定稿 |
| `ix`（默认） | 自由议题，双席各抒后互评，首席汇总 |

## 命令

```bash
par.sh triad open [--mode research|review|ix] [--chief|--a|--b <轨|cmd>] [--force]
par.sh triad fire "题目"                 # 只派首席（附协作协议尾），火即返
par.sh triad take [chief|a|b|--all] [--read] [--json]
par.sh triad relay <triad-chief|triad-a|triad-b> "<回话>"   # 席位互注闸控通道（rc4 隔离/rc5 状态闸/rc6 主窗/rc7 上限）
par.sh triad collect [...]               # 兜底：wait→take
par.sh triad status [--json]
par.sh triad wait [chief|a|b|--any|--all] [--timeout-ms N]
par.sh triad close
```

- 席位 token 锚 = `triad-<a|b>#<首席当前 attempt>`：首席每 fire 涨号，旧轮席位 token 自动失效。
- `take` 后清 token + 归档 `.parallel/triad/<role>/archive/<attempt>-<ts>.md`（`PAR_TRIAD_ARCHIVE=0` 关闭）。
- `wait` 对首席无 token 时补问 1 次（同 attempt，不涨号）。

## 运维三行（失败时）

```text
1) cat .parallel/triad/<role>/round            # pending/busy/harvestable/tid/attempt
2) herdr pane get <pane> | jq -r '.result.pane.tokens.par_result'
3) take rc3 = 无本轮 token；席位未报 = 其回合未完成或被闸门拦
4) relay 被拦看 rc：4 隔离/自注 · 5 目标忙（先 agent wait）· 6 非三席 · 7 本轮回话额度用完
```

补救：同题再 `triad fire`（首席新 attempt，席位锚自动随涨）。
