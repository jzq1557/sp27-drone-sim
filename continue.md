# continue.md —— 工作交接书

> **给双系统 Ubuntu 上的新会话（零上下文冷启动）**
> 读完本文，你应该能立刻知道：这是什么、做到哪了、卡在哪、下一步干什么、怎么验证。
>
> 撰写时间：2026-11-07
> 撰写环境：Windows 11 + WSL2（旧环境）
> 目标环境：**Ubuntu 裸机（双系统），不再用 WSL**
> 配套仓库：<https://github.com/jzq1557/sp27-drone-sim>

---

## 0. 三十秒速览

| 项 | 内容 |
|---|---|
| **项目** | 把同济 SuperPower 战队 `sp_nav_drone_27`（视觉导航无人机）的仿真验证跑起来，并接入官方 RMUC2027 比赛场地 |
| **已完成** | 环境从零搭通 → 12 项验收全绿 → 起飞/悬停/降落跑通 → 精度 RMSE **8.3 cm**（围栏场地） |
| **已卡住** | 接入**真实 RMUC2027 场地**后精度恶化到 RMSE **44.8 cm**，飞高 3.12 m，PX4 退出 OFFBOARD，位置估计发散到 154 m |
| **下一步** | 定位"真实场地下的 ORB 丢跟踪/尺度漂移"（排查计划见 §5，命令可直接抄） |
| **为什么换 Ubuntu** | 主 Windows 只有 15.7 GB 内存，WSL 配额与 Windows 争抢导致反复卡死；裸机后 15.7 GB 全归 Linux |

---

## 1. 项目是什么

### 1.1 被验证的对象

`TongjiSuperPower/sp_nav_drone_27` —— 同济 SuperPower 战队的 SP27 视觉导航方案（**私有仓库**）。

- 分支：`dev_wwa_air`
- 稀疏克隆时的 HEAD：`2802230`（完整历史见仓库）
- 结构：ROS 2 工作区，含 ORB-SLAM3 / VINS-Fusion / PX4 overlay / Gazebo 场景 / 控制与决策包

### 1.2 系统架构（数据流）

```
Gazebo 双目 + IMU + 真值
   │  ros_gz_bridge / parameter_bridge
   ▼
ROS 2 话题（/tidesense/left|right/image_raw、/sp27/imu、/model/sp27_uav_0/odometry…）
   │
   ├─► ORB-SLAM3（stereo-inertial）  ──/orbslam3/raw_odom──►
   │        vio_bridge（滤波 + 坐标变换 + 协方差）
   │            │ /mavros/vision_pose/pose_cov
   │            ▼
   │        MAVROS ──MAVLink──► PX4 EKF2
   │            │ /mavros/local_position/pose
   │            ▼
   └────► offboard_controller（状态机）──/mavros/setpoint_position/local──► PX4 ──► Gazebo 电机
```

### 1.3 里程碑定义（当初约定）

- **里程碑 A（已完成）**：能看见飞机、能起飞、ORB 输出位姿
- **里程碑 B（未开始）**：完整固定航线（上升 1 m → 前飞 5 m → 右转 360° → 返航）+ 误差报告
- **里程碑 C（未开始）**：实机（标定、hardware profile、PX4 融合参数）

---

## 2. 当前状态

### 2.1 已完成 ✅

- [x] 论文精读（NMI 2025，可微物理敏捷飞行）——见仓库 `docs/04`
- [x] 完整仿真栈在 WSL2 上从零搭通
- [x] `verify_a.sh` **12/12 PASS**
- [x] 起飞（1.003 m）→ 悬停（mm 级漂移）→ 降落（AUTO.LAND + 上锁）全流程
- [x] 精度：**位置 RMSE 8.3 cm / 中位 6.1 cm / p95 16.5 cm**，姿态中位 0.55°（944 帧对比真值）
- [x] 官方 RMUC2027 场地资产已拿到并**成功安装、成功加载**（世界无报错）
- [x] 内存瓶颈定量定位（WSL 配额 vs Windows 占用）
- [x] 无 GUI（headless）模式验证通过
- [x] 场地资产溯源（确认原仓库无 mesh、找到官方 CAD 名与公开替代品）
- [x] Isaac / UE / Unity / 双系统 选型分析（结论：裸机 Linux）

### 2.2 未完成 / 卡住 ⏳

| # | 问题 | 严重度 |
|---|---|---|
| 1 | **真实 RMUC2027 场地下 ORB/EKF 发散**（RMSE 44.8 cm，飞高 3.12 m，PX4 退出 OFFBOARD，位置估计到 154 m） | 阻塞 B 阶段 |
| 2 | 内置航线在旋转段反复 `Turn paused: position error 0.2x m`（阈值 `turn_position_limit_m: 0.25`） | 阻塞 B 阶段 |
| 3 | 完整固定航线未端到端验证 | 里程碑 B |
| 4 | 实机完全未涉及 | 里程碑 C |

---

## 3. 已确认的技术事实（别重新摸索）

### 3.1 版本矩阵（Windows/WSL 上验证通过的组合）

| 组件 | 版本 | 备注 |
|---|---|---|
| Ubuntu | 22.04 | ROS 2 Humble 必需 |
| ROS 2 | **Humble** | |
| Gazebo | **Harmonic，gz-sim 8.15.0** | `gz-harmonic 1.0.0` |
| PX4 | **v1.16.2，commit `54f0455ffcd755534539a7cf33a09a20bf71d29d`** | 必须精确对齐，否则补丁打不上 |
| px4 gz 资源子模块 | `e05f4312d3f28aa621157610584a4870406cb6d3` | `Tools/simulation/gz` |
| MAVROS | 2.16.0 | apt 安装 |
| **ros_gz** | **1.0.25（源码编译）** | ⚠️ apt 版是 Fortress，不可用，见 §4.1 |
| ORB-SLAM3 | 仓库内置 | |
| Pangolin | **v0.6** | ⚠️ v0.8 布局不同，见 §4.4 |
| GeographicLib geoid | `egm96-5` | MAVROS 必需 |

### 3.2 编译的 ROS 包（共 6 个）

```bash
colcon build --symlink-install --packages-select \
  sp_robot_msg sp_communicator sp_nav_bringup \
  orbslam3_ros vio_bridge offboard_controller \
  --cmake-args -DCMAKE_BUILD_TYPE=Release
```

> 注意：`sp_nav_bringup` 的 `exec_depend` 里有 `sp_communicator`，必须先编译它，否则 colcon 报 `Failed to find ... package.sh`。

### 3.3 关键路径（旧 WSL 环境，Ubuntu 上按同样结构重建即可）

```
~/TJ-Superpower/
├── sp_nav_drone_27/                    # 主工作区（稀疏克隆，约 181 MB）
│   └── src/sp_filght_sim/external_files/
│       ├── PX4-Autopilot/              # gitignore，需自行拉取 v1.16.2
│       └── worlds/RMUC2027/meshes/model.dae   # 96 MB，见 §7
├── ros_gz_ws/                          # Harmonic 版 ros_gz（覆盖 apt）
│   └── gz_aliases/                     # gz-transport / gz-msgs 的 CMake 别名
├── pylibs/rosidl_pycommon/             # Humble 源里缺失的构建期模块
└── deploy/                             # 本次交付的脚本（= 仓库 scripts/）
```

---

## 4. 必须知道的坑（浓缩版，详见仓库 `docs/01-会话纪要.md`）

### 4.1 ⚠️ ros_gz 必须用 Harmonic 版（最容易浪费一天）

**现象**：桥接进程正常、`ros2 topic list` 能看到话题，但**ROS 侧一条数据都收不到**，日志刷 `Unknown message type [8]/[9]`。

**根因**：apt 的 `ros-humble-ros-gz-bridge 0.244.26` 依赖 `libignition-transport11` / `libignition-msgs8`（**Fortress**），PX4 v1.16 用 **Harmonic**（`gz-transport13` / `gz-msgs10`）。

**解法**：源码编译 `ros_gz 1.0.25` 到独立工作区，启动时**先 source 它**。配套 4 处适配：
1. `gz_aliases/`：提供 `gz-transport` / `gz-msgs` 的 CMake 别名（系统只有带版本号的 `gz-transport13` / `gz-msgs10`）；
2. 删掉 `marine_acoustic_msgs`（未安装）的 mappings / convert 源与头；
3. `yaml-cpp::yaml-cpp` → `yaml-cpp`；
4. `rclcpp::BestAvailableQoS()` → `rclcpp::QoS(rclcpp::KeepLast(10)).best_effort()`（Humble 无此 API）。

> **验证方法**：`ros2 topic hz /sp27/imu` 有数才算通；只有 `ros2 topic list` 里出现不算。

### 4.2 ⚠️ ORB 同步队列必须调小（最隐蔽）

**现象**：ORB 里程计 15 Hz、跟踪状态 OK，但 `/mavros/vision_pose/pose_cov` **一条都没有** → PX4 不解锁（`Arming denied: Resolve system health failures first`）。

**根因**：`sp27_flight.launch.py` 里 `sync_queue_size: 30`，15 Hz 下 = 缓存 2 秒画面，ORB 输出**固定落后仿真时钟 0.75 s**；而 `vio_bridge` 的陈旧阈值是 **0.3 s** → 每帧被 `return std::nullopt` **静默丢弃**（几乎无警告）。

**解法**：`sync_queue_size` **30 → 3**。延迟 752 ms → **50 ms**。

> **已改**：仓库里这个文件仍是原值，克隆后需自行修改（或从本仓库 `scripts/` 找不到，属于源码改动，见 §6.5）。

### 4.3 仓库自身缺 4 个文件

`ORB_SLAM3/CMakeLists.txt` 引用了但**从未提交**：

```
Thirdparty/DBoW2/DUtils/Timestamp.{h,cpp}
Thirdparty/g2o/g2o/stuff/timeutil.{h,cpp}
```

→ 从上游 `UZ-SLAMLab/ORB_SLAM3` 取同版本补齐，否则 `No SOURCES given to target`。

### 4.4 Pangolin 必须 v0.6

`orbslam3_ros` 的 CMake 硬编码找 `Pangolin/build/src/libpangolin`，这是 **v0.6 的布局**；v0.8 改成了 `components/`。

且 `orbslam3_ros` 不自动加 Pangolin 头文件路径，需：

```bash
export CPLUS_INCLUDE_PATH="$PANGOLIN/include:$PANGOLIN/build/src/include:$CPLUS_INCLUDE_PATH"
# 注意 build/src/include 里有构建时生成的 config.h
```

### 4.5 PX4 的三处本地适配（因为编译期要联网）

1. `boards/px4/sitl/default.px4board`：`CONFIG_MODULES_UXRCE_DDS_CLIENT=n`（用 MAVLink，不需要 uXRCE-DDS）
2. `src/modules/simulation/gz_plugins/CMakeLists.txt`：注释 `add_subdirectory(optical_flow)`，并从 `px4_gz_plugins` 依赖里移除 `OpticalFlowSystem`
3. **新建 `Tools/simulation/gz/worlds/default.sdf`**：PX4 从 `worlds/*.sdf` 生成 `gz_<机型>_<世界>` 目标，缺它就没有 `gz_sp27_uav`（launch 报 `unknown target`）

> 在能正常访问 GitHub 的 Ubuntu 上，这三处**可以不改**（让 PX4 自己拉 ExternalProject）。但如果你也遇到网络问题，照上面改。

### 4.6 其他小坑

| 坑 | 解法 |
|---|---|
| GPS 子模块拉不下来 | tarball 解压到 `src/drivers/gps/devices`，放 `.git` 占位；全程 `export GIT_SUBMODULES_ARE_EVIL=1` |
| MAVROS 启动即崩，报 geoid 缺失 | 下载 `egm96-5.tar.bz2` 解压到 `~/.local/share/GeographicLib/`，`export GEOGRAPHICLIB_DATA=$HOME/.local/share/GeographicLib`（**免 sudo**） |
| `rosidl_pycommon` 在 Humble apt 里没有 | `apt-get download ros-iron-rosidl-pycommon`（不需要 root）→ `dpkg -x` → 放进 `PYTHONPATH` |
| ORB 示例程序拖垮构建 | `CMakeLists.txt` 加 `option(SP27_ORB_BUILD_EXAMPLES "" OFF)`，里程碑 A 只需要 `libORB_SLAM3.so` |
| 稀疏克隆后 `git status` 卡死 | blobless 仓读文件会触发懒加载网络请求，别在仓库里跑遍历脚本 |

### 4.7 ⚠️ 操作纪律（这条吃过亏）

**不要在单次工具调用里放长时间 `sleep`**。WSL 环境下，命令超时被中断时 `wsl.exe` 的进程树会被一起清理，仿真会停在半启动状态（服务器活着但 `/clock` 不步进、GUI 全黑），极难排查。

正确做法：
```bash
setsid nohup bash deploy/run_sim_headless.sh > /tmp/sim.log 2>&1 < /dev/null &
disown
```
然后用**短命令**（≤20 秒）轮询状态。

> Ubuntu 裸机上这个问题会缓解（没有 wsl.exe 进程树），但"长时间操作要脱管"仍是好习惯。

---

## 5. 下一步：定位真实场地下的精度恶化（**核心任务**）

### 5.1 现象回顾

| 指标 | 围栏世界（`visual_feature_fence`） | 真实场地（`RMUC2027`） |
|---|---|---|
| 3D 位置 RMSE | **8.3 cm** | **44.8 cm** |
| 位置误差中位 | 6.1 cm | 32.5 cm |
| 姿态误差中位 | 0.55° | 3.29° |
| 真值高度 | 稳定 1.00 m | **一度 3.12 m**（94% 时间 >1.5 m） |
| 失败表现 | 正常 | 旋转段反复暂停 → **PX4 退出 OFFBOARD** → 位置估计发散到 (−154, 126) m |

### 5.2 排查计划（按顺序做，每步都有明确判据）

#### 步骤 1：确认 ORB 是否丢跟踪

```bash
python3 - <<'PY'
import csv, collections
from pathlib import Path
root = Path.home() / "TJ-Superpower/sp_nav_drone_27/log/orbslam3_flights"
d = max(root.glob("flight_*"), key=lambda p: p.stat().st_mtime)
tr = list(csv.DictReader(open(d / "tracking.csv")))
cnt = collections.Counter(r["tracking_state"] for r in tr)
total = len(tr)
print("会话:", d.name, "总帧:", total)
print("状态分布:", dict(cnt))
print(f"OK(2) 占比: {cnt.get('2',0)/total*100:.1f}%")
PY
```

**判据**：`tracking_state` 语义为 ORB-SLAM3 的 `eTrackingState`：`2 = OK`，`3 = RECENTLY_LOST`，`4 = LOST`。
若 OK 占比 < 90% → 确认丢跟踪，往"特征不足/纹理重复"方向查。

#### 步骤 2：测 ORB 输出延迟（关键）

```bash
# 保存为 /tmp/lag_probe.py
cat > /tmp/lag_probe.py <<'PY'
import rclpy
from rclpy.node import Node
from nav_msgs.msg import Odometry

class Probe(Node):
    def __init__(self):
        super().__init__('lag_probe')
        self.create_subscription(Odometry, '/orbslam3/raw_odom', self.cb, 10)
        self.n = 0
    def cb(self, msg):
        now = self.get_clock().now().nanoseconds * 1e-9
        st = msg.header.stamp.sec + msg.header.stamp.nanosec * 1e-9
        self.n += 1
        if self.n <= 8:
            print(f"frame {self.n}: now={now:.3f} stamp={st:.3f} lag={now-st:+.3f}s")
        if self.n == 8:
            raise SystemExit(0)

rclpy.init(); node = Probe()
try: rclpy.spin(node)
except SystemExit: pass
finally: node.destroy_node(); rclpy.shutdown()
PY

python3 /tmp/lag_probe.py --ros-args -p use_sim_time:=true
```

**判据**：`lag` 必须 **< 0.3 s**（`vio_bridge` 的陈旧阈值）。
若 > 0.3 s → 说明 ORB 在新场地里处理变慢、队列积压，先解决延迟（见步骤 3），别急着改算法。

#### 步骤 3：若延迟超限，先降 ORB 负载

`src/sp_localization/orbslam3_ros/config/stereo_inertial/sp27_gazebo.yaml`：

```yaml
ORBextractor.nFeatures: 1200     # 试着降到 800
ORBextractor.iniThFAST: 20       # 试着放宽到 25
```

同时确认 `sp27_flight.launch.py` 里 `sync_queue_size: 3`（见 §4.2）。

#### 步骤 4：看相机画面质量（特征是否够）

在仿真运行时抓一帧存 PNG：

```bash
cat > /tmp/grab.py <<'PY'
import rclpy, numpy as np, cv2
from rclpy.node import Node
from sensor_msgs.msg import Image

class Grab(Node):
    def __init__(self):
        super().__init__('grab_left')
        self.create_subscription(Image, '/tidesense/left/image_raw', self.cb, 10)
    def cb(self, m):
        h, w = m.height, m.width
        if m.encoding in ('mono8','8UC1'):
            img = np.frombuffer(m.data, dtype=np.uint8).reshape(h, w)
        elif m.encoding == 'rgb8':
            img = np.frombuffer(m.data, dtype=np.uint8).reshape(h, w, 3)[:, :, ::-1]
        else:
            img = np.frombuffer(m.data, dtype=np.uint8).reshape(h, w, 3)
        cv2.imwrite('/tmp/left_frame.png', img)
        print(f"saved {w}x{h} {m.encoding}")
        raise SystemExit(0)

rclpy.init(); n = Grab()
try: rclpy.spin(n)
except SystemExit: pass
finally: n.destroy_node(); rclpy.shutdown()
PY

python3 /tmp/grab.py --ros-args -p use_sim_time:=true
```

**判据**：若画面大面积纯色/过暗/纹理重复 → 特征不足，需换场地或加纹理。参考仓库 `screenshots/03_左目相机首帧_640x400.png`（围栏场地，画面偏暗但可见结构）。

#### 步骤 5：对比 A/B —— 换回围栏场地做对照

把世界改回只用 `visual_feature_fence`（仓库里有现成的两版世界，见 §7.3），重跑同样航线。
**若围栏场地回到 8 cm、真实场地 45 cm，则问题确定在场地/特征层面**，而不是控制或 EKF 参数。

#### 步骤 6（可选）：放宽 `vio_bridge` 的陈旧阈值做实验

`src/sp_localization/vio_bridge/src/orb_odometry_processor.hpp` 里的 `now-stamp > 0.3`。**仅作为验证假设的手段**，不要当作最终方案。

### 5.3 已知的安全恢复手段

仿真中若 PX4 退出 OFFBOARD（模式变 `STABILIZED`/`POSCTL`），用 MAVROS 强制降落：

```bash
ros2 service call /mavros/set_mode mavros_msgs/srv/SetMode "{base_mode: 0, custom_mode: 'AUTO.LAND'}"
```

控制器的命令全集（`/offboard/command`，`std_msgs/String`）：

```
start_builtin   内置信标航线（上升1m → 前飞5m → 右转360° → 返航）
start_external  执行外部路径（/planner/trajectory）
hold            原地悬停
land            降落
stop            中止（不自动重入）
remote          请求遥控接管
release_rc      释放遥控
```

---

## 6. 在 Ubuntu 裸机上重建环境（环境那边再搞，这里是清单）

> 用户已说明：具体配置在 Ubuntu 上再搞。以下是**必须注意的差异点**，不要照搬 WSL 的东西。

### 6.1 不需要迁移的东西（WSL 专属）

| WSL 的东西 | Ubuntu 上怎么办 |
|---|---|
| `C:\Users\Justin\.wslconfig`（memory=6656MB 等） | **删掉概念**，裸机直接有 15.7 GB |
| `vmmemWSL` 内存争抢 | 不存在，问题消失 |
| WSLg / 远程桌面下 Gazebo 黑屏 | 不存在，原生 GPU 渲染 |
| `/mnt/e` 跨文件系统 | 用真实的 `/home/<user>/` |
| `HEADLESS=1` 为了省内存 | 仍可用，但不再是必须 |

### 6.2 必须重建的步骤

```bash
# 1) 系统依赖（需要 sudo）
sudo bash scripts/bootstrap_root.sh
#    它会装：build-essential / cmake / OpenCV / Eigen / GLEW / gz-harmonic /
#            ros_gz / mavros / GeographicLib 等
#    ⚠️ 若网络正常，OSRF 源与 ros_gz 都走 apt 即可；
#       但注意 ros_gz 的 apt 版本是 Fortress，仍需源码编译 Harmonic 版（§4.1）

# 2) 代码落地
#    私有仓库需要 token（向用户索取，或用 gh auth login）
git clone --filter=blob:none --no-checkout --depth 1 -b dev_wwa_air <repo> sp_nav_drone_27
cd sp_nav_drone_27
git sparse-checkout init --no-cone
# 只勾这些目录（写进 .git/info/sparse-checkout）：
#   /src/sp_nav_bringup/ /src/sp_localization/orbslam3_ros/
#   /src/sp_localization/vio_bridge/ /src/sp_localization/ORB_SLAM3/{src,include,Thirdparty,Vocabulary}/
#   /src/sp_control/ /src/sp_robot_msg/ /src/sp_filght_sim/ /src/sp_communicator/ /bash/
git checkout -f dev_wwa_air

# 3) PX4 v1.16.2（放到仓库期望的路径）
git clone --depth 1 -b v1.16.2 <PX4> \
  src/sp_filght_sim/external_files/PX4-Autopilot
#   Ubuntu 上网络正常的话，让 PX4 自己拉子模块即可

# 4) 补丁 + 资源导出
bash scripts/patch_px4.sh
#   注意：gazebo.patch 只改 x500_depth（旧对比机型），可跳过

# 5) 构建
bash scripts/build.sh
#   Pangolin v0.6 → ORB_SLAM3（需先补 §4.3 的 4 个文件）→ colcon

# 6) ros_gz 1.0.25 源码编译（§4.1）
#    然后确保启动脚本里「先 source ros_gz_ws，再 source 主工作区」

# 7) 启动
setsid nohup bash scripts/run_sim_headless.sh > /tmp/sim.log 2>&1 &
bash scripts/verify_a.sh     # 期望 12/12 PASS
```

### 6.3 环境变量清单（启动脚本必须包含）

```bash
export GIT_SUBMODULES_ARE_EVIL=1                      # PX4 跳过子模块联网检查
export GEOGRAPHICLIB_DATA=$HOME/.local/share/GeographicLib   # MAVROS geoid
export PYTHONPATH=$HOME/TJ-Superpower/pylibs:$PYTHONPATH     # rosidl_pycommon
export PATH=$HOME/.local/bin:$PATH                    # PX4 的 python 脚本
export GZ_SIM_RESOURCE_PATH="<PX4>/Tools/simulation/gz/models:<PX4>/Tools/simulation/gz/worlds:<repo>/src/sp_filght_sim/external_files/worlds"

source /opt/ros/humble/setup.bash
source $HOME/TJ-Superpower/ros_gz_ws/install/setup.bash   # ⚠️ 必须在主工作区之前
source $HOME/TJ-Superpower/sp_nav_drone_27/install/setup.bash
```

### 6.4 显卡

RTX 4060 Laptop 8 GB：Ubuntu 上装 NVIDIA 官方驱动即可，`nvidia-smi` 能出结果就行。
Gazebo Harmonic 会走 OpenGL/Ogre2，原生比 WSLg 稳得多。

### 6.5 仓库里仍需手动改的源码（本仓库不含源码，故要自己动手）

| 文件 | 改什么 |
|---|---|
| `src/sp_nav_bringup/launch/sp27_flight.launch.py` | `'sync_queue_size': 30` → **3**（§4.2，关键） |
| `src/sp_localization/ORB_SLAM3/CMakeLists.txt` | 加 `option(SP27_ORB_BUILD_EXAMPLES "" OFF)` 包住 examples 段 |
| `src/sp_localization/ORB_SLAM3/Thirdparty/DBoW2/DUtils/` | 补 `Timestamp.{h,cpp}` |
| `src/sp_localization/ORB_SLAM3/Thirdparty/g2o/g2o/stuff/` | 补 `timeutil.{h,cpp}` |
| `src/sp_filght_sim/sp27_gazebo_scene/worlds/sp_27_features.sdf` | 决定用哪个场地（见 §7.3） |

---

## 7. 文件与资源清单

### 7.1 本仓库（<https://github.com/jzq1557/sp27-drone-sim>）

| 路径 | 内容 |
|---|---|
| `docs/01-会话纪要.md` | ⭐ 全过程技术纪要：12 个坑的完整版（现象/根因/解法/命令） |
| `docs/02-部署笔记.md` | 环境版本、改动清单、复现步骤 |
| `docs/03-选型分析-是否脱离WSL.md` | Isaac/UE/Unity/双系统 对比（含官方要求原文引用） |
| `docs/04-论文速读-NMI敏捷飞行.md` | 被验证方法的原论文速览 |
| `scripts/bootstrap_root.sh` | 系统依赖（sudo） |
| `scripts/patch_px4.sh` | PX4 补丁 + 资源导出 |
| `scripts/build.sh` | Pangolin → ORB_SLAM3 → colcon |
| `scripts/run_sim.sh` | 启动（带 GUI） |
| `scripts/run_sim_headless.sh` | 启动（无 GUI，省内存） |
| `scripts/verify_a.sh` | 12 项自动验收 |
| `scripts/certs/` | 校园网 SSL 审计根证书（**Ubuntu 校园网可能仍需要**） |
| `screenshots/` | Gazebo 机体、地面状态、左目相机首帧 |
| `data/flight-logs/flight_20261107_024044_n5x7wu47/` | 一次完整飞行的逐帧 ORB vs 真值数据（844 有效帧） |

### 7.2 ⚠️ 不在仓库里、需要从 Windows 侧拷过来的资产

| 文件 | 位置 | 大小 | 说明 |
|---|---|---|---|
| `meshes.zip` | `E:\工程文档\rm\SP_drone_sim\meshes.zip` | 23 MB | 解压出 `meshes/model.dae`（**96 MB，130 个具名子网格 ID3/ID6/…**） |
| `RMUC2027_4.dae` | `E:\工程文档\rm\SP_drone_sim\RMUC2027_4.dae` | 46.5 MB | 另一个变体（与本仓库 SDF 的子网格名**不匹配**，暂不需要） |
| 部署归档 | `E:\工程文档\rm\SP_drone_sim\` | 3.8 MB | 笔记/脚本/截图/日志（已全部进本仓库） |
| 论文 PDF | `E:\工程文档\rm\论文阅读\` | 6 MB | 版权原因未上传 |

**安装位置**（关键）：

```
<TJ-Superpower>/sp_nav_drone_27/src/sp_filght_sim/external_files/
├── worlds/RMUC2027/meshes/model.dae      ← meshes.zip 解压到这里
└── worlds/RMUC2027_4.dae                 ← 那个 46.5 MB 文件
```

**校验方法**（必须做，否则 SDF 会静默缺件）：

```bash
python3 - <<'PY'
import re
from pathlib import Path
W = Path.home()/"TJ-Superpower/sp_nav_drone_27/src/sp_filght_sim/external_files/worlds"
sdf = (W/"RMUC2027/model.sdf").read_text(errors="ignore")
need = set(re.findall(r"<submesh>\s*<name>\s*([A-Za-z0-9_]+)\s*</name>", sdf, re.S))
dae = (W/"RMUC2027/meshes/model.dae").read_text(errors="ignore")
have = set(re.findall(r'<geometry[^>]*name="([A-Za-z0-9_]+)"', dae))
print(f"SDF 需要 {len(need)} 个, DAE 有 {len(have)} 个, 缺失 {len(need-have)}")
PY
# 期望输出：SDF 需要 130 个, DAE 有 130 个, 缺失 0
```

### 7.3 世界文件的两个版本（`sp_27_features.sdf`）

当前文件里有两个候选场地，**用注释切换**：

```xml
<!-- 方案 A：真实比赛场地（需 §7.2 的 mesh） -->
<include><uri>model://RMUC2027</uri><pose>0 0 0 0 0 0</pose></include>

<!-- 方案 B：仓库自带的围栏场地（零依赖，精度已验证 8.3 cm） -->
<include><uri>model://visual_feature_fence</uri><pose>0 0 0 0 0 0</pose></include>

<!-- 方案 C（未验证）：纯 SDF 棋盘格墙，ORB 特征最理想 -->
<!-- <include><uri>model://wall</uri><pose>0 0 0 0 0 0</pose></include> -->
<!-- <include><uri>model://visual_landmarks</uri><pose>0 0 0 0 0 0</pose></include> -->
```

> **重要历史教训**：我们曾以为"加 `wall` 导致 Gazebo 卡死"，后来证明那次卡死是 WSL 工具调用超时杀了进程树，**与场地无关**。方案 C 其实从未被真正验证过，值得一试。

---

## 8. 关键配置速查

### 8.1 `src/sp_nav_bringup/config/flight.yaml`

```yaml
mode: simulation              # simulation | hardware
common:
  start_controller: false     # 是否由统一入口启动控制器
  control_mode: fixed
  enable_auto_flight: false   # ⚠️ 保持 false，手动发命令起飞更安全
  vocabulary: package://orbslam3_ros/vocabulary/ORBvoc.txt   # 需解压 ORBvoc.txt.tar.gz
  filter_tau: 0.04
  controller_params: package://offboard_controller/config/offboard_controller.yaml
profiles:
  simulation:
    world: sp_27_features
    odometry_source: orb      # orb | truth | none
    ev_ctrl: 11               # EKF2_EV_CTRL 位掩码：水平+垂直位置+yaw
    height_reference: 3       # EKF2_HGT_REF：用视觉高度
    baro_ctrl: 0              # 关闭气压计融合
    initial_heading: -0.785
    settings_file: package://orbslam3_ros/config/stereo_inertial/sp27_gazebo.yaml
    left_topic: /tidesense/left/image_raw
    right_topic: /tidesense/right/image_raw
    imu_topic: /sp27/imu
    body_gyro_topic: /sp27/imu
    base_frame: base_link
    camera_frame: sp27_left_camera_optical_frame
    truth_topic: /model/sp27_uav_0/odometry
```

### 8.2 `offboard_controller.yaml`（影响航线行为）

```yaml
takeoff_altitude: 0.5
cruise_altitude: 2.0
rate_hz: 20.0
prestream_count: 100
waypoint_tolerance: 0.10
fixed_route_profile: mission   # 上升1m → 前飞5m → 右转360° → 返航
turn_rate_deg_s: 15.0
turn_position_limit_m: 0.25    # ⚠️ 旋转段暂停的阈值，我们实测误差 0.2~0.27 卡在这
pose_timeout_sec: 0.5
land_mode: AUTO.LAND
```

### 8.3 ORB 配置 `sp27_gazebo.yaml` 关键项

```yaml
ORBextractor.nFeatures: 1200   # 重场景可降到 800
ORBextractor.iniThFAST: 20
ORBextractor.minThFAST: 7
```

### 8.4 仿真参数（`sp27_sim.launch.py` 内写死）

```python
PX4_GZ_MODEL_POSE = "-1.03455,-1.03030,1.95,0,0,-0.785"   # 无人机出生位姿
PX4_PARAM_EKF2_EV_DELAY = "15"    # 视觉延迟补偿，odometry_source=orb 时
PX4_PARAM_MPC_LAND_SPEED = "0.6"
```

---

## 9. 工作约定与建议

### 9.1 命令纪律

1. **长任务一律脱管**：`setsid nohup ... &` + `disown`，然后用短命令轮询。
2. **状态检查看进程数**：`pgrep -fc "gz sim"` 应为 **2**（服务器+GUI）或 **1**（headless）。
3. **gz CLI 必须匹配分区**：先 `export GZ_PARTITION=<launch 日志里那串>`，否则看不到任何 gz 话题。
4. **分层验证**：gz 单独 → +PX4 → +桥接 → +ORB，每层单独确认再上一层。

### 9.2 判定"到底通没通"

| 层 | 通过标准 |
|---|---|
| Gazebo | `gz topic -e -t /clock -n 1` 有输出（**不是** `gz topic -l` 有列表） |
| PX4 | `ros2 topic echo /mavros/state` → `connected: true` |
| 桥接 | `ros2 topic hz /sp27/imu` **有数**（249 Hz 左右） |
| ORB | `ros2 topic hz /orbslam3/raw_odom` 有数（15 Hz） |
| 视觉位姿 | `ros2 topic hz /mavros/vision_pose/pose_cov` 有数（15 Hz） |
| 可解锁 | 发 `start_builtin` 后 `armed: true` + `mode: OFFBOARD` |

### 9.3 精度评估方法

每次飞行后 `log/orbslam3_flights/flight_*/comparison.csv` 会生成，含 `error_3d_m`、`attitude_error_deg`：

```bash
python3 - <<'PY'
import csv, statistics
from pathlib import Path
root = Path.home()/"TJ-Superpower/sp_nav_drone_27/log/orbslam3_flights"
d = max(root.glob("flight_*"), key=lambda p: p.stat().st_mtime)
rows = [r for r in csv.DictReader(open(d/"comparison.csv"))
        if r["valid_vio"]=="1" and r["truth_matched"]=="1"]
err = sorted(float(r["error_3d_m"]) for r in rows)
rmse = (sum(x*x for x in err)/len(err))**0.5
print(f"{d.name}  n={len(err)}  中位={statistics.median(err):.4f}  RMSE={rmse:.4f}  p95={err[int(0.95*(len(err)-1))]:.4f}")
PY
```

**基线参考**：围栏场地 RMSE 8.3 cm / 中位 6.1 cm。超过 15 cm 就该怀疑退化。

---

## 10. 如果你只有十分钟

1. 读 §2（状态）和 §5（核心任务）
2. 跑 §6.2 的第 7 步验证环境：`bash scripts/verify_a.sh`，期望 12/12
3. 跑 §5.2 的**步骤 1 和步骤 2**（跟踪状态 + 延迟），这两个数据点足以判断方向

---

## 11. 未回答的问题（可以问用户）

以下是我们当时没弄清、需要用户或战队负责人确认的：

1. **`RMUC2027/meshes/model.dae` 的使用许可** —— 属 RoboMaster 赛事资产，能否用于公开发布？（我们因此没把它放进公开仓库）
2. **真实场地下的精度是否本来就该更低** —— 原作者报告悬停 RMSE 4.6–5.7 cm，但那是在他自己的场地里；官方场地几何更大、更复杂，是否可接受 10–20 cm？
3. **B 阶段的验收标准** —— 完整航线跑通即可，还是要给出与某基线的对比报告？
4. **是否还有其他分支/机器上的配置** —— `dev_cfy_air` 分支是另一位成员（cfy）的工作，是否有可复用的场地/标定资产？

---

## 12. 致谢与交接说明

本阶段工作在 Windows/WSL2 上完成，因内存约束（15.7 GB 主机 + WSL 配额争抢）反复卡顿，最终确认**裸机 Ubuntu 是正确方向**（分析见 `docs/03`）。

代码、脚本、数据、踩坑记录都已整理并公开在 <https://github.com/jzq1557/sp27-drone-sim>。
唯一需要手工搬运的是两个场地二进制文件（§7.2）。

祝在 Ubuntu 上顺利。**下一步就从 §5.2 的步骤 1 开始。**
