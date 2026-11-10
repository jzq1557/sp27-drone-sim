#!/usr/bin/env bash
# =============================================================================
# P2b：补齐 ROS 2 Humble 缺失组件 + 安装 Gazebo Harmonic
#
# 何时用：ROS 2 Humble 已经装好（例如用 fishros 装过），但缺
#   - MAVROS（mavros / mavros_extras）
#   - ros_gz（bridge / image / interfaces）
#   - xacro、rmw-cyclonedds-cpp
#   - Gazebo Harmonic（gz 命令不存在）
#
# 用法：sudo bash install_extras.sh
# 幂等：已装的跳过；失败会打印原因。
# =============================================================================
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

OSRF_KEY_URL="https://packages.osrfoundation.org/gazebo.gpg"
OSRF_KEYRING=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
LOG=/var/log/sp27_extras.log

log()  { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[警告] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }
run()  { echo "+ $*"; "$@"; }

install_available() {
  local desc=$1; shift
  local avail=() missing=()
  for p in "$@"; do
    if apt-cache show "$p" >/dev/null 2>&1; then avail+=("$p"); else missing+=("$p"); fi
  done
  ((${#missing[@]})) && warn "$desc：源里不存在，已跳过 -> ${missing[*]}"
  ((${#avail[@]})) || die "$desc：没有任何可安装的包"
  run apt-get install -y --no-install-recommends "${avail[@]}"
}

[[ $EUID -eq 0 ]] || die "必须用 sudo 运行：sudo bash $0"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

log "0. 现状"
echo "ROS: $(ls /opt/ros 2>/dev/null || echo 无)"
echo "gz : $(gz sim --versions 2>/dev/null | head -1 || echo '未安装')"
ls -l /etc/apt/sources.list.d/ 2>/dev/null | tail -5

log "1. 确保 OSRF Gazebo 源存在"
mkdir -p /usr/share/keyrings
if [[ ! -s $OSRF_KEYRING ]]; then
  run curl -fsSL "$OSRF_KEY_URL" -o "$OSRF_KEYRING"
fi
chmod 644 "$OSRF_KEYRING"
echo "deb [arch=amd64 signed-by=$OSRF_KEYRING] http://packages.osrfoundation.org/gazebo/ubuntu-stable jammy main" \
  > /etc/apt/sources.list.d/gazebo-stable.list

log "2. apt 索引"
run apt-get update

log "3. ROS 2 Humble 补充包"
install_available "ROS 2 Humble 补充包" \
  ros-humble-mavros \
  ros-humble-mavros-extras \
  ros-humble-ros-gz \
  ros-humble-ros-gz-bridge \
  ros-humble-ros-gz-image \
  ros-humble-ros-gz-sim \
  ros-humble-xacro \
  ros-humble-rmw-cyclonedds-cpp \
  ros-humble-tf2-geometry-msgs \
  ros-humble-tf2-tools \
  ros-humble-ros2cli \
  ros-humble-ros2topic \
  ros-humble-ros2service \
  ros-humble-ros2param \
  ros-humble-ros2node \
  ros-humble-ros2launch \
  ros-humble-ros2run

log "4. Gazebo Harmonic"
if dpkg -s gz-harmonic >/dev/null 2>&1; then
  echo "已安装，跳过"
else
  run apt-get install -y --no-install-recommends gz-harmonic
fi

log "5. 校验"
FAIL=0
check() { if eval "$2"; then echo "[PASS] $1"; else echo "[FAIL] $1"; FAIL=$((FAIL+1)); fi; }
check "ROS_DISTRO=humble" 'bash -c "source /opt/ros/humble/setup.bash && [[ \$ROS_DISTRO == humble ]]"'
check "mavros" 'bash -c "source /opt/ros/humble/setup.bash && ros2 pkg prefix mavros >/dev/null 2>&1"'
check "mavros_extras" 'bash -c "source /opt/ros/humble/setup.bash && ros2 pkg prefix mavros_extras >/dev/null 2>&1"'
check "ros_gz_bridge" 'bash -c "source /opt/ros/humble/setup.bash && ros2 pkg prefix ros_gz_bridge >/dev/null 2>&1"'
check "ros_gz_image" 'bash -c "source /opt/ros/humble/setup.bash && ros2 pkg prefix ros_gz_image >/dev/null 2>&1"'
check "xacro" 'bash -c "source /opt/ros/humble/setup.bash && ros2 pkg prefix xacro >/dev/null 2>&1"'
check "rmw_cyclonedds" 'bash -c "source /opt/ros/humble/setup.bash && ros2 pkg prefix rmw_cyclonedds_cpp >/dev/null 2>&1"'
check "gz 8.15+" 'gz sim --versions 2>/dev/null | head -1 | grep -qE "8\\.(15|16|17)"'
check "geoid" '[[ -f /home/justin/.local/share/GeographicLib/geoids/egm96-5.pgm || -f /usr/share/GeographicLib/geoids/egm96-5.pgm ]]'

echo
if (( FAIL > 0 )); then
  die "$FAIL 项失败，见上；日志 $LOG"
fi
echo "全部补齐。下一步（不需要 sudo）：重建 colcon 包与 ros_gz_ws。"
