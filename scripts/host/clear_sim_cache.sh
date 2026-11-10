#!/usr/bin/env bash
# 飞行仿真缓存清理：每次起飞试验前执行。
#
# 清理内容：
#   - PX4：parameters.bson / parameters_backup.bson / dataman（参数与数据管理）
#           rootfs/log/*（PX4 飞行日志，通常数 GB）
#   - Gazebo：~/.gz/sim/log/*、~/.gz/rendering/ogre2.log、~/.gz/sim/8/gui.config 与 server.config
#   - ROS：~/.ros/log/*、ros2 daemon（节点发现缓存）
#   - 本地化锁：/tmp/sp27_localization_domain_*.lock
#
# 小文件（PX4 参数/dataman/GUI 配置）会备份到 artifacts/cache_backup/<时间戳>/；
# 大日志直接删除。不删除飞行精度日志（log/orbslam3_flights）与构建产物。
set -o pipefail

DEPLOY=/home/justin/TJ-Superpower/deploy
# shellcheck disable=SC1091
source "$DEPLOY/host/env.sh" 2>/dev/null

TS=$(date +%Y%m%d_%H%M%S)
BK="/home/justin/works/SP_drone/artifacts/cache_backup/$TS"
mkdir -p "$BK/px4" "$BK/gz"

say() { echo "[cache $(date +%H:%M:%S)] $*"; }

# 1. 停止所有仿真相关进程
pkill -INT -f 'ros2 laun[c]h sp_nav_bringup' 2>/dev/null
pkill -INT -f 'offboard_control[l]er_node' 2>/dev/null
pkill -INT -f 'gz si[m]' 2>/dev/null
pkill -INT -f 'p[x]4_sitl_default/bin' 2>/dev/null
sleep 3
pkill -KILL -f 'gz si[m]' 2>/dev/null
pkill -KILL -f 'p[x]4_sitl_default/bin' 2>/dev/null
sleep 1

# 2. PX4 参数/数据管理/日志
ROOT="$SP27_PX4/build/px4_sitl_default/rootfs"
for f in parameters.bson parameters_backup.bson dataman; do
  if [[ -e "$ROOT/$f" ]]; then
    mv "$ROOT/$f" "$BK/px4/" 2>/dev/null && say "PX4 $f -> 备份"
  fi
done
if [[ -d "$ROOT/log" ]]; then
  SIZE=$(du -sh "$ROOT/log" 2>/dev/null | cut -f1)
  rm -rf "${ROOT:?}/log"/* 2>/dev/null
  say "PX4 飞行日志已清空（$SIZE）"
fi
mkdir -p "$ROOT/eeprom"

# 3. Gazebo 缓存与 GUI 配置
if [[ -d "$HOME/.gz/sim/log" ]]; then
  rm -rf "$HOME/.gz/sim/log"/* 2>/dev/null
  say "Gazebo server/GUI 日志已清空"
fi
[[ -f "$HOME/.gz/rendering/ogre2.log" ]] && rm -f "$HOME/.gz/rendering/ogre2.log"
[[ -f "$HOME/.gz/auto_default.log" ]] && rm -f "$HOME/.gz/auto_default.log"
for f in gui.config server.config; do
  [[ -e "$HOME/.gz/sim/8/$f" ]] && mv "$HOME/.gz/sim/8/$f" "$BK/gz/" 2>/dev/null
done
say "Gazebo 渲染/GUI 配置已重置"

# 4. ROS 日志与发现缓存
rm -rf "$HOME/.ros/log"/* 2>/dev/null
ros2 daemon stop >/dev/null 2>&1
say "ROS 日志与 daemon 缓存已清理"

# 5. 本地化锁
rm -f /tmp/sp27_localization_domain_*.lock 2>/dev/null
say "本地化锁已清除"

# 6. 结果
echo
say "清理完成；备份目录：$BK"
ls -1 "$BK/px4" "$BK/gz" 2>/dev/null
