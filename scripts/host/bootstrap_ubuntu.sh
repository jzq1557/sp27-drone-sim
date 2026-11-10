#!/usr/bin/env bash
# =============================================================================
# P2：SP27 仿真栈系统依赖安装（Ubuntu 22.04 / ROS 2 **Humble** / Gazebo Harmonic）
#
# 用法（需要 sudo）：
#   sudo bash /home/justin/works/SP_drone/scripts/host/bootstrap_ubuntu.sh
#
# 特点：
#   - 幂等：已装的包会跳过；重复执行安全
#   - 只装 ROS 2 Humble：源固定为 ros2/ubuntu jammy（Humble），不添加 rolling/test 源
#   - 网络只走可达源：清华 ROS 镜像、OSRF 源；不依赖被墙的 github.com
#   - 装完做强校验：/opt/ros 必须只有 humble，ROS_DISTRO 必须 humble，gz 必须 8.15
#   - 不安装/不升级 NVIDIA 驱动（本机 580.178.04 open 驱动已工作）
#
# 日志：/var/log/sp27_bootstrap.log
# =============================================================================
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

LOG=/var/log/sp27_bootstrap.log
ROS_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ros2/ubuntu"
OSRF_KEY_URL="https://packages.osrfoundation.org/gazebo.gpg"

BASE_PKGS=(
  build-essential cmake ninja-build git curl wget unzip pkg-config
  python3-pip python3-dev python3-yaml python3-venv python3-numpy python3-opencv
  libeigen3-dev libboost-all-dev libopencv-dev
  libglew-dev libepoxy-dev libgl1-mesa-dev libglu1-mesa-dev
  libwayland-dev libxkbcommon-dev wayland-protocols libegl1-mesa-dev
  libssl-dev protobuf-compiler libgoogle-glog-dev
  libsuitesparse-dev libyaml-cpp-dev libtbb-dev
  libjpeg-dev libpng-dev libtiff-dev
  mesa-utils xterm lsof htop rsync bzip2
)

# 只列 ros-humble-*；不要改发行版
ROS_PKGS=(
  ros-humble-ros-base
  ros-humble-ros2cli
  ros-humble-ros2run
  ros-humble-ros2launch
  ros-humble-ros2topic
  ros-humble-ros2service
  ros-humble-ros2param
  ros-humble-ros2node
  ros-humble-mavros
  ros-humble-mavros-extras
  ros-humble-image-transport
  ros-humble-cv-bridge
  ros-humble-tf2-ros
  ros-humble-tf2-tools
  ros-humble-tf2-geometry-msgs
  ros-humble-rviz2
  ros-humble-rmw-cyclonedds-cpp
  ros-humble-xacro
  ros-humble-ros-gz
  ros-humble-ros-gz-bridge
  ros-humble-ros-gz-image
  ros-humble-ros-gz-sim
  python3-colcon-common-extensions
)

log()  { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[警告] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }
run()  { echo "+ $*"; "$@"; }

# 过滤当前 apt 索引里不存在的包名：一个错名不再让整条 apt 失败
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

log "0. 基础信息"
{
  echo "日期: $(date -Is)"
  echo "系统: $(. /etc/os-release; echo "$PRETTY_NAME")"
  echo "内核: $(uname -r)"
  echo "内存: $(free -b | awk 'NR==2{printf "%.1f GiB", $2/1073741824}')  CPU: $(nproc)"
  echo "根分区: $(df -h / | awk 'NR==2{print $4" 可用"}')"
  echo "GPU: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo 'nvidia-smi 不可用')"
  echo "现有 ROS: $(ls /opt/ros 2>/dev/null || echo '无')"
}

log "1. apt 索引"
run apt-get update

log "2. 基础编译链与视觉依赖"
install_available "基础依赖" "${BASE_PKGS[@]}"

log "3. ROS 2 Humble 源（清华镜像，仅 jammy/Humble）"
KEYRING=/usr/share/keyrings/ros-archive-keyring.gpg
if [[ ! -s $KEYRING ]]; then
  TMPKEY=$(mktemp)
  run curl -fsSL "http://packages.ros.org/ros.key" -o "$TMPKEY"
  # 官方 ros.key 是二进制 OpenPGP；若是 ASCII armor 则 dearmor
  if head -c 1 "$TMPKEY" | od -An -c | grep -q -- '-'; then
    gpg --dearmor < "$TMPKEY" > "$KEYRING"
  else
    cp "$TMPKEY" "$KEYRING"
  fi
  rm -f "$TMPKEY"
fi
# 关键：apt 抓取时以 _apt 用户读取 keyring；权限 600 会报 "没有公钥"
chmod 644 "$KEYRING" 2>/dev/null || true
# 若系统里已有别的 ROS 2 源（例如 fishros 的 ros-fish.list），不要再重复添加
EXISTING_ROS_SRC=$(grep -rls "ros2/ubuntu" /etc/apt/sources.list.d/*.list 2>/dev/null | grep -v '/ros2\.list$' | head -1 || true)
if [[ -n ${EXISTING_ROS_SRC:-} ]]; then
  echo "已有 ROS 2 源：$EXISTING_ROS_SRC，跳过添加"
else
  echo "deb [arch=amd64 signed-by=$KEYRING] $ROS_MIRROR jammy main" \
    > /etc/apt/sources.list.d/ros2.list
fi
# 防御：删掉可能存在的其他 ROS 发行版源，避免混装
for f in /etc/apt/sources.list.d/ros2-*.list; do
  [[ -e $f ]] || continue
  case $f in /etc/apt/sources.list.d/ros2.list) ;; *) warn "移除疑似混源: $f"; rm -f "$f";; esac
done

log "4. OSRF Gazebo 源（Harmonic + ros-gz 依赖的 ignition 库）"
if [[ ! -s /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg ]]; then
  run curl -fsSL "$OSRF_KEY_URL" -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
fi
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable jammy main" \
  > /etc/apt/sources.list.d/gazebo-stable.list
run apt-get update

log "5. ROS 2 Humble 包（ros-humble-*）"
install_available "ROS 2 Humble 包" "${ROS_PKGS[@]}"
# colcon 若系统已有 python3-colcon-common-extensions 会跳过；补一个兜底检查
command -v colcon >/dev/null 2>&1 || run apt-get install -y python3-colcon-common-extensions

log "6. Gazebo Harmonic"
if dpkg -s gz-harmonic >/dev/null 2>&1; then
  echo "gz-harmonic 已安装，跳过"
else
  run apt-get install -y --no-install-recommends gz-harmonic
fi

log "7. GeographicLib geoid 数据（MAVROS 启动需要）"
GEO_DIR=/usr/share/GeographicLib/geoids
if [[ -f $GEO_DIR/egm96-5.pgm ]] || compgen -G "$GEO_DIR/*.pgm" >/dev/null; then
  echo "系统 geoid 已存在"
elif [[ -f /home/justin/.local/share/GeographicLib/geoids/egm96-5.pgm ]]; then
  echo "使用 WSL 迁移来的 ~/.local/share/GeographicLib（无需 sudo 安装）"
else
  TMPG=$(mktemp -d)
  if run curl -fL --retry 2 -o "$TMPG/egm96-5.tar.bz2" \
       "https://downloads.sourceforge.net/project/geographiclib/geoids-distrib/egm96-5.tar.bz2"; then
    mkdir -p /usr/share/GeographicLib
    run tar -xjf "$TMPG/egm96-5.tar.bz2" -C /usr/share/GeographicLib
    echo "geoid 安装到 /usr/share/GeographicLib"
  else
    warn "geoid 下载失败；若 MAVROS 启动报 geoid 缺失，可稍后从 WSL 迁 ~/.local/share/GeographicLib"
  fi
  rm -rf "$TMPG"
fi

log "8. pip 镜像（避免 pypi.org 超时）"
if [[ -d /etc ]]; then
  cat > /etc/pip.conf <<'EOF'
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
timeout = 30
EOF
fi
echo "pip 默认源已指向清华镜像（/etc/pip.conf）"

log "9. 强校验"
FAIL=0
check() { if eval "$2"; then echo "[PASS] $1"; else echo "[FAIL] $1"; FAIL=$((FAIL+1)); fi; }

check "/opt/ros 只有 humble" '[[ "$(ls /opt/ros 2>/dev/null | tr -d "\n")" == "humble" ]]'
check "ROS_DISTRO=humble" 'bash -c "source /opt/ros/humble/setup.bash && [[ \$ROS_DISTRO == humble ]]"'
check "ros2 CLI" 'bash -c "source /opt/ros/humble/setup.bash && command -v ros2"'
check "mavros 包" 'bash -c "source /opt/ros/humble/setup.bash && ros2 pkg prefix mavros >/dev/null 2>&1"'
check "mavros_extras 包" 'bash -c "source /opt/ros/humble/setup.bash && ros2 pkg prefix mavros_extras >/dev/null 2>&1"'
check "ros_gz_bridge 包（apt Fortress 版，运行时由源码版覆盖）" 'bash -c "source /opt/ros/humble/setup.bash && ros2 pkg prefix ros_gz_bridge >/dev/null 2>&1"'
check "gz 8.15" 'gz sim --versions 2>/dev/null | head -1 | grep -q "8\\.15"'
check "colcon" 'command -v colcon'
check "python cv2" 'python3 -c "import cv2"'
check "gcc/g++/cmake/ninja" 'command -v gcc && command -v g++ && command -v cmake && command -v ninja'
check "nvidia-smi" 'nvidia-smi -L >/dev/null 2>&1'
echo "[INFO] GL 信息（需要图形会话，sudo 下可能不可见）：$(DISPLAY=${DISPLAY:-:0} glxinfo -B 2>/dev/null | grep -i 'OpenGL renderer' || echo '未取到（不影响安装结论）')"

log "10. 结果"
{
  echo "ROS: $(ls /opt/ros)"
  echo "gz : $(gz sim --versions 2>/dev/null | head -1)"
  echo "colcon: $(colcon --version 2>/dev/null | head -1 || true)"
  echo "gcc: $(gcc --version | head -1)"
  echo "cmake: $(cmake --version | head -1)"
  echo "GPU: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo n/a)"
  echo "geoid: $(ls /usr/share/GeographicLib/geoids 2>/dev/null | head -1) / $(ls /home/justin/.local/share/GeographicLib/geoids 2>/dev/null | head -1)"
} | tee /home/justin/works/SP_drone/artifacts/bootstrap_summary.txt

if (( FAIL > 0 )); then
  die "有 $FAIL 项校验失败，见上；完整日志 $LOG"
fi
echo
echo "全部通过。下一步（不需要 sudo）：P3 栈重建。"
