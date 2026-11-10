#!/usr/bin/env bash
# 启动 SP27 仿真（无 GUI，省内存；日常飞行/采集用这个）。
# 环境变量集中在 host/env.sh；用法：
#   bash /home/justin/TJ-Superpower/deploy/run_sim_headless.sh [额外的 ros2 launch 参数]
set -o pipefail

DEPLOY_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$DEPLOY_DIR/host/env.sh" || { echo "[run_sim_headless] env.sh 加载失败" >&2; exit 1; }

# 不启动 Gazebo GUI：PX4 的 px4-rc.gzsim 依据 HEADLESS 决定是否启动 gz sim -g
export HEADLESS=1

cd "$SP27_WS" || exit 1
echo "[run_sim_headless] $(date +%T) 启动（headless），日志：/tmp/launch_sim.log"
exec ros2 launch sp_nav_bringup sp27_flight.launch.py "$@" 2>&1 | tee /tmp/launch_sim.log
