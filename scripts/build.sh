#!/usr/bin/env bash
# P4：构建 Pangolin → ORB_SLAM3 → 5 个 ROS 包。
# 前提：bootstrap_root.sh 已成功跑过（gz / ros_gz / mavros / 编译依赖就位）。
set -o pipefail

WS=/home/justin/TJ-Superpower/sp_nav_drone_27
PANGOLIN=$WS/src/sp_localization/Pangolin
ORB=$WS/src/sp_localization/ORB_SLAM3
JOBS=12

say() { echo; echo "=============== $* ==============="; }
die() { echo "[失败] $*"; exit 1; }

say "0. 依赖检查"
for c in gz cmake colcon make g++; do
  command -v "$c" >/dev/null || die "缺少命令: $c（请先跑 bootstrap_root.sh）"
done
# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash || die "找不到 ROS Humble"
ros2 pkg prefix ros_gz_bridge >/dev/null 2>&1 || die "缺少 ros_gz_bridge"
ros2 pkg prefix ros_gz_image  >/dev/null 2>&1 || die "缺少 ros_gz_image"
ros2 pkg prefix mavros        >/dev/null 2>&1 || die "缺少 mavros"
echo "gz: $(gz sim --versions 2>/dev/null | head -1)"
echo "内存可用: $(awk '/MemAvailable/{printf "%.1f GB", $2/1048576}' /proc/meminfo)"

say "1. 构建 Pangolin v0.6（不安装，留在工作区内）"
[[ -d $PANGOLIN/src ]] || die "Pangolin 源码缺失: $PANGOLIN"
cd "$PANGOLIN" || exit 1
cmake -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_EXAMPLES=OFF \
      -DBUILD_TESTS=OFF \
      -DBUILD_TOOLS=OFF \
      -DBUILD_PANGOLIN_PYTHON=OFF \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 2>&1 | tail -12
cmake --build build -j"$JOBS" 2>&1 | tail -8 || die "Pangolin 构建失败"
ls -l build/src/libpangolin.so* 2>/dev/null || echo "[警告] 未找到 libpangolin.so，继续（ORB 阶段会报错）"

say "2. 构建 ORB_SLAM3（含 DBoW2 / g2o / Sophus）"
[[ -f $ORB/build.sh ]] || die "ORB_SLAM3/build.sh 缺失"
cd "$ORB" || exit 1
export CMAKE_PREFIX_PATH="$PANGOLIN/build/src:$CMAKE_PREFIX_PATH"
export MAKEFLAGS="-j$JOBS"
bash build.sh 2>&1 | tail -25
ls -l lib/libORB_SLAM3.so 2>/dev/null || die "ORB_SLAM3 库未生成"
ls -d Thirdparty/Sophus/build 2>/dev/null || die "Sophus 未构建"

say "3. colcon 构建（只编里程碑 A 需要的 5 个包）"
cd "$WS" || exit 1
# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
colcon build --symlink-install \
  --packages-select sp_robot_msg sp_nav_bringup orbslam3_ros vio_bridge offboard_controller \
  --cmake-args -DCMAKE_BUILD_TYPE=Release \
  2>&1 | tail -30

say "4. 结果"
# shellcheck disable=SC1091
source "$WS/install/setup.bash"
ros2 pkg list | grep -E "^(sp_nav_bringup|orbslam3_ros|vio_bridge|offboard_controller|sp_robot_msg)$" || die "包未安装成功"
echo "全部构建完成。"
