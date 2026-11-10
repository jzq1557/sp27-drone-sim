#!/usr/bin/env bash
# 热重启：保留 Gazebo 世界与 GUI，只重启 PX4 + ROS 节点。
# 用法：bash warm_restart.sh <gz_partition> [launch_log]
set -o pipefail

DEPLOY=/home/justin/TJ-Superpower/deploy
WS=/home/justin/TJ-Superpower/sp_nav_drone_27
P="${1:?用法: warm_restart.sh <gz_partition> [log]}"
LOGF="${2:-/tmp/warm_restart.log}"
# shellcheck disable=SC1091
source "$DEPLOY/host/env.sh" 2>/dev/null

say() { echo "[warm $(date +%H:%M:%S)] $*"; }

# 1. 只停飞控/ROS，不动 gz
pkill -INT -f 'ros2 laun[c]h sp_nav_bringup' 2>/dev/null
pkill -INT -f 'offboard_control[l]er_node' 2>/dev/null
pkill -INT -f 'p[x]4_sitl_default/bin' 2>/dev/null
sleep 3
pkill -KILL -f 'ros2 laun[c]h sp_nav_bringup' 2>/dev/null
pkill -KILL -f 'p[x]4_sitl_default/bin' 2>/dev/null

# 2. 删除旧无人机实体
GZ_PARTITION="$P" timeout 8 gz service -s /world/sp_27_features/remove \
  --reqtype gz.msgs.Entity --reptype gz.msgs.Boolean --timeout 3000 \
  --req 'name: "sp27_uav_0"' >/dev/null 2>&1
say "已删除 sp27_uav_0（若存在）"

# 3. 清 PX4 参数/数据管理缓存（保留 gz 世界）
ROOT="$SP27_PX4/build/px4_sitl_default/rootfs"
BK="/home/justin/works/SP_drone/artifacts/cache_backup/warm_$(date +%H%M%S)"
mkdir -p "$BK"
for f in parameters.bson parameters_backup.bson dataman; do
  [[ -e "$ROOT/$f" ]] && mv "$ROOT/$f" "$BK/" 2>/dev/null
done
rm -f /tmp/sp27_localization_domain_*.lock
say "PX4 参数/dataman 已清（备份 $BK）"

# 4. 复用世界重启
( cd "$WS" && setsid nohup systemd-inhibit --what=sleep:idle --mode=block \
    --who=sp27-warm --why="SP27 warm restart" \
    bash "$DEPLOY/run_sim.sh" reuse_world:=true gz_partition:="$P" \
    > "$LOGF" 2>&1 < /dev/null & )
say "已发起复用世界启动（partition=$P）"
