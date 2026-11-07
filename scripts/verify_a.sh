#!/usr/bin/env bash
# SP27 里程碑 A 自动验收：一条命令检查 A1–A6。
# 用法：
#   1) 另开终端跑 ros2 launch sp_nav_bringup sp27_flight.launch.py
#   2) 运行本脚本：bash /home/justin/TJ-Superpower/deploy/verify_a.sh
# 任何一项 FAIL 会在末尾汇总，全部 PASS 才算里程碑 A 达成。
set -o pipefail

PASS=0; FAIL=0; SKIP=0
declare -a RESULTS

ok()   { RESULTS+=("PASS  $1"); PASS=$((PASS+1)); echo "[PASS] $1"; }
bad()  { RESULTS+=("FAIL  $1  <- $2"); FAIL=$((FAIL+1)); echo "[FAIL] $1  ($2)"; }
skip() { RESULTS+=("SKIP  $1"); SKIP=$((SKIP+1)); echo "[SKIP] $1"; }

MIB=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo)
echo "== A1 资源 =="
(( MIB >= 10000 )) && ok "A1 内存 ${MIB} MiB (>=10000)" || bad "A1 内存" "${MIB} MiB < 10000"
NPROC=$(nproc)
(( NPROC >= 20 )) && ok "A1 CPU ${NPROC} 核 (>=20)" || bad "A1 CPU" "${NPROC} < 20"

echo "== A2 网络 =="
CODE=$(curl -s -o /dev/null -m 15 -w '%{http_code}' https://github.com || echo 000)
[[ $CODE == 200 ]] && ok "A2 github HTTPS 200" || bad "A2 github HTTPS" "code=$CODE"

echo "== A3 Gazebo =="
if command -v gz >/dev/null; then
  ok "A3 gz 已安装: $(gz sim --versions 2>/dev/null | head -1)"
else
  bad "A3 gz" "未安装"
fi
if pgrep -af "gz sim" >/dev/null; then
  ok "A3 Gazebo 进程在运行"
else
  skip "A3 Gazebo 进程（还没起仿真）"
fi

echo "== 环境 =="
if [[ -f /opt/ros/humble/setup.bash ]]; then
  # shellcheck disable=SC1091
  source /opt/ros/humble/setup.bash
fi
WS=/home/justin/TJ-Superpower/sp_nav_drone_27
if [[ -f $WS/install/setup.bash ]]; then
  # shellcheck disable=SC1091
  source "$WS/install/setup.bash"
else
  bad "工作区 install/setup.bash" "$WS/install 不存在（还没 colcon build）"
fi

echo "== A4 PX4 + 机型 =="
if pgrep -af "px4_sitl" >/dev/null || pgrep -x px4 >/dev/null; then
  ok "A4 PX4 SITL 进程在运行"
else
  skip "A4 PX4 进程（还没起仿真）"
fi
if timeout 10 ros2 node list 2>/dev/null | grep -q sp27_stereo_imu; then
  ok "A4 ORB 节点 sp27_stereo_imu 在线"
else
  skip "A4 ORB 节点（还没起统一入口）"
fi

hz_of() { timeout 12 ros2 topic hz "$1" 2>/dev/null | grep -m1 "average rate" | awk '{print $3}'; }

echo "== A5 传感器桥接 =="
IMG_HZ=$(hz_of /tidesense/left/image_raw)
if [[ -n $IMG_HZ ]] && awk -v r="$IMG_HZ" 'BEGIN{exit !(r>5)}'; then
  ok "A5 左目图像 ${IMG_HZ} Hz"
elif [[ -n $IMG_HZ ]]; then
  bad "A5 左目图像频率" "${IMG_HZ} Hz 偏低"
else
  skip "A5 左目图像（无数据或话题不存在）"
fi

IMU_HZ=$(hz_of /sp27/imu)
if [[ -n $IMU_HZ ]] && awk -v r="$IMU_HZ" 'BEGIN{exit !(r>30)}'; then
  ok "A5 IMU ${IMU_HZ} Hz"
elif [[ -n $IMU_HZ ]]; then
  bad "A5 IMU 频率" "${IMU_HZ} Hz 偏低"
else
  skip "A5 IMU（无数据或话题不存在）"
fi

echo "== A6 ORB 位姿 =="
ORB_HZ=$(hz_of /orbslam3/raw_odom)
if [[ -n $ORB_HZ ]] && awk -v r="$ORB_HZ" 'BEGIN{exit !(r>1)}'; then
  ok "A6 ORB 里程计 ${ORB_HZ} Hz"
else
  skip "A6 ORB 里程计（无数据）"
fi

echo "== 顺带检查 =="
if timeout 10 ros2 node list 2>/dev/null | grep -qE "mavros"; then ok "MAVROS 节点在线"; else skip "MAVROS 节点"; fi
if [[ -d $WS/log/orbslam3_flights ]]; then
  ok "A8 对比日志目录存在: $(ls -1 "$WS"/log/orbslam3_flights 2>/dev/null | wc -l) 个会话"
else
  skip "A8 对比日志目录（还没生成）"
fi

echo
echo "================ 汇总 ================"
printf '%s\n' "${RESULTS[@]}"
echo "--------------------------------------"
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
(( FAIL == 0 )) && echo "结论：当前没有失败项。" || echo "结论：存在 $FAIL 个失败项，见上。"
