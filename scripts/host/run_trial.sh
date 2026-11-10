#!/usr/bin/env bash
# VIO 调参试验：一次「干净重启 → 起飞 → 8°/s 固定航线 → 降落 → 分析」。
#
# 用法：
#   bash run_trial.sh <label>
# 输出：/home/justin/works/SP_drone/runs/vio_tune/<label>/<时间戳>/
#   launch.log  controller.log  probe.csv  summary.txt
set -o pipefail

DEPLOY=/home/justin/TJ-Superpower/deploy
WS=/home/justin/TJ-Superpower/sp_nav_drone_27
LABEL="${1:?用法: run_trial.sh <label>}"
STAMP=$(date +%H%M%S)
OUT="/home/justin/works/SP_drone/runs/vio_tune/$LABEL/$STAMP"
mkdir -p "$OUT"
LOG="$OUT/trial.log"
exec > >(tee -a "$LOG") 2>&1

# shellcheck disable=SC1091
source "$DEPLOY/host/env.sh"

say() { echo "[trial $(date +%H:%M:%S)] $*"; }

stop_sim() {
  pkill -INT -f 'ros2 laun[c]h sp_nav_bringup' 2>/dev/null
  pkill -INT -f 'offboard_control[l]er_node' 2>/dev/null
  pkill -INT -f 'gz si[m]' 2>/dev/null
  pkill -INT -f 'p[x]4_sitl_default/bin' 2>/dev/null
  sleep 3
  pkill -KILL -f 'gz si[m]' 2>/dev/null
  pkill -KILL -f 'p[x]4_sitl_default/bin' 2>/dev/null
  sleep 2
}

reset_px4_params() {
  local root="$SP27_PX4/build/px4_sitl_default/rootfs"
  mkdir -p /home/justin/works/SP_drone/artifacts/px4_param_backup
  [[ -f "$root/parameters.bson" ]] && mv "$root/parameters.bson" \
    "/home/justin/works/SP_drone/artifacts/px4_param_backup/parameters_${STAMP}.bson" 2>/dev/null
  [[ -f "$root/parameters_backup.bson" ]] && mv "$root/parameters_backup.bson" \
    "/home/justin/works/SP_drone/artifacts/px4_param_backup/parameters_backup_${STAMP}.bson" 2>/dev/null
  true
}

start_sim() {
  ( cd "$WS" && setsid nohup systemd-inhibit --what=sleep:idle --mode=block \
      --who="sp27-trial-$LABEL" --why="SP27 trial $LABEL" \
      bash "$DEPLOY/run_sim.sh" > "$OUT/launch.log" 2>&1 < /dev/null & )
}

state_field() {  # $1 = armed|mode|connected
  timeout 3 ros2 topic echo --once /mavros/state 2>/dev/null | awk -v k="$1:" '$1==k{print $2; exit}'
}

local_ok() {
  local p x y
  p=$(timeout 3 ros2 topic echo --once /mavros/local_position/pose --field pose.position 2>/dev/null)
  x=$(echo "$p" | awk '/x:/{print $2; exit}')
  y=$(echo "$p" | awk '/y:/{print $2; exit}')
  [[ -n "$x" && -n "$y" ]] || return 1
  awk -v x="$x" -v y="$y" 'BEGIN{exit !(x*x+y*y < 4.0)}'
}

wait_ready() {
  local i
  for i in $(seq 1 40); do
    [[ "$(state_field connected)" == "true" ]] && break
    sleep 2
  done
  sleep 12
  local j
  for j in $(seq 1 10); do
    if timeout 4 ros2 topic echo --once /mavros/vision_pose/pose_cov >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  for j in $(seq 1 15); do
    local_ok && return 0
    sleep 2
  done
  return 1
}

run_mission() {
  nohup ros2 run offboard_controller offboard_controller_node --ros-args \
    --params-file "$WS/install/offboard_controller/share/offboard_controller/config/offboard_controller.yaml" \
    -p use_sim_time:=true \
    -p turn_rate_deg_s:=8.0 -p turn_segments:=1 -p turn_accel_deg_s2:=7.5 \
    > "$OUT/controller.log" 2>&1 &
  disown
  sleep 4
  timeout 8 ros2 topic pub --once /offboard/command std_msgs/msg/String "{data: start_builtin}" >/dev/null 2>&1
}

wait_done() {
  local i a m armed_seen=0
  for i in $(seq 1 150); do
    a=$(state_field armed); m=$(state_field mode)
    [[ "$a" == "true" ]] && armed_seen=1
    if (( armed_seen == 1 )) && [[ "$a" == "false" ]] && [[ "$m" != "OFFBOARD" ]]; then
      return 0
    fi
    if (( armed_seen == 0 )) && (( i > 40 )); then
      say "40 秒内未解锁，判定启动异常"
      return 1
    fi
    sleep 2
  done
  return 1
}

say "===== 试验 $LABEL / $STAMP ====="
for attempt in 1 2; do
  say "第 $attempt 次启动（完整清理缓存）"
  bash "$DEPLOY/host/clear_sim_cache.sh" > "$OUT/cache_clear_$attempt.log" 2>&1
  start_sim
  if wait_ready; then
    break
  fi
  say "启动未就绪，重试"
done

# 探针
nohup python3 /home/justin/works/SP_drone/analysis/flight_probe.py \
  --out "$OUT/probe.csv" > "$OUT/probe.log" 2>&1 &
PROBE=$!
disown

sleep 2
if run_mission && wait_done; then
  say "航线完成"
else
  say "航线未正常完成（见 controller.log）"
fi
sleep 3
kill "$PROBE" 2>/dev/null
pkill -INT -f 'offboard_control[l]er_node' 2>/dev/null

# 分析
D=$(ls -dt "$WS"/log/orbslam3_flights/flight_* | head -1)
{
  echo "session: $D"
  python3 /home/justin/works/SP_drone/analysis/diagnose_session.py "$D" 2>/dev/null
  echo
  echo "--- controller 关键事件 ---"
  grep -E "Continuous turn|Turn paused|LANDING|REMOTE|BUILTIN" "$OUT/controller.log" | tail -12
  echo
  python3 - "$D" "$OUT/probe.csv" <<'PY'
import csv, statistics, sys
from pathlib import Path
d = Path(sys.argv[1]); probe = Path(sys.argv[2])
tr = list(csv.DictReader(open(d / "tracking.csv")))
bh = list(csv.DictReader(open(d / "bridge_health.csv")))
states = {}
for r in bh:
    states.setdefault(r["signal"], []).append(int(float(r["value"])))
imu = states.get("/orbslam3/imu_initialized", [])
print("tracking:", {s: sum(1 for r in tr if r["tracking_state"] == s) for s in sorted({r["tracking_state"] for r in tr})})
print("imu_initialized ones:", sum(imu), "/", len(imu))
if probe.is_file():
    rows = list(csv.DictReader(open(probe)))
    lags = [float(r["vision_lag_s"]) for r in rows]
    if lags:
        print(f"vision lag: median={statistics.median(lags)*1000:.0f} ms p95={sorted(lags)[int(.95*(len(lags)-1))]*1000:.0f} ms")
    # local 是 PX4 局部系（原点在起飞点），truth 是世界系；先扣除首帧固定偏移再比
    if rows:
        ox = float(rows[0]["local_x"]) - float(rows[0]["truth_x"])
        oy = float(rows[0]["local_y"]) - float(rows[0]["truth_y"])
        oz = float(rows[0]["local_z"]) - float(rows[0]["truth_z"])
        errs = []
        for r in rows:
            dx = float(r["local_x"]) - float(r["truth_x"]) - ox
            dy = float(r["local_y"]) - float(r["truth_y"]) - oy
            dz = float(r["local_z"]) - float(r["truth_z"]) - oz
            errs.append((dx*dx + dy*dy + dz*dz) ** 0.5)
        print(f"local-vs-truth(对齐后): median={statistics.median(errs)*100:.1f} cm max={max(errs)*100:.1f} cm")
PY
} > "$OUT/summary.txt"

stop_sim
echo
echo "===== $LABEL 结果 ====="
cat "$OUT/summary.txt"
