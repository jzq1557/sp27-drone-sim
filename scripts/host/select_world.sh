#!/usr/bin/env bash
# 切换 SP27 世界的场地（在 SP27_FIELD_BEGIN/END 标记之间替换），
# 同时更新「源码世界」与「PX4 使用的世界副本」。
#
# 用法：
#   bash select_world.sh check       # 查看当前启用（默认）
#   bash select_world.sh newmap      # 新 RMUC2027 地图（默认）
#   bash select_world.sh newmap_fence # 新地图 + 四周围栏纹理（给 ORB 提供特征）
#   bash select_world.sh fence       # 旧围栏场地（8.25 cm 基线用）
#   bash select_world.sh rmuc2027    # 旧官方网格（96 MB，无贴图）
#   bash select_world.sh both        # 旧 RMUC2027 + 围栏（历史对照）
set -euo pipefail

SRC=/home/justin/TJ-Superpower/sp_nav_drone_27/src/sp_filght_sim
FILES=(
  "$SRC/sp27_gazebo_scene/worlds/sp_27_features.sdf"
  "$SRC/external_files/PX4-Autopilot/Tools/simulation/gz/worlds/sp_27_features.sdf"
  "$SRC/external_files/PX4-Autopilot/Tools/simulation/gz/worlds/default.sdf"
)
MODE="${1:-check}"

case "$MODE" in
  check|newmap|newmap_fence|fence|rmuc2027|both) ;;
  *) echo "用法: $0 [check|newmap|newmap_fence|fence|rmuc2027|both]" >&2; exit 2;;
esac

python3 - "$MODE" "${FILES[@]}" <<'PY'
import re, sys
from pathlib import Path

mode = sys.argv[1]
files = [Path(p) for p in sys.argv[2:]]
BEGIN, END = "<!-- SP27_FIELD_BEGIN -->", "<!-- SP27_FIELD_END -->"

def include(uri, pose=None):
    lines = ["<include>", f"  <uri>model://{uri}</uri>"]
    if pose:
        lines.append(f"  <pose>{pose}</pose>")
    lines.append("</include>")
    return "\n".join(lines)

PLAN = {
    "newmap":       [include("rmuc27_field")],
    "newmap_fence": [include("rmuc27_field"),
                     include("visual_feature_fence", "0 0 0 0 0 0")],
    "fence":     [include("visual_feature_fence", "0 0 0 0 0 0")],
    "rmuc2027":  [include("RMUC2027", "0 0 0 0 0 0")],
    "both":      [include("RMUC2027", "0 0 0 0 0 0"),
                  include("visual_feature_fence", "0 0 0 0 0 0")],
}

for path in files:
    if not path.is_file():
        print(f"[跳过] {path} 不存在")
        continue
    text = path.read_text(encoding="utf-8")
    if mode == "check":
        m = re.search(re.escape(BEGIN) + r"(.*?)" + re.escape(END), text, re.S)
        uris = re.findall(r"<uri>model://([^<]+)</uri>", m.group(1)) if m else []
        print(f"{path}\n  当前启用: {uris}")
        continue
    if BEGIN not in text or END not in text:
        print(f"[错误] {path} 缺少 SP27_FIELD 标记，未修改")
        continue
    block = "\n".join(PLAN[mode])
    new_text = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END),
                      BEGIN + "\n" + block + "\n" + END, text, flags=re.S)
    path.write_text(new_text, encoding="utf-8")
    print(f"[写入] {path.name} -> {mode}")
PY
