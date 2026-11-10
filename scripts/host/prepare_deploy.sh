#!/usr/bin/env bash
# 把 ~/TJ-Superpower/deploy 换成工作区里的「已适配」脚本（原目录先备份）。
# 适配内容：run_sim*.sh 统一 source host/env.sh；verify_a.sh 的联网检查改为镜像。
set -euo pipefail

ROOT=/home/justin/TJ-Superpower
SRC=/home/justin/works/SP_drone/sp27-drone-sim/scripts
BACKUP_DIR=/home/justin/works/SP_drone/artifacts
TS=$(date +%Y%m%d_%H%M%S)

[[ -d $SRC ]] || { echo "[错误] 源脚本目录不存在: $SRC" >&2; exit 1; }
mkdir -p "$BACKUP_DIR"

if [[ -L $ROOT/deploy ]]; then
  echo "deploy 已经是符号链接 -> $(readlink -f "$ROOT/deploy")"
elif [[ -d $ROOT/deploy ]]; then
  B="$BACKUP_DIR/deploy_backup_$TS"
  mv "$ROOT/deploy" "$B"
  echo "旧 deploy 已备份到 $B"
fi

ln -sfn "$SRC" "$ROOT/deploy"
chmod 755 "$SRC"/*.sh "$SRC"/host/*.sh 2>/dev/null || true
echo "deploy -> $SRC"
ls -l "$ROOT/deploy" | head -12
echo
echo "自检："
for f in run_sim.sh run_sim_headless.sh verify_a.sh host/env.sh; do
  [[ -e "$ROOT/deploy/$f" ]] && echo "  [PASS] $f" || echo "  [FAIL] $f 缺失"
done
