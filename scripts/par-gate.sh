#!/usr/bin/env bash
# par-gate.sh — 合并/发布前门禁（路线图 M-4）
#
# 用法:
#   par-gate.sh           # 默认：bash -n + 全量 stub 回归（run-all）
#   par-gate.sh --quick   # 仅 bash -n 关键脚本（提速）
#   par-gate.sh --full    # 默认 + version-check（装机漂移）
#
# 判定: PAR-GATE-PASS / PAR-GATE-FAIL
# 退出码: 0 通过 · 1 失败 · 2 用法
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
MODE=default
for a in "$@"; do
  case "$a" in
    --quick) MODE=quick ;;
    --full) MODE=full ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "usage: par-gate.sh [--quick|--full]" >&2
      exit 2
      ;;
  esac
done

FAIL=0
log() { echo "[par-gate] $*"; }
bad() { echo "[par-gate][FAIL] $*" >&2; FAIL=1; }

log "== mode=$MODE skill=$SKILL =="

# 1) 关键脚本语法（任何模式）
log "== bash -n scripts/*.sh =="
for f in "$SKILL"/scripts/*.sh; do
  [ -f "$f" ] || continue
  if ! bash -n "$f" 2>/tmp/par-gate-bashn.err; then
    bad "bash -n $(basename "$f")"
    cat /tmp/par-gate-bashn.err >&2
  fi
done
[ "$FAIL" -eq 0 ] && log "bash -n OK"

# 2) parallel run-all（--quick 跳过）
if [ "$MODE" != quick ]; then
  log "== parallel run-all (stub) =="
  if bash "$SKILL/scripts/tests/run-all.sh" >/tmp/par-gate-runall.out 2>&1; then
    log "run-all OK"
    tail -3 /tmp/par-gate-runall.out
  else
    bad "run-all"
    tail -30 /tmp/par-gate-runall.out >&2
  fi
else
  log "== run-all 跳过（--quick）=="
fi

# 3) version-check（仅 --full；漂移不硬死，记 WARN）
if [ "$MODE" = full ]; then
  log "== version-check =="
  if bash "$SKILL/scripts/version-check.sh" >/tmp/par-gate-ver.out 2>&1; then
    log "version OK"
  else
    log "version DRIFT（见 /tmp/par-gate-ver.out；装机树未刷时常见）"
    tail -8 /tmp/par-gate-ver.out
  fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "PAR-GATE-PASS"
  exit 0
fi
echo "PAR-GATE-FAIL"
exit 1
