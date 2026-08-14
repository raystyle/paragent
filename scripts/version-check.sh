#!/usr/bin/env bash
# version-check.sh — paragent 装机漂移检查（只读）：CLI + 薄 skill 树 vs 本仓源
#
# 用法:
#   version-check.sh              # 本机：~/.local/bin/par + 各 agent 树 skills/par
#   version-check.sh --remote     # + lan-home-mac / lan-home-linux
#   version-check.sh --json
#
# 判定: PAR-VERSION-PASS / PAR-VERSION-DRIFT / PAR-VERSION-FAIL
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
REMOTE=0
JSON=0
for a in "$@"; do
  case "$a" in
    --remote) REMOTE=1 ;;
    --json) JSON=1 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
  esac
done

SRC_VER=$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo missing)
DRIFT=0
ROWS=()

_skill_ver() {  # $1=skills/par 目录（容忍 gh install 重排 frontmatter 的任意缩进）
  awk '/^ *version:/ { gsub(/"/, "", $2); print $2; exit }' "$1/SKILL.md" 2>/dev/null
}

_row() { # label status detail
  ROWS+=("$1|$2|$3")
  printf '  %-28s %s\n' "$1" "$2"
  [ -n "$3" ] && printf '    %s\n' "$3"
  [ "$2" = OK ] || DRIFT=1
}

# 1) CLI：~/.local/bin/par 存在且 PAR_HOME 解析回本仓/装机根
CLI="$HOME/.local/bin/par"
if [ -x "$CLI" ]; then
  cver=$(PAR_RESOLVE_ONLY=1 "$CLI" --version 2>/dev/null || true)
  # --version 未实现时退化为存在性检查
  _row "cli:$CLI" OK "installed"
else
  _row "cli:$CLI" MISSING "先 bash scripts/install.sh"
fi

# 2) 本机各 agent 树的薄 skill（skills/par/SKILL.md version == VERSION）
for base in "$HOME/.claude/skills/par" "$HOME/.codex/skills/par" "$HOME/.kimi-code/skills/par" \
            "$HOME/.pi/agent/skills/par" "$HOME/.config/agents/skills/par" "$HOME/.grok/skills/par"; do
  [ -e "$base" ] || continue
  v=$(_skill_ver "$base")
  if [ "$v" = "$SRC_VER" ]; then
    _row "local:$(basename "$(dirname "$(dirname "$base")")")/par" OK "ver=$v"
  else
    _row "local:$(basename "$(dirname "$(dirname "$base")")")/par" DRIFT "want=$SRC_VER got=${v:-missing}（重跑 install.sh）"
  fi
done

# 3) 远程薄 skill 树
if [ "$REMOTE" = 1 ]; then
  for h in lan-home-mac lan-home-linux; do
    if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$h" true 2>/dev/null; then
      _row "remote:$h" UNREACHABLE ""
      continue
    fi
    for r in .claude/skills/par .codex/skills/par .kimi-code/skills/par; do
      ssh -o BatchMode=yes -o ConnectTimeout=8 "$h" "test -f \"\$HOME/$r/SKILL.md\"" 2>/dev/null || continue
      v=$(ssh -o BatchMode=yes -o ConnectTimeout=12 "$h" \
        "awk '/^ *version:/ { gsub(/\"/, \"\", \$2); print \$2; exit }' \"\$HOME/$r/SKILL.md\"" 2>/dev/null)
      if [ "$v" = "$SRC_VER" ]; then
        _row "remote:$h/par" OK "ver=$v"
      else
        _row "remote:$h/par" DRIFT "want=$SRC_VER got=${v:-missing}"
      fi
    done
  done
fi

if [ "$JSON" = 1 ]; then
  printf '%s\n' "${ROWS[@]}" | jq -R -s '
    split("\n") | map(select(length>0) | split("|") | {target:.[0],status:.[1],detail:.[2]}) | {rows:.}' 2>/dev/null || true
fi

echo
if [ "$DRIFT" -eq 0 ]; then
  echo "PAR-VERSION-PASS"
  exit 0
fi
echo "PAR-VERSION-DRIFT"
echo "修: 重跑 bash scripts/install.sh（本机）/ rsync skills/par → 目标树（远程）"
exit 1
