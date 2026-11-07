#!/usr/bin/env bash
# P3：把 PX4 放到位、打两个补丁、导出 SP27 仿真资源。
# 幂等：重复执行安全（已应用的补丁会跳过）。
set -o pipefail

WS=/home/justin/TJ-Superpower/sp_nav_drone_27
OVERLAY=$WS/src/sp_filght_sim/sp27_px4_overlay
PX4=$WS/src/sp_filght_sim/external_files/PX4-Autopilot
SRC=/home/justin/TJ-Superpower/px4-download/PX4-Autopilot

say() { echo; echo "=============== $* ==============="; }

say "1. 把 PX4 放到仓库期望的位置"
if [[ -d $PX4/.git ]]; then
  echo "已就位：$PX4（$(git -C "$PX4" rev-parse --short HEAD)）"
elif [[ -d $SRC/.git ]]; then
  mkdir -p "$(dirname "$PX4")"
  mv "$SRC" "$PX4"
  echo "已移动：$SRC -> $PX4"
else
  echo "[错误] 找不到 PX4 源码（$SRC 或 $PX4）"; exit 1
fi

cd "$PX4" || exit 1
BASE=$(git rev-parse HEAD)
echo "PX4 HEAD = $BASE"
if [[ $BASE != 54f0455ffcd755534539a7cf33a09a20bf71d29d ]]; then
  echo "[警告] PX4 不是文档基线 54f0455，补丁可能打不上"
fi

say "2. 应用 px4.patch"
if git apply --check "$OVERLAY/px4.patch" 2>/dev/null; then
  git apply "$OVERLAY/px4.patch" && echo "px4.patch 已应用"
elif git apply --check -R "$OVERLAY/px4.patch" 2>/dev/null; then
  echo "px4.patch 已应用过，跳过"
else
  echo "[错误] px4.patch 打不上，需要人工看"; git apply --check "$OVERLAY/px4.patch"; exit 1
fi

say "3. 应用 gazebo.patch（仅当上游 gz 模型库存在时）"
GZ=$PX4/Tools/simulation/gz
cd "$GZ" || { echo "[错误] 缺少 $GZ"; exit 1; }
if [[ -f $GZ/models/x500_depth/model.sdf ]]; then
  echo "gz 子模块 HEAD = $(git -C "$GZ" rev-parse --short HEAD)"
  if git apply --check "$OVERLAY/gazebo.patch" 2>/dev/null; then
    git apply "$OVERLAY/gazebo.patch" && echo "gazebo.patch 已应用"
  elif git apply --check -R "$OVERLAY/gazebo.patch" 2>/dev/null; then
    echo "gazebo.patch 已应用过，跳过"
  else
    echo "[警告] gazebo.patch 打不上（上游模型版本不同），继续"
  fi
else
  echo "[跳过] 上游 PX4-gazebo-models 未克隆，改用最小资源目录。"
  echo "       gazebo.patch 只修改 models/x500_depth（旧对比机型），对 sp27_uav 无影响。"
  echo "       若以后要跑 x500 对照实验，再补：git -C $PX4 submodule update --init Tools/simulation/gz"
fi

say "4. 导出 SP27 模型 / 世界 / 机型"
cd "$WS" || exit 1
python3 "$OVERLAY/export_assets.py" --check || true
python3 "$OVERLAY/export_assets.py" --apply
echo "--- 复核 ---"
python3 "$OVERLAY/export_assets.py" --check && echo "导出后已无差异"

say "5. 路径可移植性检查（仓库自带）"
python3 bash/check_portable_paths.py || echo "[警告] 路径检查返回非零，见上"

say "6. 结果"
echo "airframe: $(ls -l "$PX4/ROMFS/px4fmu_common/init.d-posix/airframes/4022_gz_sp27_uav" 2>/dev/null | wc -l) 个文件"
echo "world:    $(ls -l "$GZ/worlds/sp_27_features.sdf" 2>/dev/null | wc -l) 个文件"
echo "models:   $(ls "$GZ/models" 2>/dev/null | grep -c sp27) 个 sp27 模型"
echo "完成。"
