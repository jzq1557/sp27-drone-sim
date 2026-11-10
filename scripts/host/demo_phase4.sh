#!/usr/bin/env bash
# 阶段 4 demo 一键录制：
#   清缓存 → 重启 GUI 全栈 → 绑核 → 解锁/垂直起飞 → 地图/规划/BT/决策
#   → (4,2,2) → (-2,2,2) → 降落 → 停止录制
# 输出：runs/demo_<时间>/demo.mp4、trajectory.csv、final.png、logs/
set -o pipefail

DEPLOY=/home/justin/TJ-Superpower/deploy
WS=/home/justin/TJ-Superpower/sp_nav_drone_27
ANA=/home/justin/works/SP_drone/analysis
TS=$(date +%Y%m%d_%H%M%S)
OUT="/home/justin/works/SP_drone/runs/demo_$TS"
mkdir -p "$OUT/logs"
LOG="$OUT/demo.log"
exec > >(tee -a "$LOG") 2>&1

say() { echo "[demo $(date +%H:%M:%S)] $*"; }

# shellcheck disable=SC1091
source "$DEPLOY/host/env.sh"

# 0. 录制（HDMI 1920x1080）
say "开始录制 $OUT/demo.mp4"
ffmpeg -y -f x11grab -framerate 30 -video_size 1920x1080 -i :0.0+0,0 \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  "$OUT/demo.mp4" > "$OUT/logs/ffmpeg.log" 2>&1 &
FFPID=$!
sleep 2

# 1. 清缓存 + 停旧节点
say "清理仿真缓存"
bash "$DEPLOY/host/clear_sim_cache.sh" > "$OUT/logs/cache_clear.log" 2>&1
pkill -KILL -f 'static_voxel_ma[p]' 2>/dev/null
pkill -KILL -f 'planner_serve[r]' 2>/dev/null
pkill -KILL -f 'planner.launc[h]' 2>/dev/null
pkill -KILL -f 'nav_interface_nod[e]' 2>/dev/null
pkill -KILL -f 'nav_bt.launc[h]' 2>/dev/null
pkill -KILL -f 'sp_decision_nod[e]' 2>/dev/null
pkill -KILL -f 'decision.launc[h]' 2>/dev/null
pkill -KILL -f 'offboard_control[l]er_node' 2>/dev/null
pkill -KILL -f 'demo_logge[r]' 2>/dev/null
pkill -KILL -f 'rviz[2]' 2>/dev/null
sleep 2

# 2. 启动 GUI 仿真
say "启动 GUI 仿真"
( cd "$WS" && setsid nohup systemd-inhibit --what=sleep:idle --mode=block \
    --who=sp27-demo --why="SP27 demo" \
    bash "$DEPLOY/run_sim.sh" > "$OUT/launch.log" 2>&1 < /dev/null & )

# 3. 等 Gazebo 窗口，摆到左半屏
for _ in $(seq 1 60); do
  xwininfo -root -tree 2>/dev/null | grep -q '"Gazebo Sim"' && break
  sleep 1
done
sleep 2
python3 "$ANA/window_layout.py" > "$OUT/logs/layout1.log" 2>&1 || true

# 4. RViz（右半屏）
say "启动 RViz"
nohup rviz2 -d "$WS/src/sp_nav_bringup/rviz/demo.rviz" \
  --ros-args -p use_sim_time:=true > "$OUT/logs/rviz.log" 2>&1 &
sleep 6
python3 "$ANA/window_layout.py" > "$OUT/logs/layout2.log" 2>&1 || true

# 5. 控制器 + 绑核 + 解锁/垂直起飞
say "启动控制器并解锁"
nohup ros2 run offboard_controller offboard_controller_node --ros-args \
  --params-file "$WS/install/offboard_controller/share/offboard_controller/config/offboard_controller.yaml" \
  -p use_sim_time:=true -p control_mode:=external \
  > "$OUT/logs/controller.log" 2>&1 &
sleep 2
ros2 topic pub --once /offboard/command std_msgs/msg/String "{data: start_external}" >/dev/null 2>&1
bash "$DEPLOY/host/pin_sim_cpus.sh" 15 > "$OUT/logs/pin.log" 2>&1 || true

for _ in $(seq 1 40); do
  grep -q -- "TAKEOFF -> WAIT_PATH" "$OUT/logs/controller.log" && break
  sleep 2
done
if ! grep -q -- "TAKEOFF -> WAIT_PATH" "$OUT/logs/controller.log"; then
  say "起飞未完成，继续尝试启动任务栈"
else
  say "起飞完成（WAIT_PATH）"
fi

# 6. 轨迹记录 + 任务栈
say "启动地图/规划/BT/决策"
nohup python3 "$ANA/demo_logger.py" --out "$OUT/trajectory.csv" \
  > "$OUT/logs/logger.log" 2>&1 &
LOGPID=$!
nohup ros2 launch sp_nav_sim static_voxel_map.launch.py > "$OUT/logs/map.log" 2>&1 &
nohup ros2 launch sp_global_planner planner.launch.py > "$OUT/logs/planner.log" 2>&1 &
nohup ros2 launch sp_nav_bt nav_bt.launch.py use_sim_time:=true > "$OUT/logs/navbt.log" 2>&1 &
sleep 2
nohup ros2 launch sp_decision decision.launch.py use_sim_time:=true > "$OUT/logs/decision.log" 2>&1 &

# 7. 等任务完成
for _ in $(seq 1 60); do
  grep -q "Mission finished" "$OUT/logs/decision.log" 2>/dev/null && break
  sleep 2
done
say "任务阶段结束"
sleep 3

# 8. 降落
ros2 topic pub --once /offboard/command std_msgs/msg/String "{data: land}" >/dev/null 2>&1
sleep 12

# 9. 收尾
kill "$LOGPID" 2>/dev/null
sleep 1
python3 -c "from PIL import ImageGrab; ImageGrab.grab(bbox=(0,0,1920,1080), xdisplay=':0').save('$OUT/final.png')" 2>/dev/null || true
kill -INT "$FFPID" 2>/dev/null
wait "$FFPID" 2>/dev/null || true

# 10. 复制关键日志
for f in controller launch planner navbt decision map pin; do
  [[ -f "$OUT/logs/$f.log" ]] && cp "$OUT/logs/$f.log" "$OUT/logs/" 2>/dev/null
done

say "完成：$OUT"
ls -lh "$OUT" | tail -8
