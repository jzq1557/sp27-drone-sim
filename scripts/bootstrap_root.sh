#!/usr/bin/env bash
# SP27 仿真环境一次性系统依赖安装（在 WSL2 Ubuntu 22.04 上执行）
# 用法：sudo bash /home/justin/TJ-Superpower/deploy/bootstrap_root.sh
# 幂等：可以重复执行，已装好的包会跳过。
set -o pipefail

DEPLOY=/home/justin/TJ-Superpower/deploy
LOG=$DEPLOY/bootstrap.log
export DEBIAN_FRONTEND=noninteractive

step() { echo; echo "=============== $* ===============" | tee -a "$LOG"; }
run()  { echo "+ $*" | tee -a "$LOG"; "$@" 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; }

if [[ $EUID -ne 0 ]]; then
  echo "必须用 sudo 运行：sudo bash $0" >&2
  exit 1
fi

mkdir -p "$DEPLOY"
: > "$LOG"

step "0. 基础信息"
{
  echo "date: $(date -Is)"
  echo "kernel: $(uname -r)"
  echo "os: $(. /etc/os-release; echo "$PRETTY_NAME")"
  echo "memory: $(free -h | awk '/^Mem:/{print $2}')"
  nproc
} 2>&1 | tee -a "$LOG"

########################################################################
step "1. 安装校园网根证书（修复 github/pypi 的 HTTPS）"
########################################################################
shopt -s nullglob
certs=("$DEPLOY"/certs/scholar-root-ca-v*.pem)
if (( ${#certs[@]} )); then
  for f in "${certs[@]}"; do
    base=$(basename "$f" .pem)
    run cp -f "$f" "/usr/local/share/ca-certificates/${base}.crt"
  done
  run update-ca-certificates
  echo "已安装 ${#certs[@]} 张证书" | tee -a "$LOG"
else
  echo "[警告] 未找到 $DEPLOY/certs/scholar-root-ca-v*.pem，跳过" | tee -a "$LOG"
fi
shopt -u nullglob

step "2. apt 索引更新"
run apt-get update

########################################################################
step "3. 基础编译链与机器视觉依赖"
########################################################################
BASE_PKGS=(
  build-essential cmake ninja-build git curl wget unzip pkg-config
  python3-pip python3-dev python3-vcstool python3-yaml
  libeigen3-dev libboost-all-dev libopencv-dev
  libglew-dev libepoxy-dev libgl1-mesa-dev libglu1-mesa-dev
  libwayland-dev libxkbcommon-dev wayland-protocols libegl1-mesa-dev
  libssl-dev protobuf-compiler libgoogle-glog-dev
  libsuitesparse-dev libyaml-cpp-dev libpython3-dev libtbb-dev
  libjpeg-dev libpng-dev libtiff-dev
  xterm lsof htop rsync
)
run apt-get install -y --no-install-recommends "${BASE_PKGS[@]}"

########################################################################
step "4. Gazebo Harmonic (gz-sim8) —— 来自 OSRF 官方源"
########################################################################
if dpkg -s gz-harmonic >/dev/null 2>&1; then
  echo "gz-harmonic 已安装，跳过" | tee -a "$LOG"
else
  if run bash -c 'curl -fsSL https://packages.osrfoundation.org/gazebo.gpg -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg'; then
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable jammy main" \
      > /etc/apt/sources.list.d/gazebo-stable.list
    run apt-get update
    run apt-get install -y --no-install-recommends gz-harmonic
  else
    echo "[错误] 无法获取 OSRF 签名，Gazebo 未安装；后续步骤仍会继续" | tee -a "$LOG"
  fi
fi

########################################################################
step "5. ROS 2 侧运行依赖（ros_gz / mavros / 桥接）"
########################################################################
ROS_PKGS=(
  ros-humble-ros-gz
  ros-humble-ros-gz-bridge
  ros-humble-ros-gz-image
  ros-humble-ros-gz-sim
  ros-humble-mavros
  ros-humble-mavros-extras
  ros-humble-image-transport
  ros-humble-cv-bridge
  ros-humble-tf2-ros
  ros-humble-tf2-tools
  ros-humble-rviz2
  ros-humble-rmw-cyclonedds-cpp
  ros-humble-xacro
)
run apt-get install -y --no-install-recommends "${ROS_PKGS[@]}"

step "6. MAVROS 的 GeographicLib 数据集（GPS/海拔转换用，失败不阻塞）"
if [[ -d /usr/share/GeographicLib/geoids ]]; then
  echo "数据集已存在，跳过" | tee -a "$LOG"
else
  TMPG=$(mktemp -d)
  if run bash -c "curl -fsSL https://raw.githubusercontent.com/mavlink/mavros/master/mavros/scripts/install_geographiclib_datasets.sh -o $TMPG/geo.sh && bash $TMPG/geo.sh"; then
    echo "GeographicLib 数据集安装完成" | tee -a "$LOG"
  else
    echo "[警告] GeographicLib 数据集安装失败（不影响本地 ENU 仿真）" | tee -a "$LOG"
  fi
  rm -rf "$TMPG"
fi

########################################################################
step "7. PX4 工具链依赖（PX4 源码就位后执行其官方脚本）"
########################################################################
PX4_UBUNTU_SCRIPT=/home/justin/TJ-Superpower/sp_nav_drone_27/src/sp_filght_sim/external_files/PX4-Autopilot/Tools/setup/ubuntu.sh
if [[ -f $PX4_UBUNTU_SCRIPT ]]; then
  echo "发现 PX4 官方依赖脚本，执行（--no-nuttx：只要 SITL，不要 NuttX 交叉工具链）" | tee -a "$LOG"
  echo "该脚本在 Ubuntu 22.04 上安装的正是 gz-harmonic，与本方案目标版本一致" | tee -a "$LOG"
  run bash -c "cd $(dirname "$PX4_UBUNTU_SCRIPT")/../.. && bash Tools/setup/ubuntu.sh --no-nuttx" || \
    echo "[警告] PX4 ubuntu.sh 返回非零，稍后按需补包" | tee -a "$LOG"
else
  echo "[跳过] 未找到 $PX4_UBUNTU_SCRIPT（等代码落地后再跑）" | tee -a "$LOG"
fi

########################################################################
step "8. 结果自检"
########################################################################
{
  echo "--- gz ---"
  if command -v gz >/dev/null; then gz sim --versions 2>/dev/null | head -3; else echo "gz 未安装"; fi
  echo "--- ros_gz ---"
  ls -d /opt/ros/humble/share/ros_gz_* 2>/dev/null | xargs -n1 basename 2>/dev/null || echo "ros_gz 未安装"
  echo "--- mavros ---"
  ls /opt/ros/humble/share/mavros/launch/px4.launch 2>/dev/null || echo "mavros 未安装"
  echo "--- https ---"
  curl -sS -o /dev/null -w "github=%{http_code}\n" https://github.com 2>&1 | tail -1
  echo "--- 内存 ---"
  free -h | head -2
} 2>&1 | tee -a "$LOG"

echo
echo "系统依赖安装结束，完整日志：$LOG"
echo "下一步（不需要 sudo，我来做）：给 PX4 打补丁、导出仿真资源、colcon 构建。"
