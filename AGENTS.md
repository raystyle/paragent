# paragent — 项目规范

## 项目概览

独立 CLI 项目（`bin/par`）+ 附带薄 skill（`skills/par/SKILL.md`）。
herdr 并行 agent 编排：五原语 develop/research/review/discuss/triad。形态 = CLI 主、skill 仅路由。
仓内零密钥材料。

## 安装

```bash
bash scripts/install.sh          # 幂等：依赖自检 + ~/.paragent-home 指针 + 全局 CLI ~/.local/bin/par
gh skill install raystyle/paragent --all   # 薄 skill（路由层；不含 CLI）
```

CLI 全局唯一（PATH）；skill 仅路由，不做 symlink。

## 质量准则

1. **正文 = 唯一正确做法 + 强约束规则**。
2. **错误靠代码兜底 + 回归测试，不靠提示词告诫**。同一错误第二次出现 → 下沉进脚本/工具。
3. **靠确定产物监控**（退出码/标记/token），不靠提示词反复确认。

## 硬规则

- **铁律以 `skills/par/SKILL.md` 为准**（完成真源 par_result token、relay 闸、禁扫终端等），本文件不复制。
- **脚本名不改**；新脚本 `<域>-<动作>.sh`。
- **emoji 禁令**：SKILL.md、references 及脚本输出一律不用 emoji/U+2713。
- **SKILL.md 体积**：路由层 ≤60 行（正文，frontmatter 不计）；超限 → 拆 references/。
- **路径纪律**：脚本一律 `$PAR_HOME` 相对寻址（env → `~/.paragent-home` → 仓根），禁止硬编码仓绝对路径。
- **脱敏**：真实 IP/主机名/凭据不入库（公开仓）。

## 验收门禁（改动后必过）

```bash
par gate                    # = bash -n scripts/*.sh + scripts/tests/run-all.sh
par gate --quick            # bash -n + 关键用例
```

回归测试在 `scripts/tests/test-*.sh`（纯 bash + stub，不需真 herdr）。
修过的 bug 必固化一个用例（仓规 2/3）。

## 已确立约定

- frontmatter：author=rayh4c、user-invocable=true、form=routing、version 语义化（VERSION 文件同源）。
- 运行时状态目录 = 项目 cwd 下 `.parallel/`（任务态/归档），日志 = `~/.local/state/paragent/`。
- 规范单点：本文件为正本，README 仅门面。
