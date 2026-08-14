#!/usr/bin/env bash
# install.sh — paragent 装机（幂等）：只装全局 CLI；薄 skill 走 gh skill install，不做 symlink
#   1) 依赖自检（herdr/jq/git/python3）
#   2) PAR_HOME 指针 ~/.paragent-home（仓根）
#   3) CLI ~/.local/bin/par（拷贝 bin/par；PAR_HOME 经指针解析，仓移动后重跑本脚本即可）
# 用法: install.sh [--check]   # --check 只读体检
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1 || true

log() { echo "[install] $*"; }
fail() { echo "[install][FAIL] $*" >&2; exit 1; }

# 1) 依赖
for c in herdr jq git python3; do
  if command -v "$c" >/dev/null 2>&1; then log "dep $c OK"; else fail "缺依赖: $c"; fi
done

[ -f "$ROOT/VERSION" ] || fail "仓根缺 VERSION"
[ -f "$ROOT/skills/par/SKILL.md" ] || fail "仓根缺 skills/par/SKILL.md"
VER=$(tr -d '[:space:]' < "$ROOT/VERSION")

if [ "$CHECK" = 1 ]; then
  [ -x "$HOME/.local/bin/par" ] && log "cli ~/.local/bin/par OK" || fail "缺 ~/.local/bin/par"
  [ -f "$HOME/.paragent-home" ] && log "pointer OK: $(cat "$HOME/.paragent-home")" || fail "缺 ~/.paragent-home"
  echo "INSTALL-CHECK-PASS"
  exit 0
fi

# 2) 指针
printf '%s\n' "$ROOT" > "$HOME/.paragent-home"
log "pointer ~/.paragent-home → $ROOT"

# 3) CLI（全局 PATH）
mkdir -p "$HOME/.local/bin"
cp "$ROOT/bin/par" "$HOME/.local/bin/par"
chmod +x "$HOME/.local/bin/par"
log "cli ~/.local/bin/par ($VER)"

command -v par >/dev/null 2>&1 || log "WARN: ~/.local/bin 不在 PATH（重开 shell 或加 PATH）"
echo "INSTALL-PASS paragent $VER"
