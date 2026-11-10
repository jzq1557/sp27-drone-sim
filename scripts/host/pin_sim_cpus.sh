#!/usr/bin/env bash
# SP27 仿真 CPU 绑核：减少 Gazebo GUI 对 PX4/MAVROS 时间同步与 EKF 的调度干扰。
#
# 角色 -> CPU：
#   PX4 / MAVROS / 控制器 / 规划 / BT : 0-7   (P 核)
#   Gazebo server（物理 + 相机渲染）  : 8-15  (P 核)
#   Gazebo GUI（ruby 渲染）           : 16-23 (E 核)
#   ORB-SLAM3 / 对比记录              : 24-31 (E 核)
set -o pipefail

MASK_FLIGHT="${SP27_CPU_FLIGHT:-0-7}"
MASK_SERVER="${SP27_CPU_SERVER:-8-15}"
MASK_GUI="${SP27_CPU_GUI:-16-23}"
MASK_ORB="${SP27_CPU_ORB:-24-31}"

wait_for="${1:-0}"   # 可选：等待关键进程出现的秒数

key_ready() {
  pgrep -f 'gz sim .* -s ' >/dev/null 2>&1 && pgrep -f '/bin/px4' >/dev/null 2>&1
}

if (( wait_for > 0 )); then
  for _ in $(seq 1 "$wait_for"); do
    key_ready && break
    sleep 1
  done
fi

pin() {
  local mask="$1" pattern="$2" label="$3"
  local pids
  pids=$(pgrep -f "$pattern" 2>/dev/null || true)
  for pid in $pids; do
    taskset -pc "$mask" "$pid" >/dev/null 2>&1 || true
  done
  [[ -n "$pids" ]] && echo "[pin] $label -> $mask ($(echo $pids | wc -w) pid)"
}

pin "$MASK_FLIGHT" '/bin/px4' 'PX4'
pin "$MASK_FLIGHT" 'mavros_node' 'MAVROS'
pin "$MASK_FLIGHT" 'offboard_controller_node' 'controller'
pin "$MASK_FLIGHT" 'planner_server' 'planner'
pin "$MASK_FLIGHT" 'nav_interface_node' 'nav_bt'
pin "$MASK_FLIGHT" 'sp_decision_node' 'decision'
pin "$MASK_SERVER" 'gz sim .* -s ' 'gz-server'
pin "$MASK_GUI" 'gz sim -g' 'gz-gui'
pin "$MASK_ORB" 'orbslam3_ros_multimode_node' 'ORB'
pin "$MASK_ORB" 'sp27_vio_compare' 'VIO-compare'
