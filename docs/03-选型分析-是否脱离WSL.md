# 是否值得脱离 WSL 换仿真方案 —— 可行性分析

日期：2026-11-07
背景：SP27 仿真在 WSL2 里跑，主机 15.7 GB 内存 + RTX 4060 Laptop 8 GB，内存被 Windows 与 WSL 反复挤爆，导致 DSH/桌面卡死。
问题：换 Isaac Sim / Isaac Lab / Unreal / Unity 能否摆脱 WSL，甚至完全不依赖 Linux？

---

## 结论先行

1. **换仿真器解决不了"依赖 WSL"的问题**。真正绑定 Linux 的不是 Gazebo，而是 **PX4 SITL + MAVROS + ORB-SLAM3 + ROS 2** 这一整条验证栈。换渲染引擎，这条栈还在 Linux 上。
2. **Isaac Sim 在本机硬件上不可行**：官方要求 x86_64 工作站"至少 32 GB 内存 + 16 GB 显存"，本机是 15.7 GB / 8 GB，差距近一倍。
3. **想彻底不用 WSL，唯一务实的路是"让 Linux 跑在裸机"**：双系统 / 独立 Linux 机器 / 便携 SSD 启动。这样内存、显卡、GUI 全部归 Linux，问题从"分配内存"变成"根本不缺内存"。
4. 短期不必停产：**无 GUI（HEADLESS=1）模式**已可用，内存需求从 ~4 GB 降到 ~3 GB，是当前最省事的缓解。

---

## 一、真正约束在哪里（逐项核实）

| 组件 | Windows 原生可行性 | 依据 |
|---|---|---|
| **PX4 SITL** | ❌ 不发布 Windows 原生 SITL | 官方开发环境要求 Linux；Windows 需 WSL2。社区有原生 Windows SITL 的 PR（[PX4#27297](https://github.com/PX4/PX4-Autopilot/pull/27297)）但**未合并** |
| **MAVROS** | ❌ 无 Windows 发行 | 仅有 Linux 版 ROS 2 deb；源码编译亦以 Linux 为目标 |
| **Gazebo (gz-sim)** | ❌ 无 Windows 官方支持 | 官方二进制只提供 Linux / macOS |
| **ORB-SLAM3 + Pangolin** | ⚠️ 理论可编译，实际极痛 | 依赖 Pangolin/OpenGL/ROS 封装；团队现成的是 Linux 构建 |
| **ROS 2 Humble** | ⚠️ 有 Windows 版但不完整 | 上述关键包（MAVROS/ros_gz）无 Windows 版 |

**关键点**：SP27 验证的**对象**就是 PX4 + MAVLink + ORB-SLAM3 这套真实栈。要验证它，就必须让它跑起来——而它只在 Linux 上跑得起来。

---

## 二、四个候选方案逐一评估

### 方案 A：Isaac Sim / Isaac Lab

| 项 | 事实 |
|---|---|
| 平台支持 | Isaac Lab 3.0 已支持 **Ubuntu 22.04+ 与 Windows 11 x86_64**（官方文档明确列出） |
| **硬件要求** | 官方原文：x86_64 工作站"**plan for at least 32 GB RAM, 16 GB VRAM** and a supported RTX GPU" |
| 本机 | 15.7 GB RAM / 8 GB VRAM → **不足**（内存差 2 倍，显存差 2 倍） |
| PX4 联动 | 需 Pegasus 一类桥接（Linux + Docker），**依然要 Linux** |
| 迁移成本 | 极高：场景、传感器、控制接口、评估脚本全部重写 |

**判断：不可行**。硬件不达标是硬门槛；且它并不解除 Linux 依赖。

> 参考：[Isaac Lab 安装与系统要求](https://isaac-sim.github.io/IsaacLab/main/source/isaaclab/installation.html)、[Isaac Sim 要求](https://docs.isaacsim.omniverse.nvidia.com/latest/installation/requirements.html)

### 方案 B：Unreal Engine + AirSim / Project AirSim

| 项 | 事实 |
|---|---|
| Windows 支持 | ✅ UE 原生 Windows |
| AirSim 状态 | 微软已于 2022 年归档，停止维护 |
| 硬件 | 8 GB 显存勉强能跑，但多相机 + 高帧率会吃紧 |
| PX4 联动 | AirSim 的 PX4 SITL 联动仍在 Linux 侧；ROS 桥接同样 Linux |
| 迁移成本 | 高：需重建 SP27 机型、相机、IMU、MAVLink 时序 |

**判断：技术上能跑，但费力且不解除 Linux 依赖**，且建立在已归档项目上有维护风险。

### 方案 C：Unity（或团队现成的 Godot `sp_sim`）

| 项 | 事实 |
|---|---|
| Windows 支持 | ✅ 原生 |
| 已有资产 | 团队 `sp_sim` 是 **Godot 做的操作手训练模拟器**，不是飞行动力学验证平台；官方社区也有 2027 场地 Unity 资源 |
| 缺口 | 旋翼动力学、IMU、双目相机渲染、MAVLink/PX4 联动都要自己实现 |
| PX4 联动 | 可与 PX4 SITL 通过 MAVLink 对接，但 PX4 仍在 Linux |
| 迁移成本 | **极高**（等于自己造一个仿真器），且验证语义会变（不再是原栈） |

**判断：不建议**。适合做"操作手训练"，不适合做"算法验证"。

### 方案 D：让 Linux 跑裸机（切断 WSL）

| 形态 | 说明 | 迁移成本 | 效果 |
|---|---|---|---|
| **D1 双系统（推荐）** | 本机分出 ~150 GB 装 Ubuntu 22.04，保留 Windows | 低：现有脚本 `bootstrap_root.sh` / `build.sh` 基本可直接复用 | **15.7 GB 内存全给 Linux**，Gazebo GUI 原生，彻底摆脱 WSL 内存竞争 |
| **D2 独立 Linux 机器/实验室服务器** | 台式机或服务器 | 低（同样复用脚本） | 最稳，可与 Windows 并行使用 |
| **D3 便携 SSD / U 盘 Ubuntu** | 外置盘装系统 | 低 | 不动机内分区，插上即用 |
| **D4 云 GPU 实例** | 租用 | 中（网络、授权、数据同步） | 性能最强但要花钱、延迟高 |

**判断：D 是唯一能真正"不依赖 WSL"的路**，而且**不需要换仿真器、不需要重写验证栈**。

---

## 三、对比总表

| 方案 | 解除 WSL 依赖 | 本机硬件满足 | 迁移成本 | 验证语义是否保持 | 建议 |
|---|---|---|---|---|---|
| A. Isaac Sim / Lab | ❌（PX4 仍要 Linux） | ❌（差 2 倍） | 极高 | 需重建 | 不可行 |
| B. Unreal + AirSim | ❌ | ⚠️ 勉强 | 高 | 需重建 | 不推荐 |
| C. Unity / Godot | ❌ | ✅ | 极高 | 会变 | 不推荐 |
| **D1. 双系统 Ubuntu** | ✅ | ✅ | **低** | **完全保持** | **推荐** |
| D2. 独立 Linux 机器 | ✅ | ✅ | 低 | 完全保持 | 有条件则最佳 |
| 现状：WSL + 限内存 | ❌ | ⚠️ 紧张 | 0 | 保持 | 短期可用 |

---

## 四、推荐路线

**短期（今天就能用）**
1. 用 `run_sim_headless.sh`（`HEADLESS=1`）跑飞行与精度采集：无 Gazebo GUI，省约 1 GB。
2. 只在"要肉眼看画面"时用 `run_sim.sh`，并先关掉飞书/Edge。
3. `.wslconfig` 保持 `memory=6656MB`；实测 5 GB 会在加载 96 MB 场地后 OOM（`/clock` 都起不来），6.3 GB 可跑但 Windows 仅剩约 1 GB。

**中期（建议执行）**
- **装 Ubuntu 双系统（方案 D1）**：本机 946 GB 剩余空间足够；现有 `bootstrap_root.sh`、`build.sh`、`run_sim.sh` 可直接复用，预计半天完成环境重建。此后 15.7 GB 内存全归 Linux，GUI 原生、无 vmmem 竞争，DSH 也不会再被挤死。

**长期（若要做感知/合成数据）**
- Isaac Sim 这类高保真渲染确实更强，但需要 **≥32 GB 内存 + ≥16 GB 显存的台式机**，属于换硬件而非换软件的问题。

---

## 五、需要注意的前提

1. 双系统会改变开机流程，且 Windows 与 Linux 不能同时用（除非另配机器）。若你要边跑仿真边用 Windows 软件，选 **D2 独立机器**。
2. 现有 WSL 工程（`/home/justin/TJ-Superpower`）**可直接迁移**：源码、脚本、配置文件都在 home 下，tar 打包即可搬到裸机 Linux。
3. 无论哪条路，`RMUC2027` 场地网格、`ros_gz` 源码编译、`sync_queue_size` 这些已解决的问题都不会丢——它们已经是脚本化/文档化的状态。

---

## 六、补充：改用 Isaac Sim 旧版本可行吗？（2026-11-07 追加）

### 硬件门槛的历史情况

| 版本 | 官方内存/显存口径 |
|---|---|
| Isaac Sim 4.x / 5.x（现行口径） | x86_64 工作站「**至少 32 GB 内存 + 16 GB 显存**」 |
| Isaac Sim 2022.2 / 2023.1（更早） | 显存最低线一直是 **8 GB（RTX 3070 级）**，内存推荐 32 GB、最低 16 GB |

本机是 **15.7 GB 内存 + 8 GB 显存**：显存刚够老版本的最低线，内存低于推荐值。
**所以"同款机器装过老版本"是合理的**——能装、能跑小场景，但不等于能满足多相机 + 高帧率的验证需求。

### 但 PX4 联动这条路仍然堵死

唯一成熟的开源 PX4 + Isaac 方案是 **Pegasus Simulator**（918★，维护活跃）。它的官方安装文档原文：

> "We have tested Pegasus Simulator with Isaac Sim 5.1.0 release on **Ubuntu 22.04LTS** with NVIDIA driver 550.163.01. The PX4-Autopilot used during development was **v1.14.3**. Older versions Ubuntu and PX4-Autopilot were not tested. **This extension was not tested on Windows.**"
>
> —— [Pegasus 安装文档](https://pegasussimulator.github.io/PegasusSimulator/source/setup/installation.html)

三个硬约束：

1. **平台**：Pegasus 只测过 Ubuntu 22.04，Windows 未测试；
2. **PX4 版本**：它绑定 **PX4 v1.14.3**（`make px4_sitl_default none`），而本仓库用的是 **v1.16.2** —— 等于要把 PX4 降级，验证对象就变了；
3. **版本强绑定**：Pegasus v5.1.0↔Isaac 5.1.0、v4.5.1↔Isaac 4.5.0、v4.2.0↔Isaac 4.2.0，跨版本不兼容。

### 结论

- **Isaac 老版本可以在 Windows 上跑起来**（做可视化、合成数据、感知算法调试），但要跑 **PX4 + ORB-SLAM3 闭环验证**，仍然必须 Linux；
- 换 Isaac 是"把内存压力从 WSL 搬到 Windows"：Isaac 自身要吃 4–8 GB，WSL 里 PX4 + ORB 还得 1.5–2 GB，**总量不减反增**；
- 因此**不改变上一节的结论**：要彻底摆脱 WSL，正确做法是让 Linux 跑裸机（双系统 / 独立机器），而不是换仿真器或退版本。

如果只是想"看好看的画面 / 生成感知数据"，值得单独试 Isaac Sim 4.2 或 4.5（老版本对 8 GB 显存更友好），但应作为**独立课题**，与 SP27 飞行验证解耦。
