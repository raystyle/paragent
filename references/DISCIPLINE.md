# 并行任务原语（workspace 载荷 · 非独立 skill）

> **不是**可安装 skill。入口只有 workspace：`scripts/par.sh`；本目录 = 脚本/纪律载荷。  
> **用法正本（先读这个）**：`../references/parallel.md`（dev / research / review / ix 四原语一张表）。  
> **生产级路线**：`references/production-roadmap.md`（L1 主路径 / L2 加固 / L3 完整）。  
> 本文件 = 纪律与门禁深钻；模型矩阵 `references/models.md`。  
> 模式：规划 grill + 交付确认（人在环）；中间 par-* 全自动。

## 三阶段人机边界

1. **规划(人在环,grill 风格)**:拷问人类——并行做什么（分支开叉/研究分析/review 审核/合作交流）。一次一问、给推荐答案、能自查的事实不问。规划期定:任务拆分、各任务档位、并发路数、产出形态、verify 命令(开发)。细则见 references/planning.md。**达成共享理解 = 授权**。
2. **执行(自动)**:主 agent 用 herdr 编排,无中途过人。verify 失败自动补发修复(retry ≤2),再失败升档重派(档位序列规划定)。
3. **交付(人在环)**:主 agent 评估产物(开发=diff+verify 全绿;研究=汇总)→ 与人确认 → 开发模式此时才 par-merge。

## 完成判定协议（token 真源 · 不扫终端文本）

**稳定完成信号 = `herdr pane report-metadata` 写入的 `tokens.par_result`。**

子 agent 最后动作（必须）:

```bash
herdr pane report-metadata "$HERDR_PANE_ID" --source parallel \
  --token "par_result=PAR-DONE <tid>#<attempt> <一句话结论>"
# 卡住:
# --token "par_result=PAR-BLOCKED <tid>#<attempt> <原因>"
```

编排侧（`par_finish`）:

1. **启动时** `clear-token par_result` + 写 `artifact.baseline`，防上轮串台/旧产物。  
2. **每切片先读** `pane get → tokens.par_result`，锚定 `<tid>#<attempt> <非空结论>` → `done` / `blocked`（空结论 = waiting）。  
3. `agent wait --until idle|done|blocked` **只作唤醒**；**单独 agent_status 永不升格完成**。  
4. token=`done` 后仍过交付门禁：`artifact.md` 非空 **且相对 baseline 已更新**；dev 另需 worktree 新 commit。  
5. token 早产（有 token 无交付）→ grace → 质问并 **+1 attempt**（清旧 token、重写 baseline，要求新 `par_result`）。  
6. **无 token 永不 done**（timeout / blocked / stalled）；**禁止** `sentinel-missing→done`。

终端打印 `PAR-DONE …` 仅供人眼；脚本**不**匹配终端文本。

## 并行分支/开叉（dev 模式）

1. grill 拆成 N 个**零文件重叠**子任务(每个:范围/brief/verify 命令/档位)→ plan.md 落 `.parallel/` → 人确认。
2. 渐进批量派发:`par.sh wave --mode dev t1=@dev/a t2=@dev/b t3=@dev/c`（**tab 布局**+worktree；每任务一 tab）。model-cmd 可用矩阵轨 `@dev/a` 或裸命令。
3. 各任务 done 后:`par.sh verify <tid> --cmd "<规划定的 verify 命令>"`。
4. 全绿 → 主 agent 汇总评估 diff → 人确认 → `par.sh merge <tid>...`。
细则与失败处理见 references/dev-mode.md。

## 并行研究/分析（research 模式）

1. grill 拆成 N 个探索问题(档位/路数/产出形态当次现定)→ 人确认。
2. 渐进批量派发:`par.sh wave --mode research t1=@research/a t2=@research/b t3=@research/c`（**tab 布局**；每任务一 tab）。task.md 按 references/research-mode.md 预写。
3. 各 artifact 收回 → 主 agent 汇总评估 → 人确认最终结论。
细则见 references/research-mode.md。

## 并行 review/审核（review 模式）

1. grill 定审阅范围(commit/PR/diff)与双轨档位 → 人确认。
2. 预写 `.parallel/<tid>/task.md` → `par.sh wave --mode review t-a=@review/a t-b=@review/b`（**tab**；只读无 worktree）。
3. 收齐 artifact（判定 + P0/P1）→ 主 agent 交叉汇总 → 人确认。
细则见 references/review-mode.md。

## 并行合作/交流（ix · 两令制）

1. **三窗**：主窗人控；`ix open` 只开右 stack 双席（默认 Opus 4.8 + GPT 顶档）。
2. **两令**（禁止合成一条长命令齐等）：
   - **`ix fire a|b "…"`** — 只派发，火即返；清旧 `par_result`、写本轮 `ix-<role>#attempt`、消息尾强制完成上报指令；
   - **`ix take [--all] [--read]`** — 只收本轮 **token 过闸** 席（非阻塞；无则 rc3）；`--read` 仅佐证。
3. 节奏：`fire`×N → `take` → 可再 `fire` 跟进/新题 → `take`… 实现异步渐进并行多任务。
4. **编排糖**（非第三令）：`ix collect [--all|a|b] [--read]` = `wait`（等到 token）→ `take`；主控「派完自动收」用，**不**把阻塞塞进 fire。
5. 交互期不关右窗；`close-tasks` 跳过 ix；仅 `ix close`。
6. **完成真源与 wave 同源**：`tokens.par_result` 锚定 tid#attempt + 非空结论；**禁** agent_status / 扫终端单独升格完成。
细则见 references/interactive-mode.md。

## 纪律

- **拆分零重叠**(dev):任务间无共同文件,merge 才顺序无冲突;冲突回派原 agent 修。
- **预写 task.md 优先**:主 agent 规划后预写 `.parallel/<tid>/task.md`(含研究模式 explorer 契约),脚本检测到就用。
- **渐进启动(par-wave)**:串行 recruit（回执后下一个），避免并发 tab create/agent start 撞锁；启动后并发收割。
- **布局**:wave/run 默认 **tab**；**ix 固定右侧 stack 双 agent**。wave/run 可用 `--layout stack` 覆盖。
- **矩阵派发**:`<tid>=@dev/a|@research/b|…` 经 `par_matrix_resolve` 解成 model-cmd（见 references/models.md）。
- **单任务失败不拖全局**:failed/blocked/verify-failed 记录后继续,交付评估一并报人。
- **merge 必过人**:脚本不自动 merge;人确认后 par-merge.sh 才执行。
- **窗格**:wave/run 默认可关任务 tab；**ix 交互不关右窗**，仅 `ix close`。
- **herdr 原语注意**:report/send 族成功=空 stdout+rc0(判成功看退出码);新 pane `read --source recent` 可能为空(用 visible);顶层 `--help` 非全量命令清单(逐组 --help)。
- **pi 长 prompt 限制**:pi 对长 prompt 可能进编辑器未提交——编排 prompt 保持短、内容一律落 task.md/verify.log;卡顿时主 agent 查 pane 实况手动 herdr pane send-keys <pane> enter。
