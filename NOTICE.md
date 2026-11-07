# NOTICE —— 第三方资产、许可与免责声明

本仓库（`sp27-drone-sim`）只包含**部署脚本、工程文档、飞行日志与截图**，用于技术记录与复现参考。

---

## 1. 未随仓库分发的资产

| 资产 | 原因 |
|---|---|
| `sp_nav_drone_27` 源码（含 ORB-SLAM3、VINS-Fusion、PX4 overlay 等） | 私有仓库，版权归同济大学 SuperPower 战队所有；本仓库不复制、不再分发 |
| `RMUC2027/meshes/model.dae`（96 MB） | 原作者仓库 `.gitignore` 显式排除；属 RoboMaster 赛事场地资产，不宜公开分发 |
| `RMUC2027_4.dae`（46.5 MB） | 同上 |
| PX4-Autopilot 源码 | 由使用者自行按 v1.16.2 拉取；其许可为 BSD-3-Clause |
| Gazebo / gz-sim | Apache-2.0，由系统包管理器安装 |
| MAVROS | BSD-3-Clause |
| ORB-SLAM3 | GPLv3（注意：GPL 有传染性，若二次分发需遵守其条款） |
| Pangolin | MIT |
| `ROS 2 Humble` | Apache-2.0 |
| 论文 PDF *Learning vision-based agile flight via differentiable physics* | Springer Nature 版权，未随仓库分发 |

如果你需要上述资产，请分别向对应权利人获取。

---

## 2. 本仓库自有内容的许可

除特别标注外，本仓库内的**脚本、文档、截图、日志**由本仓库作者提供，采用 **MIT License** 发布。

> 注意：`scripts/certs/` 下是**校园网根证书**（`Scholar Root CA v1/v2`），
> 它们的用途仅是让 WSL 内的 `git`/`curl` 能信任校园网的 SSL 审计代理。
> 证书本身不归本仓库作者所有，随附仅为可复现性参考；**若你的环境不需要，请删除**。

---

## 3. 学术引用

本项目的仿真验证对象对应以下论文的方法与代码栈，若用于研究请引用：

```bibtex
@article{zhang2025learning,
  title   = {Learning vision-based agile flight via differentiable physics},
  author  = {Zhang, Yuang and Hu, Yu and Song, Yunlong and Zou, Danping and Lin, Weiyao},
  journal = {Nature Machine Intelligence},
  volume  = {7},
  pages   = {954--966},
  year    = {2025},
  doi     = {10.1038/s42256-025-01048-0}
}
```

---

## 4. 免责声明

- 本项目是**个人/团队内部的技术验证记录**，与同济大学、上海交通大学、大疆创新（DJI）及 RoboMaster 组委会无隶属关系，不代表其立场。
- 所有仿真结果**仅适用于仿真环境**，不可直接作为真机飞行参数使用的依据。
- 使用本项目脚本造成的一切后果（包括但不限于设备损坏、数据丢失、违反所在机构的网络与信息安全规定）由使用者自行承担。
- `scripts/certs/` 中的校园网证书仅用于解决特定校园网络环境下的 TLS 信任问题，请在使用前确认符合你所在机构的网络使用政策。
