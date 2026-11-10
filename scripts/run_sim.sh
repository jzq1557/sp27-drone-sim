#!/usr/bin/env bash
# 启动 SP27 仿真（带 GUI，里程碑 A 用）。
# 环境变量集中在 host/env.sh；用法：
#   bash /home/justin/TJ-Superpower/deploy/run_sim.sh [额外的 ros2 launch 参数]
set -o pipefail

DEPLOY_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$DEPLOY_DIR/host/env.sh" || { echo "[run_sim] env.sh 加载失败" >&2; exit 1; }

cd "$SP27_WS" || exit 1
echo "[run_sim] $(date +%T) 启动（GUI），日志：/tmp/launch_sim.log"
# 自动绑核：PX4/MAVROS 0-7，server 8-15，GUI 16-23，ORB 24-31
( for _ in $(seq 1 60); do bash "$DEPLOY_DIR/host/pin_sim_cpus.sh" >/dev/null 2>&1; sleep 2; done ) >/tmp/sp27_cpu_pin.log 2>&1 &
exec ros2 launch sp_nav_bringup sp27_flight.launch.py "$@" 2>&1 | tee /tmp/launch_sim.log
