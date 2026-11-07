#!/usr/bin/env bash
# 启动 SP27 仿真（里程碑 A 用）。所有必要的环境变量集中在这里。
# 用法：bash /home/justin/TJ-Superpower/deploy/run_sim.sh [额外的 ros2 launch 参数]
set -o pipefail

WS=/home/justin/TJ-Superpower/sp_nav_drone_27
PX4=$WS/src/sp_filght_sim/external_files/PX4-Autopilot
GZ=$PX4/Tools/simulation/gz

# PX4 构建/运行时需要：跳过子模块联网检查（校园网到 github 不稳）
export GIT_SUBMODULES_ARE_EVIL=1
export PATH=$HOME/.local/bin:$PATH

# MAVROS 需要 GeographicLib 的 geoid 数据集（已放在用户目录，免 sudo）
# ros_gz_bridge 的 python 模块需要 rosidl_pycommon（Humble 源里缺失，已本地补齐）
export PYTHONPATH=/home/justin/TJ-Superpower/pylibs:$PYTHONPATH
export GEOGRAPHICLIB_DATA=$HOME/.local/share/GeographicLib

# Gazebo 资源搜索路径：SP27 模型、世界，以及 external_files 下的场地
export GZ_SIM_RESOURCE_PATH="$GZ/models:$GZ/worlds:$WS/src/sp_filght_sim/external_files/worlds"

# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
# Harmonic 版 ros_gz（源码编译，覆盖 apt 里的 Fortress 版 bridge/image）
# shellcheck disable=SC1091
source /home/justin/TJ-Superpower/ros_gz_ws/install/setup.bash
# shellcheck disable=SC1091
source "$WS/install/setup.bash"

cd "$WS" || exit 1
echo "[run_sim] $(date +%T) 启动，日志：/tmp/launch_sim.log"
exec ros2 launch sp_nav_bringup sp27_flight.launch.py "$@" 2>&1 | tee /tmp/launch_sim.log
