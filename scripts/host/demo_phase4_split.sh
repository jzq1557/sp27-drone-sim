#!/usr/bin/env bash
# 阶段 4 demo（分轨录制）：
#   Gazebo / RViz / 前视相机 / 下视相机 分别输出文件
#   清缓存 → 重启 → 绑核 → 垂直起飞 → 两点任务 → 降落
set -o pipefail

DEPLOY=/home/justin/TJ-Superpower/deploy
WS=/home/justin/TJ-Superpower/sp_nav_drone_27
ANA=/home/justin/works/SP_drone/analysis
TS=$(date +%Y%m%d_%H%M%S)
OUT="/home/justin/works/SP_drone/runs/demo_split_$TS"
mkdir -p "$OUT/logs"
exec > >(tee -a "$OUT/demo.log") 2>&1
say() { echo "[demo $(date +%H:%M:%S)] $*"; }
source "$DEPLOY/host/env.sh"

# 0. 清缓存/停旧节点
say "清理缓存并停止旧节点"
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
pkill -KILL -f 'cam_record[e]r' 2>/dev/null
pkill -KILL -f 'rviz[2]' 2>/dev/null
pkill -KILL -f 'ffmpe[g]' 2>/dev/null
sleep 2

# 1. GUI 仿真
say "启动 GUI 仿真"
( cd "$WS" && setsid nohup systemd-inhibit --what=sleep:idle --mode=block \
    --who=sp27-demo --why="SP27 demo split" \
    bash "$DEPLOY/run_sim.sh" > "$OUT/launch.log" 2>&1 < /dev/null & )
for _ in $(seq 1 60); do
  xwininfo -root -tree 2>/dev/null | grep -q '"Gazebo Sim"' && break
  sleep 1
done
sleep 2

# 2. RViz
say "启动 RViz"
nohup rviz2 -d "$WS/src/sp_nav_bringup/rviz/demo.rviz" \
  --ros-args -p use_sim_time:=true > "$OUT/logs/rviz.log" 2>&1 &
sleep 6
python3 "$ANA/window_layout.py" > "$OUT/logs/layout.log" 2>&1 || true

# 3. 读取窗口几何
geo() {
  local title="$1" id
  id=$(xwininfo -root -tree 2>/dev/null | awk -v t="$title" 'index($0,t){print $1; exit}')
  [[ -n "$id" ]] || { echo "0 0 1280 720"; return; }
  xwininfo -id "$id" | awk '
    /Absolute upper-left X/{x=$4}
    /Absolute upper-left Y/{y=$4}
    /Width:/{w=$2}
    /Height:/{h=$2}
    END{print x, y, w, h}'
}
read GX GY GW GH < <(geo 'Gazebo Sim')
read RX RY RW RH < <(geo 'RViz')
# RViz 若压在 Gazebo 右侧，Gazebo 只截到 RViz 左边界，避免画面重叠
GZ_W=$GW
if (( RX > GX && RX < GX + GW )); then GZ_W=$((RX - GX)); fi
say "Gazebo ${GZ_W}x${GH}+${GX},${GY}; RViz ${RW}x${RH}+${RX},${RY}"

# 4. 四个录制器
say "启动四路录制"
ffmpeg -y -f x11grab -framerate 30 -video_size "${GZ_W}x${GH}" -i ":0.0+${GX},${GY}" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p "$OUT/gazebo.mp4" \
  > "$OUT/logs/ffmpeg_gazebo.log" 2>&1 &
FF_GZ=$!
ffmpeg -y -f x11grab -framerate 30 -video_size "${RW}x${RH}" -i ":0.0+${RX},${RY}" \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p "$OUT/rviz.mp4" \
  > "$OUT/logs/ffmpeg_rviz.log" 2>&1 &
FF_RV=$!
nohup python3 "$ANA/cam_recorder.py" --topic /tidesense/left/image_raw \
  --out "$OUT/forward_cam.mp4" > "$OUT/logs/cam_left.log" 2>&1 &
CAM_L=$!
nohup python3 "$ANA/cam_recorder.py" --topic /down_camera/image \
  --out "$OUT/down_cam.mp4" > "$OUT/logs/cam_down.log" 2>&1 &
CAM_D=$!
nohup python3 "$ANA/demo_logger.py" --out "$OUT/trajectory.csv" \
  > "$OUT/logs/logger.log" 2>&1 &
LOGPID=$!
sleep 2

# 5. 控制器 + 解锁/起飞
say "控制器解锁/垂直起飞"
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
say "起飞阶段：$(grep -c -- 'TAKEOFF -> WAIT_PATH' "$OUT/logs/controller.log")"

# 6. 任务栈
say "启动地图/规划/BT/决策"
nohup ros2 launch sp_nav_sim static_voxel_map.launch.py > "$OUT/logs/map.log" 2>&1 &
nohup ros2 launch sp_global_planner planner.launch.py > "$OUT/logs/planner.log" 2>&1 &
nohup ros2 launch sp_nav_bt nav_bt.launch.py use_sim_time:=true > "$OUT/logs/navbt.log" 2>&1 &
sleep 2
nohup ros2 launch sp_decision decision.launch.py use_sim_time:=true > "$OUT/logs/decision.log" 2>&1 &
for _ in $(seq 1 60); do
  grep -q "Mission finished" "$OUT/logs/decision.log" 2>/dev/null && break
  sleep 2
done
say "任务结束"
sleep 3

# 7. 降落
ros2 topic pub --once /offboard/command std_msgs/msg/String "{data: land}" >/dev/null 2>&1
sleep 12

# 8. 停止录制并转码
say "停止录制"
kill -INT "$CAM_L" "$CAM_D" "$LOGPID" 2>/dev/null
sleep 2
kill -INT "$FF_GZ" "$FF_RV" 2>/dev/null
wait "$FF_GZ" 2>/dev/null || true
wait "$FF_RV" 2>/dev/null || true
python3 -c "from PIL import ImageGrab; ImageGrab.grab(bbox=(0,0,1920,1080), xdisplay=':0').save('$OUT/final.png')" 2>/dev/null || true

say "完成：$OUT"
ls -lh "$OUT" | tail -10
