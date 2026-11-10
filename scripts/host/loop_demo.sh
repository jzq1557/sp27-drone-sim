#!/usr/bin/env bash
# 循环演示：每轮「重启仿真(GUI) → 起飞 → 固定航线 → 自动降落 → 重启」。
# 每轮都从干净状态开始，避免同一次仿真里二次解锁被 EKF 拒绝的问题。
#
# 用法：
#   bash loop_demo.sh            # 无限循环
#   bash loop_demo.sh 3          # 跑 3 轮
#   CAMERA=1 bash loop_demo.sh   # 同时启动三路相机预览窗口
#
# 日志/录像：/home/justin/works/SP_drone/runs/demo/
set -o pipefail

DEPLOY=/home/justin/TJ-Superpower/deploy
WS=/home/justin/TJ-Superpower/sp_nav_drone_27
LOGDIR=/home/justin/works/SP_drone/runs/demo
MAX_CYCLES="${1:-0}"
mkdir -p "$LOGDIR"

# shellcheck disable=SC1091
source "$DEPLOY/host/env.sh"

say() { echo "[loop $(date +%H:%M:%S)] $*"; }

stop_sim() {
  pkill -INT -f 'offboard_control[l]er_node' 2>/dev/null
  pkill -INT -f 'ros2 laun[c]h sp_nav_bringup' 2>/dev/null
  pkill -INT -f 'gz si[m]' 2>/dev/null
  pkill -INT -f 'p[x]4_sitl_default/bin' 2>/dev/null
  sleep 3
  pkill -KILL -f 'gz si[m]' 2>/dev/null
  pkill -KILL -f 'p[x]4_sitl_default/bin' 2>/dev/null
  sleep 2
}

start_sim() {  # $1 = 轮次
  ( cd "$WS" && setsid nohup systemd-inhibit --what=sleep:idle --mode=block \
      --who=sp27-demo --why="SP27 demo cycle $1" \
      bash "$DEPLOY/run_sim.sh" > "$LOGDIR/sim_$1.log" 2>&1 < /dev/null & )
}

start_controller() {  # $1 = 轮次
  nohup ros2 run offboard_controller offboard_controller_node --ros-args \
    --params-file "$WS/install/offboard_controller/share/offboard_controller/config/offboard_controller.yaml" \
    -p use_sim_time:=true > "$LOGDIR/controller_$1.log" 2>&1 &
  disown
}

state_field() {  # $1 = armed|mode
  timeout 3 ros2 topic echo --once /mavros/state 2>/dev/null | awk -v k="$1:" '$1==k{print $2; exit}'
}

wait_ready() {
  local i
  for i in $(seq 1 45); do
    if [[ "$(state_field connected)" == "true" ]]; then
      sleep 10   # 给 ORB 初始化的时间
      return 0
    fi
    sleep 2
  done
  return 1
}

wait_landed() {
  local i a m armed_seen=0
  for i in $(seq 1 240); do
    a=$(state_field armed); m=$(state_field mode)
    [[ "$a" == "true" ]] && armed_seen=1
    if (( armed_seen == 1 )) && [[ "$a" == "false" ]]; then
      say "落地/上锁完成（mode=$m）"
      return 0
    fi
    sleep 1
  done
  say "等待落地超时"
  return 1
}

if [[ "${CAMERA:-0}" == "1" ]]; then
  say "启动三路相机预览"
  nohup python3 "$DEPLOY/host/camera_viewer.py" > "$LOGDIR/camera_viewer.log" 2>&1 &
  disown
fi

cycle=0
while :; do
  cycle=$((cycle + 1))
  if (( MAX_CYCLES > 0 && cycle > MAX_CYCLES )); then
    say "完成 $MAX_CYCLES 轮，退出"
    break
  fi
  say "===== 第 $cycle 轮：重启仿真 ====="
  stop_sim
  start_sim "$cycle"
  if ! wait_ready; then
    say "第 $cycle 轮仿真未就绪，重试"
    continue
  fi
  start_controller "$cycle"
  sleep 3
  say "发送 start_builtin"
  timeout 8 ros2 topic pub --once /offboard/command std_msgs/msg/String "{data: start_builtin}" >/dev/null 2>&1
  wait_landed
  say "第 $cycle 轮结束"
  sleep 2
done
