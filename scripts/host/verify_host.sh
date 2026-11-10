#!/usr/bin/env bash
# 主机就绪检查：P2 装完后、以及每次改动环境后跑一遍。
# 用法：bash /home/justin/works/SP_drone/scripts/host/verify_host.sh
set -o pipefail

PASS=0; FAIL=0; INFO=0
ok()   { echo "[PASS] $*"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $*"; FAIL=$((FAIL+1)); }
info() { echo "[INFO] $*"; INFO=$((INFO+1)); }

echo "===== 1. 基础 ====="
[[ -f /etc/os-release ]] && info "$(. /etc/os-release; echo "$PRETTY_NAME") / $(uname -r)"
info "内存 $(free -h | awk '/^Mem:/{print $2}')，根分区 $(df -h / | awk 'NR==2{print $4}') 可用"

echo "===== 2. ROS 2 Humble ====="
if [[ -f /opt/ros/humble/setup.bash ]]; then ok "/opt/ros/humble 存在"
else bad "/opt/ros/humble 缺失（先跑 bootstrap_ubuntu.sh）"; fi
if [[ "$(ls /opt/ros 2>/dev/null | tr -d '\n')" == "humble" ]]; then ok "ROS 发行版唯一：humble"
else bad "/opt/ros 内容为：$(ls /opt/ros 2>/dev/null | tr '\n' ' ')"; fi

echo "===== 3. Gazebo ====="
if command -v gz >/dev/null 2>&1; then
  V=$(gz sim --versions 2>/dev/null | head -1)
  case "$V" in *8.15*) ok "gz $V";; *) bad "gz 版本 $V（期望 8.15.x）";; esac
else bad "gz 未安装"; fi

echo "===== 4. 工具链 ====="
for c in gcc g++ cmake ninja git colcon; do
  command -v "$c" >/dev/null 2>&1 && ok "$c -> $(command -v $c)" || bad "$c 缺失"
done
python3 -c "import cv2, numpy" 2>/dev/null && ok "python3 cv2/numpy" || bad "python3 缺 cv2/numpy"

echo "===== 5. 仿真栈路径 ====="
SP27_ROOT=/home/justin/TJ-Superpower
SP27_WS=$SP27_ROOT/sp_nav_drone_27
PX4=$SP27_WS/src/sp_filght_sim/external_files/PX4-Autopilot
for p in "$SP27_ROOT" "$SP27_WS/src" "$PX4" "$SP27_ROOT/ros_gz_ws" "$SP27_ROOT/pylibs"; do
  [[ -e $p ]] && ok "存在 $p" || bad "缺失 $p（P1 迁移未完成？）"
done
[[ -f $PX4/build/px4_sitl_default/bin/px4 ]] && ok "PX4 SITL 已构建" || info "PX4 SITL 未构建（P3 处理）"
[[ -d $PX4/Tools/simulation/gz/worlds ]] && ok "gz worlds 存在" || bad "gz worlds 缺失（PX4 资源未导出）"
[[ -d $PX4/Tools/simulation/gz/models ]] && ok "gz models 存在" || bad "gz models 缺失"
VOCOK=$(find "$SP27_WS/src/sp_localization/ORB_SLAM3/Vocabulary" -maxdepth 1 -type f 2>/dev/null | head -1)
[[ -n $VOCOK ]] && ok "ORB 词袋：$VOCOK" || bad "ORB 词袋缺失"

echo "===== 6. ros_gz（必须指向源码工作区） ====="
# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash 2>/dev/null || true
if [[ -f $SP27_ROOT/ros_gz_ws/install/setup.bash ]]; then
  # shellcheck disable=SC1091
  source "$SP27_ROOT/ros_gz_ws/install/setup.bash" 2>/dev/null || true
fi
PREFIX=$(ros2 pkg prefix ros_gz_bridge 2>/dev/null || true)
if [[ -n $PREFIX ]]; then
  case "$PREFIX" in
    *ros_gz_ws*) ok "ros_gz_bridge 来自 $PREFIX";;
    *) bad "ros_gz_bridge 指向 $PREFIX（不是 ros_gz_ws，Fortress 版会静默收不到数据）";;
  esac
else bad "ros_gz_bridge 未找到"; fi
for p in mavros mavros_extras image_transport cv_bridge tf2_ros; do
  ros2 pkg prefix "$p" >/dev/null 2>&1 && ok "ros2 包 $p" || bad "ros2 包 $p 缺失"
done

echo "===== 7. 迁移资产 ====="
MESH=/home/justin/works/SP_drone/assets/RMUC2027/meshes/model.dae
[[ -f $MESH ]] && ok "RMUC 网格 $(du -h "$MESH" | cut -f1)" || info "RMUC 网格未放置"
GEO1=$HOME/.local/share/GeographicLib/geoids/egm96-5.pgm
GEO2=/usr/share/GeographicLib/geoids/egm96-5.pgm
[[ -f $GEO1 ]] && ok "geoid（用户级）" || { [[ -f $GEO2 ]] && ok "geoid（系统级）" || bad "geoid 缺失（MAVROS 会启动即崩）"; }

echo "===== 8. 显卡 ====="
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null \
  && ok "nvidia-smi 正常" || bad "nvidia-smi 失败"
info "GL: $(DISPLAY=${DISPLAY:-:0} glxinfo -B 2>/dev/null | grep -i 'OpenGL renderer' | head -1 || echo '无图形会话')"

echo
echo "===== 汇总 ====="
echo "PASS=$PASS FAIL=$FAIL INFO=$INFO"
(( FAIL == 0 )) && echo "结论：主机就绪" || echo "结论：有 $FAIL 项需要处理"
