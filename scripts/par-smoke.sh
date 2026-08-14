#!/usr/bin/env bash
# par-smoke.sh — 并行原语冒烟（L3 门禁）
#
# 用法:
#   par-smoke.sh                 # stub 全量 run-all + version-check（默认 CI）
#   par-smoke.sh --live          # + 本机 live：discuss 双席 token 轮（需 herdr 会话与右席）
#   PAR_SMOKE_LIVE=1 par-smoke.sh
#
# 判定: PAR-SMOKE-PASS / PAR-SMOKE-FAIL
# nightly 建议: cron 跑默认（stub）；有人值守再 --live
# 日志落盘（O-2）：$PAR_SMOKE_DIR（默认 ~/.local/state/paragent/smoke/）每次 <ts>.log + last.log，
# stage 输出 {ver,discuss-open,discuss-col}.out（last-run）；失败附排查三行（O-1）
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
LIVE=0
[ "${PAR_SMOKE_LIVE:-0}" = 1 ] && LIVE=1
for a in "$@"; do
  case "$a" in
    --live) LIVE=1 ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
  esac
done

FAIL=0
log() { echo "[par-smoke] $*"; }
bad() { echo "[par-smoke][FAIL] $*" >&2; FAIL=1; }

# O-2：日志统一落盘约定（同 nightly 形制）：每次跑全量 $DIR/<ts>.log + last.log 复写；
# stage 中间输出固定名（last-run 语义）落同目录，禁 /tmp 散落
SMOKE_DIR="${PAR_SMOKE_DIR:-$HOME/.local/state/paragent/smoke}"
mkdir -p "$SMOKE_DIR"
TS=$(date +%Y%m%d-%H%M%S)
LOG="$SMOKE_DIR/$TS.log"
OUT_VER="$SMOKE_DIR/ver.out"
OUT_DISCUSS_OPEN="$SMOKE_DIR/discuss-open.out"; OUT_DISCUSS_COL="$SMOKE_DIR/discuss-col.out"

main() {
log "== 1) parallel run-all (stub) =="
if bash "$SKILL/scripts/tests/run-all.sh"; then
  log "run-all OK"
else
  bad "run-all"
fi

log "== 2) version-check（装机漂移记 WARN 不硬死） =="
if bash "$SKILL/scripts/version-check.sh" >"$OUT_VER" 2>&1; then
  log "version OK"
else
  log "version DRIFT（装机树未同步；源码测仍可过）"
  tail -8 "$OUT_VER"
fi

PAR_BIN="${PAR_BIN:-$SKILL/bin/par}"
if [ "$LIVE" = 1 ]; then
  log "== 3) live discuss token 轮（需已 open 的 discuss 或可 open）=="
  if ! command -v herdr >/dev/null 2>&1; then
    bad "herdr 不在 PATH"
  else
    # 尝试 open（已有则 reuse）
    bash "$PAR_BIN" discuss open --a @review/a --b @review/b >"$OUT_DISCUSS_OPEN" 2>&1 \
      || log "discuss open 非零（可能已有 session）: $(tail -3 "$OUT_DISCUSS_OPEN")"
    bash "$PAR_BIN" discuss fire a "【smoke】一句话回 pong-a，并执行文末 report-metadata。" >/dev/null 2>&1 || bad "discuss fire a"
    bash "$PAR_BIN" discuss fire b "【smoke】一句话回 pong-b，并执行文末 report-metadata。" >/dev/null 2>&1 || bad "discuss fire b"
    # 立即 take 应 rc3
    bash "$PAR_BIN" discuss take --all >/dev/null 2>&1
    trc=$?
    [ "$trc" -eq 3 ] && log "live immediate take rc3 OK" || bad "live immediate take 期望 rc3 got $trc"
    if bash "$PAR_BIN" discuss collect --all --no-read --timeout-ms 180000 >"$OUT_DISCUSS_COL" 2>&1; then
      grep -q 'par_result: PAR-DONE' "$OUT_DISCUSS_COL" \
        && log "live collect par_result OK" \
        || bad "live collect 无 par_result 行"
    else
      bad "live collect 失败（子席可能未 report-metadata）"
      tail -15 "$OUT_DISCUSS_COL" >&2
    fi
  fi
else
  log "== 3) live 跳过（传 --live 或 PAR_SMOKE_LIVE=1）=="
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "PAR-SMOKE-PASS"
  return 0
fi
echo "PAR-SMOKE-FAIL"
# O-1：live 踩失败三行文案（定位路径 + live 高发因 + 单跑定位）
echo "  排查三行:"
echo "  1) 全量日志 $LOG；stage 输出同目录 {ver,discuss-open,discuss-col}.out（last-run）"
echo "  2) live 高发：子席未报 token → herdr pane get <pane> 看 tokens.par_result；席忙先 herdr agent wait <pane> --until idle --until done"
echo "  3) stub 红：bash scripts/tests/run-all.sh 单跑定位（paragent 仓根下）"
return 1
}

main 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
cp -f "$LOG" "$SMOKE_DIR/last.log" 2>/dev/null || true
exit "$rc"
