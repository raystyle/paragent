# planning — grill 规划细则

> 规划是 parallel 的唯一人在环入口:拷问才放行执行。

## grill 规程(对齐 grill-me 风格)

- 一次只问一个细节,给推荐答案;能自查(代码库/文件/命令)的事实自己查,不问人。
- 决策树逐个分支走:目标 → 拆分 → 各任务(范围/档位/verify) → 路数/产出 → 授权确认。
- **档位(model-cmd)在拷问阶段决策,且必须从 [references/models.md](models.md) 的三家验证矩阵选**(端写法纪律:claude `--model` / codex `-m` / pi `--model 供应商/id`);矩阵外型号先复验再入矩阵。
- 共享理解达成前不动手。

## dev 拆分原则(零重叠)

- 唯一硬规则:**任务间零文件重叠**(改同一文件的两个任务必须合并或串行)。
- 每个子任务四要素:范围(哪些文件)/brief(做什么)/verify 命令(机械可跑,如 `cargo test xxx`)/档位(模型)。
- 拆分粒度:单任务 15 分钟内可完成 + verify 可机械判定;过大先再拆。
- 四矩阵见 [models.md](models.md)：**极速**（hs@pi / flash@codex）· **开发**（k3@kimi · grok-4.5 · **glm-5.2@claude**）· **审阅**（opus-4.8@claude + gpt-5.6-sol@codex）· **研究**（grok-4.5 · kimi-for-coding@kimi · **deepseek-pro@codex**）。Coder 简单→极速，常规→开发三轨；默认 medium 起步。

## research 拆分原则

- 每个探索问题独立可答、互不依赖;问题写清 thoroughness(quick/medium/thorough)。
- 档位/路数/产出形态**当次规划现定**,skill 不锁默认。

## plan.md 格式(落 `.parallel/plan.md`)

```markdown
# parallel plan: <目标一句话>
- 模式: dev|research
- 路数: N(规划定)
## 任务
| tid | 范围/问题 | 档位 | verify(dev) | thoroughness(research) |
|-----|-----------|------|-------------|------------------------|
| t-xxx | ... | k3 | cargo test foo | - |
## 授权
- [ ] 人已确认(日期)
```
