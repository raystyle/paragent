# research-mode — 并行研究/分析细则

> 用法正本：`../../references/parallel.md`（四原语卡）。本文件 = research 细则。

## explorer 契约(预写进 task.md;参考 Claude Code exploreAgent)

task.md 必须包含:

```markdown
你是只读探索 agent。**严禁**:创建/修改/删除任何文件、写重定向(>/>>)、heredoc 写文件、
任何改系统状态的命令。Bash 仅只读操作(ls/cat/head/tail/git log/git diff/grep/find)。
- 高效搜索:尽量并行发多个 grep/read 工具调用
- 结论写 artifact(.parallel/<tid>/artifact.md)：填实预写骨架（三节固定标题，缺一门禁不收）：
  ## 结论（先行）→ ## 证据（每条 文件:行号 或 URL）→ ## 存疑
- 完成上报(最后动作):herdr pane report-metadata "$HERDR_PANE_ID" --source parallel --token "par_result=PAR-DONE <tid>#1 <一句话结论>",并终端打印同一行
```

**可校验清单（0.7.5，P-2）**：与 review 同机制——首 launch 骨架预写进 `artifact.md`
（基线前），`par_delivery_met` 对 research 加三节 lint（`## 结论 / ## 证据 / ## 存疑`），
缺一 → 质问 → 仍缺 → stalled。

## thoroughness 分级

| 级别 | 适用 | 探索广度 |
|------|------|----------|
| quick | 定位单个文件/符号 | 几次搜索内收束 |
| medium | 理解一个模块 | 跨多文件多读 |
| thorough | 全面调研 | 多位置/多命名约定穷举 |

## 工具配置(规划定)

- **代码类**:本地只读探索(无需额外技能)。
- **资料类**:用 browse 技能(网页抓取/搜索) + gh(gh search repos/code、gh api)——model-cmd 选支持这些技能的端,task.md 写明可用工具。

## 汇总评估(主 agent)

- 各 artifact 收齐 → 交叉比对(结论一致性/证据强度) → 汇总报告:共识 / 分歧 / 存疑 → 报人确认。
- 某路 stalled/timeout:该路标「无成果」,汇总时注明缺口,不阻塞其他路。
