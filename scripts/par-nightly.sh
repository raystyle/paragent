#!/usr/bin/env bash
# par-nightly.sh — 夜间 stub smoke 挂载（路线图 M-1）
#
# 用法:
#   par-nightly.sh run         # 跑 par-smoke（stub），日志落盘
#   par-nightly.sh install     # 幂等写入 crontab（默认 03:15）— 路线图 M-1b 待做，需人工显式装
#   par-nightly.sh uninstall   # 移除本脚本 crontab 行
#   par-nightly.sh status      # 最近一次结果 + cron 是否在位
# 注意: 不在 install.sh / 提交钩子里自动 crontab；挂载须主控显式 install。
#
# 环境:
#   PAR_NIGHTLY_HOUR=3 PAR_NIGHTLY_MIN=15   # install 时刻（本地）
#   PAR_NIGHTLY_DIR=~/.local/state/paragent/nightly
#
# 判定 run: PAR-NIGHTLY-PASS / PAR-NIGHTLY-FAIL
# 失败可见: $DIR/last-status · last.log · YYYYMMDD-HHMMSS.log
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
# cron 稳定入口：优先装机树，否则本脚本路径
# cron 稳定入口：优先已装 CLI（~/.local/bin/par，经 ~/.paragent-home 解析仓根），否则本脚本
STABLE="${HOME}/.local/bin/par"
if [ -x "$STABLE" ]; then
  CRON_BIN="$STABLE"; CRON_ARGS="nightly run"
else
  CRON_BIN="$HERE/par-nightly.sh"; CRON_ARGS="run"
fi
DIR="${PAR_NIGHTLY_DIR:-$HOME/.local/state/paragent/nightly}"
HOUR="${PAR_NIGHTLY_HOUR:-3}"
MIN="${PAR_NIGHTLY_MIN:-15}"
MARKER="# paragent-nightly"
OLD_MARKER="# workspace-par-nightly"   # 迁移前旧标记（uninstall/status 一并认）
CMD="${1:-}"

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \?//'
  exit 2
}

_log_init() {
  mkdir -p "$DIR"
}

cmd_run() {
  _log_init
  local ts stamp log latest
  ts=$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s)
  stamp=$(date -Iseconds 2>/dev/null || date)
  log="$DIR/${ts}.log"
  latest="$DIR/last.log"
  {
    echo "==== par-nightly run $stamp ===="
    echo "skill=$SKILL"
    echo "host=$(hostname 2>/dev/null || echo ?)"
    echo
  } >"$log"

  local rc=0
  if bash "$SKILL/scripts/par-smoke.sh" >>"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi

  cp -f "$log" "$latest" 2>/dev/null || true
  if [ "$rc" -eq 0 ]; then
    echo "PASS $stamp" >"$DIR/last-status"
    echo "PAR-NIGHTLY-PASS log=$log" | tee -a "$log"
    # 保留最近 14 份
    ls -1t "$DIR"/[0-9]*.log 2>/dev/null | tail -n +15 | xargs -r rm -f
    exit 0
  fi
  echo "FAIL $stamp rc=$rc" >"$DIR/last-status"
  echo "PAR-NIGHTLY-FAIL log=$log rc=$rc" | tee -a "$log" >&2
  exit 1
}

_cron_line() {
  # PATH 最小集；cd 到 home 避免 cron 工作目录坑
  printf '%s %s * * * PATH=/usr/local/bin:/usr/bin:/bin HOME=%s %s %s >>%s/cron.out 2>&1 %s\n' \
    "$MIN" "$HOUR" "$HOME" "$CRON_BIN" "$CRON_ARGS" "$DIR" "$MARKER"
}

cmd_install() {
  _log_init
  if ! command -v crontab >/dev/null 2>&1; then
    echo "[par-nightly] crontab 不在 PATH；手工加一行:" >&2
    _cron_line
    exit 1
  fi
  local tmp cur
  tmp=$(mktemp)
  crontab -l 2>/dev/null | grep -v "$MARKER" >"$tmp" || true
  _cron_line >>"$tmp"
  crontab "$tmp"
  rm -f "$tmp"
  echo "[par-nightly] install OK"
  echo "  bin=$CRON_BIN"
  echo "  when=${MIN} ${HOUR} * * * (local)"
  echo "  logs=$DIR"
  echo "  status: par-nightly.sh status"
  if [ "$CRON_BIN" != "$STABLE" ]; then
    echo "[par-nightly][WARN] 未装 CLI（~/.local/bin/par），cron 绑源码树 $HERE；跑 install.sh 后可改装机入口" >&2
  fi
  echo "PAR-NIGHTLY-INSTALL-PASS"
}

cmd_uninstall() {
  if ! command -v crontab >/dev/null 2>&1; then
    echo "[par-nightly] no crontab" >&2
    exit 1
  fi
  local tmp
  tmp=$(mktemp)
  if crontab -l 2>/dev/null | grep -q -e "$MARKER" -e "$OLD_MARKER"; then
    crontab -l 2>/dev/null | grep -v -e "$MARKER" -e "$OLD_MARKER" >"$tmp" || true
    crontab "$tmp"
    echo "[par-nightly] uninstall OK（已去 crontab 标记行，含旧 workspace-par 标记）"
  else
    echo "[par-nightly] 无标记行（已干净）"
  fi
  rm -f "$tmp"
  echo "PAR-NIGHTLY-UNINSTALL-PASS"
}

cmd_status() {
  echo "== par-nightly status =="
  echo "  skill=$SKILL"
  echo "  cron_bin=$CRON_BIN"
  echo "  dir=$DIR"
  if command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -q -e "$MARKER" -e "$OLD_MARKER"; then
    echo "  cron: INSTALLED"
    crontab -l 2>/dev/null | grep -e "$MARKER" -e "$OLD_MARKER" | sed 's/^/    /'
  else
    echo "  cron: not installed"
  fi
  if [ -f "$DIR/last-status" ]; then
    echo "  last: $(cat "$DIR/last-status")"
    echo "  log:  $DIR/last.log"
  else
    echo "  last: (never run)"
  fi
  echo "PAR-NIGHTLY-STATUS-PASS"
}

case "$CMD" in
  run) cmd_run ;;
  install|enable) cmd_install ;;
  uninstall|disable|remove) cmd_uninstall ;;
  status|st) cmd_status ;;
  -h|--help|help|"") usage ;;
  *)
    echo "usage: par-nightly.sh run|install|uninstall|status" >&2
    exit 2
    ;;
esac
