#!/usr/bin/env bash
# SP27 仿真环境变量集中定义。由 run_sim*.sh / 验证脚本 source。
# 兼容旧交接书里的绝对路径；源文件顺序不能改：
#   1) ROS 2 Humble
#   2) Harmonic 版 ros_gz（源码工作区，覆盖 apt 的 Fortress 版）
#   3) 主工作区
set -o pipefail

export SP27_ROOT="${SP27_ROOT:-/home/justin/TJ-Superpower}"
export SP27_WS="$SP27_ROOT/sp_nav_drone_27"
export SP27_PX4="$SP27_WS/src/sp_filght_sim/external_files/PX4-Autopilot"
export SP27_GZ="$SP27_PX4/Tools/simulation/gz"
export SP27_ROS_GZ_WS="$SP27_ROOT/ros_gz_ws"
export SP27_WORK="${SP27_WORK:-/home/justin/works/SP_drone}"

# PX4 跳过子模块联网检查（校园网/网络受限时必需）
export GIT_SUBMODULES_ARE_EVIL=1
export PATH="$HOME/.local/bin:$PATH"

# 渲染走独显：无头 gz 默认落在 Intel 核显，96 MB 的 RMUC 场地网格会把相机
# 拖到 ~5 Hz（围栏场景 15 Hz），ORB 因此反复 Timestamp jump。PRIME offload
# 让 gz 的 server 渲染用上 RTX 4060。
if [[ -n "${DISPLAY:-}" ]] && command -v nvidia-smi >/dev/null 2>&1; then
  export __NV_PRIME_RENDER_OFFLOAD=1
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
fi

# MAVROS 的 geoid：优先用 WSL 迁来的用户级数据，否则用系统级
if [[ -f "$HOME/.local/share/GeographicLib/geoids/egm96-5.pgm" ]]; then
  export GEOGRAPHICLIB_DATA="$HOME/.local/share/GeographicLib"
fi

# rosidl_pycommon 本地补齐（Humble 源里缺失）
if [[ -d "$SP27_ROOT/pylibs" ]]; then
  export PYTHONPATH="$SP27_ROOT/pylibs:${PYTHONPATH:-}"
fi

# Gazebo 资源搜索路径：SP27 模型/世界 + external_files 场地
if [[ -d "$SP27_GZ" ]]; then
  export GZ_SIM_RESOURCE_PATH="$SP27_GZ/models:$SP27_GZ/worlds:$SP27_WS/src/sp_filght_sim/external_files/worlds${GZ_SIM_RESOURCE_PATH:+:$GZ_SIM_RESOURCE_PATH}"
fi

# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash 2>/dev/null || {
  echo "[env.sh] 错误：找不到 /opt/ros/humble/setup.bash，先跑 bootstrap_ubuntu.sh" >&2
  return 1 2>/dev/null || exit 1
}
if [[ -f "$SP27_ROS_GZ_WS/install/setup.bash" ]]; then
  # shellcheck disable=SC1091
  source "$SP27_ROS_GZ_WS/install/setup.bash"
else
  echo "[env.sh] 警告：$SP27_ROS_GZ_WS/install/setup.bash 不存在（ros_gz 尚未构建）" >&2
fi
if [[ -f "$SP27_WS/install/setup.bash" ]]; then
  # shellcheck disable=SC1091
  source "$SP27_WS/install/setup.bash"
else
  echo "[env.sh] 警告：$SP27_WS/install/setup.bash 不存在（主工作区尚未 colcon build）" >&2
fi

# 可选：HEADLESS=1 由调用方决定；这里不覆盖

# NVIDIA RTX 4060 PRIME offload：GUI 走 GLX，headless 相机渲染走 EGL/Vulkan
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
if [[ -f /usr/share/glvnd/egl_vendor.d/10_nvidia.json ]]; then
  export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
fi
if [[ -f /usr/share/vulkan/icd.d/nvidia_icd.json ]]; then
  export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
fi
