#!/usr/bin/env bash
# =============================================================================
# P1：从 WSL2 的 ext4.vhdx 里「只读」取出旧环境，迁到裸机 Ubuntu。
#
# 做的事：
#   1) 只读挂载 Windows 系统分区（默认 /dev/nvme0n1p3）
#   2) 在 Users/ 下找 ext4.vhdx（WSL 发行版磁盘）
#   3) 用 qemu-nbd -r（只读）挂载 vhdx，再只读挂载其 ext4 分区
#   4) rsync 出 ~/TJ-Superpower、~/.local/share/GeographicLib 与少量配置
#   5) 打印清点清单后卸载
#
# 安全承诺：全程 -o ro / qemu-nbd -r，绝不写 Windows 分区，绝不 remove_hiberfile。
#
# 用法：
#   sudo bash mount_wsl_ro.sh                        # 自动找 vhdx
#   sudo bash mount_wsl_ro.sh /dev/nvme0n1p3         # 指定 Windows 分区
#   sudo bash mount_wsl_ro.sh /dev/nvme0n1p3 /path/to/ext4.vhdx   # 指定 vhdx
#
# 失败时脚本会打印下一步该做什么（快速启动 / BitLocker / 找不到 vhdx）。
# =============================================================================
set -euo pipefail

WIN_DEV="${1:-/dev/nvme0n1p3}"
VHDX_ARG="${2:-}"
USER_NAME=justin
USER_HOME=/home/justin
WORK=/home/justin/works/SP_drone
ART="$WORK/artifacts/wsl_export"
WINMNT=/mnt/win_ro
WSLMNT=/mnt/wsl_ro
LOG="$ART/mount_wsl_ro.log"

MOUNTED_WIN=0
MOUNTED_WSL=0
NBD_ATTACHED=0

log()  { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[警告] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

cleanup() {
  set +e
  if (( MOUNTED_WSL )); then umount "$WSLMNT" 2>/dev/null; fi
  if (( NBD_ATTACHED )); then qemu-nbd -d /dev/nbd0 >/dev/null 2>&1; fi
  if (( MOUNTED_WIN )); then umount "$WINMNT" 2>/dev/null; fi
}
trap cleanup EXIT

[[ $EUID -eq 0 ]] || die "必须用 sudo 运行：sudo bash $0"
[[ -b $WIN_DEV ]] || die "$WIN_DEV 不是块设备。先跑 'lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT' 确认 Windows 分区（通常是最大的 NTFS）。"

mkdir -p "$ART"
exec > >(tee -a "$LOG") 2>&1

log "0. 环境"
echo "日期      : $(date -Is)"
echo "Windows 分区: $WIN_DEV"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$WIN_DEV" || true
echo "根分区可用: $(df -h /home | awk 'NR==2{print $4}')"

log "1. 只读挂载 Windows 分区"
mkdir -p "$WINMNT"
if mountpoint -q "$WINMNT"; then
  echo "已挂载，复用 $WINMNT"
else
  if mount -t ntfs3 -o ro "$WIN_DEV" "$WINMNT" 2>/tmp/ntfs3.err; then
    MOUNTED_WIN=1; echo "ntfs3 只读挂载成功"
  else
    warn "ntfs3 失败：$(cat /tmp/ntfs3.err)"
    command -v ntfs-3g >/dev/null 2>&1 || apt-get install -y ntfs-3g
    if mount -t ntfs-3g -o ro "$WIN_DEV" "$WINMNT" 2>/tmp/ntfs3g.err; then
      MOUNTED_WIN=1; echo "ntfs-3g 只读挂载成功"
    else
      warn "ntfs-3g 失败：$(cat /tmp/ntfs3g.err)"
      cat <<'EOF'

可能原因与下一步：
  A. Windows 快速启动/休眠 → 分区是「脏」的：
     重启进 Windows → 设置里关闭「快速启动」→ 完全关机（不是重启）→ 回到 Ubuntu 再跑本脚本。
  B. BitLocker 加密：
     无法离线读取；改在 Windows 里执行：
       wsl --export Ubuntu-22.04 E:\wsl-ubuntu.tar
     然后把 tar 拷到 Ubuntu，用 tar -xf 恢复（不需要本脚本）。
  C. 分区选错：
     lsblk -o NAME,SIZE,FSTYPE,LABEL 找到 NTFS 的系统盘，作为第 1 个参数重跑。
EOF
      die "无法只读挂载 $WIN_DEV"
    fi
  fi
fi

log "2. 查找 WSL 的 ext4.vhdx"
VHDX=""
if [[ -n $VHDX_ARG ]]; then
  VHDX=$VHDX_ARG
else
  mapfile -t CAND < <(find "$WINMNT/Users" -maxdepth 10 -iname '*.vhdx' 2>/dev/null | sort)
  if ((${#CAND[@]} == 0)); then
    cat <<EOF
[失败] 在 $WINMNT/Users 下没找到任何 *.vhdx。
请确认 WSL 发行版确实装在默认位置，或手动指定路径：
  sudo bash $0 $WIN_DEV /mnt/win_ro/<路径>/ext4.vhdx
也可以用 Windows 的 `wsl --list --verbose` 看发行版名字。
EOF
    die "找不到 vhdx"
  fi
  # 优先标准 Store 安装路径（.../Packages/CanonicalGroupLimited.../LocalState/ext4.vhdx）
  PREF=$(printf '%s\n' "${CAND[@]}" | grep -i 'CanonicalGroupLimited' | head -1 || true)
  if [[ -n ${PREF:-} ]]; then
    VHDX=$PREF
  elif ((${#CAND[@]} == 1)); then
    VHDX=${CAND[0]}
  else
    # 多个候选：取最大文件（文件名可能带空格，用 awk 去掉首列）
    VHDX=$(du -b "${CAND[@]}" 2>/dev/null | sort -n | tail -1 | awk '{$1=""; sub(/^ /,""); print}')
    echo "发现 ${#CAND[@]} 个 vhdx，取最大的一个："
    printf '  %s\n' "${CAND[@]}"
  fi
fi
[[ -f $VHDX ]] || die "vhdx 不存在：$VHDX"
echo "选中 vhdx: $VHDX"
du -h "$VHDX"
echo "校验（前 8 字节应为 'vhdxfile'）:"
head -c 8 "$VHDX" | od -c | head -1

log "3. 只读挂载 vhdx"
command -v qemu-nbd >/dev/null 2>&1 || { apt-get update -qq; apt-get install -y qemu-utils; }
modprobe nbd max_part=16
# 清理上次失败可能残留的 nbd 连接
if [[ -e /sys/block/nbd0/pid ]]; then
  warn "发现残留的 /dev/nbd0 连接，先断开"
  qemu-nbd -d /dev/nbd0 || true
fi
if [[ -e /dev/nbd0 ]] && qemu-nbd -r -c /dev/nbd0 --format=vhdx "$VHDX" 2>/tmp/qemu_nbd.err; then
  NBD_ATTACHED=1
else
  warn "qemu-nbd 失败：$(cat /tmp/qemu_nbd.err 2>/dev/null || echo '未知')"
  die "无法只读连接 vhdx"
fi
partprobe /dev/nbd0 2>/dev/null || true
sleep 1
lsblk -o NAME,SIZE,FSTYPE,LABEL /dev/nbd0 || true

PART=/dev/nbd0
if [[ -b /dev/nbd0p1 ]]; then PART=/dev/nbd0p1
elif [[ -b /dev/nbd0p2 ]]; then PART=/dev/nbd0p2; fi
mkdir -p "$WSLMNT"
mount -o ro "$PART" "$WSLMNT" || die "无法只读挂载 $PART（可能不是 ext4 或分区表异常）"
MOUNTED_WSL=1
echo "vhdx 分区 $PART 已只读挂载到 $WSLMNT"

log "4. 校验是目标 WSL 环境"
cat "$WSLMNT/etc/os-release" 2>/dev/null | head -2 || true
if [[ ! -d $WSLMNT/home/$USER_NAME ]]; then
  echo "--- $WSLMNT/home 内容 ---"; ls -la "$WSLMNT/home" || true
  die "没有找到 /home/$USER_NAME，可能用户名不同；请把脚本里的 USER_NAME 改成实际用户名后重跑"
fi
if [[ -d $WSLMNT/home/$USER_NAME/TJ-Superpower ]]; then
  echo "找到目标目录: /home/$USER_NAME/TJ-Superpower"
  du -sh "$WSLMNT/home/$USER_NAME/TJ-Superpower" 2>/dev/null || true
else
  warn "未找到 /home/$USER_NAME/TJ-Superpower"
  ls -la "$WSLMNT/home/$USER_NAME" | head -30 || true
  die "目标目录不存在；请把上面列表发我，我判断迁移什么"
fi

log "5. 拷贝（只读源，不会改 vhdx）"
mkdir -p /home/justin /home/justin/.local/share
rsync -a --numeric-ids --info=progress2 "$WSLMNT/home/$USER_NAME/TJ-Superpower/" /home/justin/TJ-Superpower/
chown -R "$USER_NAME:$USER_NAME" /home/justin/TJ-Superpower

for extra in .local/share/GeographicLib .bashrc .bash_history .config/fish .config/foot; do
  src="$WSLMNT/home/$USER_NAME/$extra"
  [[ -e $src ]] || continue
  case $extra in
    .local/share/GeographicLib)
      mkdir -p /home/justin/.local/share/GeographicLib
      rsync -a --numeric-ids "$src/" /home/justin/.local/share/GeographicLib/ ;;
    .bashrc|.bash_history)
      cp -a "$src" "$ART/wsl_$(basename "$extra")" ;;
    *)
      mkdir -p "$ART/wsl_config_$(basename "$extra")"
      rsync -a --numeric-ids "$src/" "$ART/wsl_config_$(basename "$extra")/" ;;
  esac
done
cp -a "$WSLMNT/etc/os-release" "$ART/wsl_os-release" 2>/dev/null || true
chown -R "$USER_NAME:$USER_NAME" /home/justin/.local/share "$ART" 2>/dev/null || true

log "6. 清点清单"
WS=/home/justin/TJ-Superpower
{
  echo "源环境: $(head -1 "$ART/wsl_os-release" 2>/dev/null || echo '?')"
  for d in sp_nav_drone_27 ros_gz_ws pylibs px4-download deploy; do
    [[ -e $WS/$d ]] && printf '%-18s %s\n' "$d" "$(du -sh "$WS/$d" 2>/dev/null | cut -f1)" || printf '%-18s %s\n' "$d" "缺失"
  done
  echo "--- PX4 ---"
  PX4=$WS/sp_nav_drone_27/src/sp_filght_sim/external_files/PX4-Autopilot
  if [[ -d $PX4 ]]; then
    [[ -f $PX4/.git/HEAD ]] && echo ".git/HEAD: $(cat "$PX4/.git/HEAD")"
    [[ -d $PX4/build/px4_sitl_default ]] && echo "build/px4_sitl_default: $(du -sh "$PX4/build/px4_sitl_default" | cut -f1)"
    [[ -f $PX4/build/px4_sitl_default/bin/px4 ]] && file "$PX4/build/px4_sitl_default/bin/px4"
  else echo "PX4 缺失"; fi
  echo "--- ORB 词袋 ---"
  find "$WS/sp_nav_drone_27/src/sp_localization/ORB_SLAM3/Vocabulary" -maxdepth 1 -type f -exec ls -lh {} \; 2>/dev/null | head
  echo "--- ros_gz_ws ---"
  ls "$WS/ros_gz_ws/install/setup.bash" 2>/dev/null || echo "install 缺失"
  echo "--- GeographicLib ---"
  ls -lh /home/justin/.local/share/GeographicLib/geoids 2>/dev/null || echo "geoid 未迁移"
} 2>&1 | tee "$ART/inventory.txt"

log "7. 卸载"
# trap 会统一清理

log "完成"
echo "清单已保存: $ART/inventory.txt"
echo "完整日志:   $LOG"
echo "下一步：把 inventory.txt 内容发我，或在会话里说「迁移完成」，我核对后进入 P2。"
