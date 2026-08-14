# models — 拷问阶段模型取证选择（三家收敛矩阵）

> **归属**：workspace 并行原语（`scripts/par.sh` / `parallel/` 载荷）的模型目录单点。**拷问阶段每个任务的档位（model-cmd）必须从本矩阵选**——不写矩阵外的型号，不凭记忆写端写法。
> **收敛决策**：四类锁定矩阵——**极速** · **开发** · **审阅** · **研究**（见下）。CPA 三端（cc/cx/pi）仍作 worker 备用写法；主派选跟锁定矩阵。  
> **档案**：`PAR_MATRIX_PROFILE=local`（默认·主控满矩阵）| `remote`（远程 CPA 子集，见下「远程矩阵」）。轨前缀 `@remote/…` / `@local/…` 可单次覆盖。  
> **端写法纪律**：claude=`claude --model '<id>'`；codex=`codex -m <id>`；pi=`pi --model <供应商>/<id>`；原生：`grok -m …` / `kimi -m kimi-code/…`（配置键带 `kimi-code/` 前缀）。

## 远程矩阵（Remote · CPA 子集 · 与 agent-cli-ensure 对齐）

远程机（mac/linux mirror 等）**ensure 只固化 claude / codex / pi**，通常 **无 kimi / grok 原生**。远程派发用档案 **`remote`**，**不要**假设主控三轨：

| 矩阵 | 远程锁定（唯一或双轨） | model-cmd | 端 |
|---|---|---|---|
| **极速** | **仅** deepseek flash | `codex -m deepseek-v4-flash-cx` | codex |
| **开发** | **仅** GLM 5.2 @ Claude Code | `claude --model 'glm-5.2-cc[1m]'` | claude |
| **研究** | **仅** DeepSeek Pro @ Codex | `codex -m deepseek-v4-pro-cx` | codex |
| **审阅** | **同主控双轨** | opus @ claude · gpt-5.6-sol @ codex | claude + codex |

```bash
# 远程会话整波
export PAR_MATRIX_PROFILE=remote
par.sh wave --mode research t1=@research/a          # → deepseek-pro@codex
par.sh wave --mode develop      t1=@develop/a               # → glm-5.2@claude
par.sh run  t-fast @speed/a --mode research         # → flash@codex

# 或单次前缀（不改 env）
par.sh run t1 @remote/develop/a --mode develop
par.sh run t2 @remote/review/b                      # 审阅 B 仍 gpt
```

- 远程表：`parallel/references/matrix-remote.json`（`@speed/*` `@develop/*` `@research/*` 别名均收敛到上表唯一轨）。  
- **主控**仍用默认 local 满矩阵（下节）；远程不要派 `@develop/a` 期望 k3——remote 下 a/b/c 都是 glm。  
- 远程 agent 就绪：`agent.sh ensure <host>` 装 claude+codex（+pi 可选）；**不要求** kimi/grok。

## 极速矩阵（派选锁定 · 主控 local · 2026-08-05 串行实弹）

两个极速模型各锁 **一端**，拷问/并行 **只写下列 model-cmd**（勿换端「以为更快」）。

| 极速模型 | 锁定端 | model-cmd（唯一） | 串行实测 | 备注 |
|---|---|---|---|---|
| **kimi-for-coding-highspeed** | **pi** | `pi --model kimi/kimi-for-coding-highspeed-pi` | ~8.5s ping OK | 编码向极速；**不用** cc/cx |
| **deepseek-v4-flash** | **codex** | `codex -m deepseek-v4-flash-cx exec --skip-git-repo-check -c model_reasoning_effort=low '…'` | ~4.4s ping OK | 冲刺/批阅极速；**必须** `effort=low`；**不用** cc/pi |

```bash
# kimi 极速（pi）
pi --model kimi/kimi-for-coding-highspeed-pi -p '…'

# deepseek flash 极速（codex）
codex -m deepseek-v4-flash-cx exec --skip-git-repo-check \
  -c model_reasoning_effort=low '…' </dev/null
```

> 同日全端对照（仅参考，**不派选**）：  
> flash：cc 2.5s / **cx-low 4.4s** / pi 5.4s；highspeed：cc 5.9s / cx-low 5.9s / **pi 8.5s**。  
> 锁端为分散限流与角色默认，不是「全网最低延迟」。

## 审阅矩阵（Review · 双轨锁定）

正式代码审阅 / 裁决 / 合并前看 diff：**双轨固定**，不混极速档。  
（CPA 原生 Claude Opus / GPT；别名以 gateway 模板为准。）

| 轨 | 端 | 型号 | model-cmd（唯一） | 用途 |
|---|---|---|---|---|
| **A · Opus 4.8** | **claude** | `claude-opus-4-8-cc` | `claude --model 'claude-opus-4-8-cc[1m]'` | 稳、深、长上下文审 diff |
| **B · GPT 顶档** | **codex** | `gpt-5.6-sol-cx`（当前 CPA 最高 GPT） | `codex -m gpt-5.6-sol-cx` | 另一供应商交叉审 |

```bash
# Review 轨 A — Claude Code Opus 4.8
claude --model 'claude-opus-4-8-cc[1m]' -p '…'

# Review 轨 B — Codex 最高 GPT（5.6 sol）
codex -m gpt-5.6-sol-cx exec --skip-git-repo-check '…' </dev/null
```

- **双轨并行**：重要 PR 可同波 A+B 各一 reviewer（不同端×不同供应商，分散限流）。  
- **GPT 顶档漂移**：若 CPA 上线更高 `gpt-*-cx`，更新本表 B 行别名后再派；拷问时不写记忆中的旧号。  
- **不用** flash / kimi-hs 顶正式审阅；极速只做粗滤。

## 研究矩阵（Research · 三轨锁定）

并行研究/分析 / 广搜 / 多路 explorer：**三轨固定**（不同端×供应商，便于同波分散）。

| 轨 | 端 | 型号 | model-cmd（唯一） | 用途 |
|---|---|---|---|---|
| **A · Grok** | **grok** | `grok-4.5` | `grok -m grok-4.5 -p '…'` | 广搜、推理、跨源综合 |
| **B · Kimi K2.7 Code** | **kimi** | `kimi-for-coding`（键 **`kimi-code/kimi-for-coding`**） | `kimi -m kimi-code/kimi-for-coding -p '…'` | 代码向研究、仓库/API 检索 |
| **C · DeepSeek Pro** | **codex** | `deepseek-v4-pro-cx` | `codex -m deepseek-v4-pro-cx` | 快/广研究、第三条供应商交叉 |

```bash
# Research 轨 A — Grok 4.5（08-05 叠窗 ~7.6s OK）
grok -m grok-4.5 -p '…'

# Research 轨 B — Kimi K2.7 Code（08-05 叠窗 ~4.7s OK）
kimi -m kimi-code/kimi-for-coding -p '…'

# Research 轨 C — DeepSeek V4 Pro @ Codex
codex -m deepseek-v4-pro-cx exec --skip-git-repo-check '…' </dev/null
```

- **三轨并行**：研究 wave 默认可 A+B+C（或按题选 2～3 路）；**tab 布局**（每任务一 tab）。  
- **勿**写裸 `kimi -m kimi-for-coding`；锁 **`kimi-code/kimi-for-coding`**。  
- **勿**用 highspeed 顶研究；pro 走 **codex 端**（非 pi）。  
- grok 仅 `grok-4.5`；换代改 A 行再派。

## 开发矩阵（Dev · 三轨锁定）

并行分支/开叉 / 实现 / worktree worker：**三轨固定**（kimi 深写 + grok 对照 + claude/glm 稳写）。

| 轨 | 端 | 型号 | model-cmd（唯一） | 用途 |
|---|---|---|---|---|
| **A · Kimi K3** | **kimi** | `k3`（键 **`kimi-code/k3`**） | `kimi -m kimi-code/k3 -p '…'` | 主实现、重构、复杂代码 |
| **B · Grok 4.5** | **grok** | `grok-4.5` | `grok -m grok-4.5 -p '…'` | 另一供应商交叉实现 / 补洞 |
| **C · GLM 5.2** | **claude** | `glm-5.2-cc` | `claude --model 'glm-5.2-cc[1m]'` | 稳写、长上下文、第三供应商 |

```bash
# Dev 轨 A — Kimi K3（08-05 叠窗冒烟 ~26s OK）
kimi -m kimi-code/k3 -p '…'

# Dev 轨 B — Grok 4.5（08-05 叠窗冒烟 ~7.2s OK）
grok -m grok-4.5 -p '…'

# Dev 轨 C — GLM 5.2 @ Claude Code
claude --model 'glm-5.2-cc[1m]' -p '…'
```

- **三轨并行**：develop wave 默认可 A+B+C 拆任务（**零文件重叠**）；一律 **tab 布局** + worktree（见 parallel 布局纪律）。  
- **勿**写裸 `kimi -m k3`；256k 变体 `kimi-code/k3-256k` 非默认。  
- **极速写码**仍用极速矩阵 kimi-hs@pi；**K3 / GLM 是开发主力**，不是 highspeed。

## 基准矩阵（7 模型 × 3 端可用 · 21 格 · CPA 备用）

| 基准模型 | claude 端 | codex 端 | pi 端 | 延迟注记 |
|---|---|---|---|---|
| glm-5.2 | **`glm-5.2-cc[1m]`（开发 C 轨）** | `glm-5.2-cx` | `glm/glm-5.2-pi` | 07-28: 9s/4s/15s |
| glm-5-turbo | `glm-5-turbo-cc`（**无 [1m]**） | `glm-5-turbo-cx` | `glm/glm-5-turbo-pi` | 07-28: 13s/4s/11s |
| k3 | `k3-cc[1m]` | `k3-cx` | `kimi/k3-pi` | **开发锁 kimi-code/k3**；07-28 worker 7s/4s/8s |
| kimi-for-coding（**K2.7 Code**，256k） | `kimi-for-coding-cc` | `kimi-for-coding-cx` | `kimi/kimi-for-coding-pi` | **研究锁 kimi CLI**；07-28 worker 9s/3s/8s |
| kimi-for-coding-highspeed | `…-cc` | `…-cx` | **`kimi/…-pi`（极速锁）** | 08-05 pi ~8.5s |
| deepseek-v4-pro | `deepseek-v4-pro-cc[1m]` | **`deepseek-v4-pro-cx`（研究 C 轨）** | `deepseek/deepseek-v4-pro-pi` | 07-28: 4s/4s/4s |
| deepseek-v4-flash | `…-cc[1m]` | **`…-cx`（极速锁）** | `deepseek/…-pi` | 08-05 cx-low ~4.4s |

> 验证方法：`claude --model '<id>' -p 'reply OK'` / `codex -m <id> exec --skip-git-repo-check -c model_reasoning_effort=low 'reply OK' </dev/null` / `pi --model <供应商>/<id> -p 'reply OK'`。  
> **codex 陷阱**：信任目录或 `--skip-git-repo-check`；stdin 断流；极速务必 `effort=low`（默认 high 会拖慢）。  
> 复验串行、端间间隔，避免限速假失败。

## 角色 × 档位（拷问时按此映射）

| 角色 | fast（极速/粗滤） | medium（常规） | slow / 正式 | deep / 满配 |
|---|---|---|---|---|
| **Coder** | 极速：kimi-hs@pi | 开发 **B/C**：grok-4.5 · glm-5.2@claude | 开发 **A**：`kimi -m kimi-code/k3` | 三轨 A+B+C（复杂波） |
| **Reviewer** | flash@codex（effort=low） | 审阅 **B**：`gpt-5.6-sol-cx` | 审阅 **A**：`claude-opus-4-8-cc[1m]` | 双轨 A+B（重要 PR） |
| **Researcher** | 研究 **B**：`kimi-code/kimi-for-coding` | 研究 **A/C**：grok-4.5 · deepseek-pro@codex | 默认三轨 A+B+C | 同左 |

- **分派梯度**：Coder 简单→极速；常规→**开发三轨**；**Reviewer 正式审 = 审阅双轨**；**Researcher = 研究三轨**。  
- **并行分散限流**：Coder→**k3@kimi · grok · glm@claude**（快可 hs@pi）· Reviewer→opus + gpt · Researcher→**grok · kimi-for-coding · deepseek-pro@codex**。

## 端写法规则（别名）

- CPA worker：`{base}-{client}` · `cc`=Claude Code · `cx`=Codex · `pi`=Completions  
- Claude Code：`{alias}[1m]`（`glm-5-turbo-cc`、`kimi-for-coding(-highspeed)-cc` 无 `[1m]`）  
- pi：`{供应商}/{alias}`，供应商 ∈ `glm`/`kimi`/`deepseek`  
- **原生 CLI**：`grok -m grok-4.5` · `kimi -m kimi-code/k3` · `kimi -m kimi-code/kimi-for-coding`  
- 型号发现：`pi --list-models` / `grok models` / CPA `…/v1/models`（token=Vault `agent/cpa`）

## 端能力表（Harness · 锁定端）

拷问/派发前按端能力写 model-cmd，**勿**用错 prompt 旗标或 stdin 习惯。  
本机探测：`agent.sh harness --json`（`present` = CLI 是否在 PATH；能力列为静态契约）。

| 端 | CLI | 非交互 / prompt | stdin | trust / skip-git | worktree | 备注 |
|---|---|---|---|---|---|---|
| **claude** | `claude` | `-p`；**herdr 交互**另加 `--dangerously-skip-permissions` | 可常开 | 每 cwd `par_seed_trust` + settings `bypassPermissions` | 友好 | 仅 settings yolo **不够**挡 trust 弹窗 |
| **codex** | `codex` | `exec` 可非交互；**herdr 交互**另加 `--dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust`（**勿**再加 `-a`/`-s`，与 bypass 互斥） | **必须断流** `</dev/null` | 每 cwd projects trust + config yolo | 友好 | 仅 config.toml yolo **不够**挡新目录 trust |
| **pi** | `pi` | `-p` | 可常开 | CPA | 友好 | **不吃** reasoning effort |
| **grok** | `grok` | `-m` / `-p` | 可常开 | `trusted_folders.toml`（`par_seed_trust`） | 友好 | 原生 CLI |
| **kimi** | `kimi` | `-m` / `-p` | 可常开 | 视本地配置 | 友好 | 键 **`kimi-code/<id>`**，禁裸 id |

矩阵轨 → 端（速查）：

| 轨 | 端 |
|---|---|
| `@speed/a`（kimi-hs） | pi |
| `@speed/b`（flash） | codex |
| `@develop/a` k3 · `@research/b` kimi-for-coding | kimi |
| `@develop/b` · `@research/a` grok | grok |
| `@develop/c` glm · `@review/a` opus | claude |
| `@review/b` gpt · `@research/c` pro | codex |

## 已知边界

- **pi 端不吃 reasoning effort**（CPA 不区分）→ pi 适配广度/速度，**不派深推理**；深度靠模型本能（k3-pi 例外可用）。
- **kimi-for-coding 强制 thinking 无档位**；`glm-5-turbo-cc` 无 `[1m]`。
- **显式指定型号，不依赖端默认**；换 model 要新派（pane 的 model 启动时定）。
- grok `grok-4.5` 进**开发矩阵 + 研究矩阵**；不进审阅矩阵。
- **codex stdin 不断流**会挂起或假失败——派发与手测一律 `</dev/null`。

## 复验规程

矩阵漂移（新模型上线/旧模型下线/端写法变更）时重跑全格验证（脚本模式见本文「验证方法」），全 OK 才更新矩阵并 bump 日期；任一 FAIL 标在矩阵里，拷问时绕开。
