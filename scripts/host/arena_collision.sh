#!/usr/bin/env bash
# 切换 RMUC2027 场地网格的碰撞体（只读视觉 vs 实体碰撞）。
#
# 背景（2026-11-07 离线复盘发现）：
#   RMUC2027/model.sdf 末尾把整个 96 MB 网格注册成一个 <collision>，
#   而围栏场地只有 4 面墙的碰撞。结果是：
#     - 无人机出生点 (-1.03,-1.03,1.95) 落在场地网格的某个结构上，静止高度 1.84 m；
#     - PX4 以 1.84 m 为局部原点，航线上"上升 1 m"就飞到 3.0 m，
#       正好贴着 3.28 m 高的场地墙顶，视觉特征变差 → 水平尺度漂移 → 44.8 cm；
#     - 96 MB 三角网格参与物理，还会拖慢 gz 实时率。
#
# 用法：
#   bash arena_collision.sh check   # 看当前状态（默认）
#   bash arena_collision.sh off     # 注释掉场地碰撞（推荐：只做视觉场景）
#   bash arena_collision.sh on      # 恢复原状（从 .orig 还原）
set -euo pipefail

SDF=/home/justin/TJ-Superpower/sp_nav_drone_27/src/sp_filght_sim/external_files/worlds/RMUC2027/model.sdf
MODE="${1:-check}"

case "$MODE" in check|off|on) ;; *) echo "用法: $0 [check|off|on]" >&2; exit 2;; esac
[[ -f $SDF ]] || { echo "[错误] 找不到 $SDF" >&2; exit 1; }
ORIG="$SDF.orig"
[[ -f $ORIG ]] || cp -a "$SDF" "$ORIG"

python3 - "$MODE" "$SDF" "$ORIG" <<'PY'
import re, sys
from pathlib import Path

mode, sdf, orig = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
text = orig.read_text(encoding="utf-8")

m = re.search(r'(?P<indent>[ \t]*)<collision name="collision">.*?</collision>\n', text, re.S)
if not m:
    print("[错误] 在 .orig 中找不到 <collision name=\"collision\"> 块")
    sys.exit(1)
block = m.group(0)

if mode == "check":
    cur = sdf.read_text(encoding="utf-8")
    disabled = "<!-- arena_collision: disabled" in cur
    print(f"当前: {'已禁用碰撞（纯视觉）' if disabled else '碰撞启用（原始状态）'}")
    sys.exit(0)

if mode == "off":
    out = text[:m.start()] + \
        f'{m.group("indent")}<!-- arena_collision: disabled (纯视觉场地；原始碰撞块见 model.sdf.orig)\n' + \
        block + f'{m.group("indent")}-->\n' + text[m.end():]
    sdf.write_text(out, encoding="utf-8")
    print("[写入] 已注释 RMUC2027 全场碰撞，场地变为纯视觉")
else:
    sdf.write_text(text, encoding="utf-8")
    print("[写入] 已从 .orig 还原 RMUC2027 碰撞")
PY
