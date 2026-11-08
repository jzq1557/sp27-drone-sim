# SolidWorks 场地图 → Gazebo（Harmonic）可行方案

> 目标：把 SolidWorks 里的场地模型转成 **Gazebo Harmonic 能用、尺寸真实、带原材质贴图** 的场景。
> 环境：**SOLIDWORKS 2026 SP0** + **SOLIDWORKS Visualize 2026 SP0**（已确认安装）
> 目标端：Gazebo Harmonic（gz-sim 8.15）、SDF 1.9

---

## 0. 先看结论（选路线）

| 路线 | 做法 | 优点 | 缺点 | 建议 |
|---|---|---|---|---|
| **A. 网格路线** | SW → glTF/DAE → Gazebo | 还原度最高，能保留细节 | 面数大，Gazebo 物理/渲染吃紧；ORB 可能因画面过复杂变慢 | **只在需要"看得像"时用** |
| **B. 图元重建路线** | 用 SolidWorks 量尺寸 → 在 SDF 里用 `box`/`plane`/`cylinder` 重建 | 极轻（几千面）、物理稳定、渲染快 | 丢失倒角/细节；贴图需自己铺 | ⭐ **做算法验证推荐这条** |
| **C. 混合路线** | 大结构用图元 + 关键视觉元素用低模网格 | 兼顾性能与观感 | 工作量中等 | 想两者兼顾时用 |

**我的建议**：你这个项目的目的是**视觉导航算法验证**（ORB-SLAM3 需要的是"特征丰富且稳定"的画面，不是"照片级还原"）。上次接入官方 96 MB 场地网格后精度反而从 8.3 cm 掉到 44.8 cm，部分原因就是场景过重导致 ORB 处理变慢。**优先走 B，必要时补 C。**

但如果你就是想高保真还原，下面 A 的完整流程也写全了。

---

## 1. 工具清单

| 工具 | 是否已装 | 用途 | 备注 |
|---|---|---|---|
| **SOLIDWORKS 2026** | ✅ | 几何源头、量尺寸、导出 glTF | |
| **SOLIDWORKS Visualize 2026** | ✅ | 更高质量导出（材质表现更好） | 可选 |
| **Blender 4.x** | ❌ 需装 | 改单位、减面、UV、材质整理、导出 DAE | **免费**，全程核心工具 |
| **Assimp CLI** | ❌ 可选 | 命令行批量格式转换（glb↔obj↔dae） | 免费，Windows 有二进制包 |
| **FreeCAD** | ❌ 可选 | STEP 精确转网格、几何检查 | 免费，需要高精度时用 |
| **Gazebo 自带** | ✅ | `gz sdf -p` 校验 SDF、`gz stats` 看性能 | |

Blender 下载：<https://www.blender.org/download/>（选 Windows Installer，装完自带 glTF/OBJ/DAE 导出器）
Assimp：<https://github.com/assimp/assimp/releases>（取 `assimp-*-windows-x64.zip`）

---

## 2. 路线 A：SW → 网格 → Gazebo（高保真）

### Step 0：在 SolidWorks 里先做"减法"（最重要，决定成败）

场地图里 90% 的面数是没用的：螺纹、倒角、垫片、螺栓、圆角、装饰件。

1. 打开装配体，**压缩/隐藏**所有紧固件、内部结构、非可见细节
2. 只保留：地面、围栏/墙体、场地上的可见结构件、标线
3. **记录 3 个基准尺寸**（后面验证比例用），例如：
   - 场地总长/宽（如 28 m × 15 m）
   - 某个标准件高度（如围栏 1.5 m）
4. `工具 > 评估 > 质量属性` 或 `测量`，确认这些尺寸的**实际数值与单位**（mm 还是 m）

> ⚠️ **单位陷阱**：SolidWorks 文档单位常是 mm。Gazebo 一律按 **米** 解释网格坐标。
> 1:1 导出会得到 1000 倍大的模型（场地变成 28 公里）。这是第一大坑。

### Step 1：导出 glTF（带材质）

**方式一：扩展现实导出（推荐，SW2020+ 都有）**

```
文件 > 另存为 > 保存类型选 "Extended Reality (*.glb)"  →  保存
```

- 会生成单个 `.glb`，**外观/材质/贴图内嵌**在里面
- 若模型很大，导出可能较慢，UI 会卡住一会儿，正常

**方式二：直接 glTF 导出（SW2024+）**

```
文件 > 另存为 > 保存类型选 "glTF (*.gltf / *.glb)"
```

**方式三：SOLIDWORKS Visualize 2026（材质最还原）**

Visualize 里导入模型 → `文件 > 导出 > glTF / USD`。
适合你特别在意渲染效果的情况；但 Visualize 的模型是"视觉模型"，几何精度以显示为准。

### Step 2：Blender 规范化（核心步骤）

```
1) 新建 Blender 工程
   - 打开 "场景属性 > 单位"：Unit System = Metric, Unit Scale = 1.0, Length = Meters
2) 导入 glb：File > Import > glTF 2.0 (.glb/.gltf)
3) 检查尺寸（关键）
   - 选中场地物体，按 N 打开侧栏，看 Dimensions
   - 对照 Step 0 记录的基准尺寸
   - 若差 1000 倍：全选 → S 输入 0.001 → 回车 → Ctrl+A > Scale 应用缩放
4) 减面（性能关键）
   - 加 Decimate 修改器，Ratio 调到总面数 < 200,000 三角形
   - 或用 Planar 模式（保留平面结构，减面更自然）
   - 顺序：先 Decimate，再 Ctrl+A 应用
5) 整理材质
   - 每个材质确认 Base Color 上有 Image Texture 节点（若有贴图）
   - 纯色件直接把 Base Color 设为对应颜色即可
   - 若纹理丢失：手动连 Image Texture → Base Color，UV 用 Smart UV Project 兜底
6) 修正法线
   - 全选 → Shift+N（Recalculate Outside），避免"全黑"
7) 导出 Collada
   File > Export > Collada (.dae)
   - 勾选 "Apply Modifiers"
   - 纹理：勾选 "Copy"（把贴图复制到输出目录，最省心）
   - 单位：Collada 导出没有单位选项，靠你在 3) 里已经缩放正确
```

> DAE（Collada）是 Gazebo 对**材质支持最好**的格式。STL 没有材质，OBJ 材质支持弱，glTF 在 Harmonic 里可加载但不如 DAE 稳。

### Step 3：组装 Gazebo 模型目录

```
rmuc2027_field/
├── model.config
├── model.sdf
├── meshes/
│   └── field_visual.dae          ← Blender 导出的
│   └── field_collision.stl       ← 可选：低模碰撞体
└── materials/
    └── textures/
        ├── floor.png
        └── wall.png              ← Blender 导出时 Copy 出来的贴图
```

**model.config**

```xml
<?xml version="1.0"?>
<model>
  <name>RMUC2027 Field</name>
  <version>1.0</version>
  <sdf version="1.9">model.sdf</sdf>
  <author><name>your-team</name></author>
  <description>RMUC 2027 competition field, converted from SolidWorks.</description>
</model>
```

**model.sdf**（要点注释版）

```xml
<?xml version="1.0"?>
<sdf version="1.9">
  <model name="rmuc2027_field">
    <static>true</static>                    <!-- 场地必须 static -->
    <link name="field">
      <!-- 视觉：用高模，带材质 -->
      <visual name="visual">
        <geometry>
          <mesh>
            <uri>model://rmuc2027_field/meshes/field_visual.dae</uri>
            <!-- 若 Blender 里已缩放正确，这里不用 scale；否则写 0.001 -->
            <scale>1 1 1</scale>
          </mesh>
        </geometry>
      </visual>

      <!-- 碰撞：单独的低模或基本体，性能关键 -->
      <collision name="collision">
        <geometry>
          <mesh>
            <uri>model://rmuc2027_field/meshes/field_collision.stl</uri>
          </mesh>
        </geometry>
        <surface>
          <friction><ode><mu>0.8</mu><mu2>0.8</mu2></ode></friction>
        </surface>
      </collision>
    </link>
  </model>
</sdf>
```

**安装位置**（二选一）

```bash
# 方式 1：用户模型目录（最简单，Gazebo 自动搜索）
mkdir -p ~/.gz/models
cp -r rmuc2027_field ~/.gz/models/

# 方式 2：放到项目的资源目录，并在启动脚本里加 GZ_SIM_RESOURCE_PATH
export GZ_SIM_RESOURCE_PATH="$GZ_SIM_RESOURCE_PATH:<你的路径>"
```

**在世界里引用**（`sp_27_features.sdf`）

```xml
<include>
  <uri>model://rmuc2027_field</uri>
  <pose>0 0 0 0 0 0</pose>
</include>
```

### Step 4：三条硬验证（必须做，别跳）

```bash
# 1) SDF 语法校验
gz sdf -p model.sdf | head -40

# 2) 网格尺寸校验（Assimp 能打印包围盒，单位=米）
assimp info meshes/field_visual.dae | grep -i "bounding"

# 3) 运行时性能（起仿真后看实时率）
gz stats -p <partition>
# RTF 应 ≈ 1.0；相机 15 Hz 不能掉
```

**尺寸快速自检法**：在 Gazebo 里临时插一个 1×1×1 m 的立方体（或直接看着 0.18 m 的无人机），
用肉眼对比"围栏高度是机身的几倍"。已知围栏 1.5 m → 应是机身 8 倍左右。

---

## 3. 路线 B：图元重建（做算法验证推荐 ⭐）

如果你只是要让 ORB-SLAM3 有稳定特征、控制算法能跑，**不需要高模**。

### 做法

1. 在 SolidWorks 里**只用来量尺寸**（长宽高、位置、间距）
2. 直接用 SDF 的 `box` / `plane` / `cylinder` 重建：

```xml
<model name="field_wall">
  <static>true</static>
  <link name="link">
    <visual name="v">
      <pose>0 7.5 0.75 0 0 0</pose>
      <geometry><box><size>28 0.2 1.5</size></box></geometry>
      <material>
        <ambient>0.9 0.9 0.9 1</ambient>
        <diffuse>0.9 0.9 0.9 1</diffuse>
        <pbr>
          <metal><albedo_map>model://field/materials/textures/wall.png</albedo_map></metal>
        </pbr>
      </material>
    </visual>
    <collision name="c">
      <pose>0 7.5 0.75 0 0 0</pose>
      <geometry><box><size>28 0.2 1.5</size></box></geometry>
    </collision>
  </link>
</model>
```

3. 贴图直接平铺 PNG（`<albedo_map>` 或材质的 `<diffuse>` + Ogre material script）

**优点**：整个场地几百面，RTF 稳、ORB 处理快、物理不抖。
**参考先例**：仓库里现成的 `wall` 模型就是纯 SDF 拼的 10.2×10.2 m 棋盘格墙，正是这个思路。

### 什么时候用 A、什么时候用 B

| 场景 | 选择 |
|---|---|
| 调 ORB / 控制 / 精度统计 | **B** |
| 做论文配图、演示视频 | A |
| 用视觉做感知训练（真实纹理很重要） | C |

---

## 4. 常见坑对照表

| 现象 | 根因 | 修法 |
|---|---|---|
| 场地是 1000 倍大（像一片大陆） | SW 单位 mm，Gazebo 按 m | Blender 里 `S 0.001`；或 SDF `<scale>0.001 0.001 0.001</scale>` |
| 模型全黑 | 材质未导出 / 法线朝内 | Blender 里重赋材质 + `Shift+N` 重算法线 |
| 纹理丢失变纯色 | 贴图是外部路径未随包复制 | 导出时勾 "Copy"，或手动放 `materials/textures/` |
| 模型加载失败 / 找不到 | `model://` 解析不到 | 放 `~/.gz/models/` 或加 `GZ_SIM_RESOURCE_PATH` |
| Gazebo 秒退 / 卡死 | 面数百万级 | Decimate 到 <20 万；碰撞用基本体 |
| 无人机穿墙 / 抖动 | 碰撞网格太复杂或非凸 | 碰撞改成 box 或简单凸包 |
| 画面过曝 / 奇怪高光 | 材质 specular 不对 | 用简单 diffuse，去掉金属/清漆属性 |
| ORB 跟踪变差、延迟变高 | 场景过重导致渲染/处理变慢 | 减面；或改走路线 B |

---

## 5. 关于"原材质贴图"的现实提醒

SolidWorks 的 **appearance（外观）** 分两类：

1. **程序化外观**（颜色 + 粗糙度 + 金属度，无图片）—— 导出后就是**纯色**
   - 比赛场地 90% 是这类（板材、铝型材、亚克力）
   - **这通常完全够用**：ORB 要的是几何边缘和对度，不是真实纹理
2. **图像贴图**（decal / 纹理文件）—— 需要 UV 展开才不扭曲
   - SW 的 decal 在 glTF 导出中**可能丢失**
   - 需在 Blender 里手动：`Smart UV Project` → 连 Image Texture 节点

**建议**：
- 纯色件 → 直接给 diffuse 颜色（最快）
- 地面标线/丝印 → 单独做一张 PNG，用一个 plane 平铺
- 不要追求"照片级"，那属于路线 A + Visualize 的范畴，与算法验证无关

---

## 6. 推荐执行顺序（给你的行动清单）

```
□ 1. 装 Blender 4.x
□ 2. SolidWorks 里压缩细节 + 记录 3 个基准尺寸（含单位！）
□ 3. 决定走 A 还是 B（我建议先做 B 打通链路）
□ 4. 路线 A：File > Save As > Extended Reality (.glb)
   路线 B：直接照 §3 写 SDF
□ 5. Blender：设单位 → 导入 → 校验尺寸 → 减面 → 修法线 → 导出 .dae
□ 6. 组装模型目录（model.config + model.sdf + meshes + textures）
□ 7. 放 ~/.gz/models/，世界里 include 它
□ 8. 三条硬验证（SDF / 包围盒 / RTF）
□ 9. 插一个 1 m 立方体做比例对照
□ 10. 上飞：先 headless 跑 30 秒，看 ORB 延迟是否 < 0.3 s
```

**第 10 步是关键判据**：无论场地多好看，只要 ORB 里程计延迟超过 0.3 s（`vio_bridge` 的陈旧阈值），
视觉位姿就会被丢弃、PX4 不解锁。所以"越大越真实"未必越好——**先保证延迟达标**。

---

## 7. 补充：如果你想把 STEP 也纳入流程（做精确碰撞）

SolidWorks 的 STEP 是几何"真值"，适合用来做高精度碰撞体：

```
SW: File > Save As > STEP AP214 (.step)
  ↓
FreeCAD（免费）: 打开 STEP → 转网格（Mesh 工作台）→ 导出 STL
  ↓
Gazebo: 作为 <collision> 的网格
```

或者用 **Blender + FreeCAD 插件**在 Blender 里直接开 STEP（如 `postsilver/import_step`、`Peak-Design/CADder`）。

> 一般不需要：碰撞体用 box/cylinder 近似通常足够，且物理更稳定。
