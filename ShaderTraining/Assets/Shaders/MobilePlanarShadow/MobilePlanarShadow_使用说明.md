# URP 移动端平面阴影

适用环境：当前工程的 Unity 2022.3、URP 14。

Shader 路径：`Assets/Shaders/MobilePlanarShadow/MobilePlanarShadow.shader`  
材质中的名称：`URPExercise/Mobile Planar Shadow`

它会把角色网格的每个顶点沿主平行光方向投影到固定世界高度的水平面，再绘制为半透明阴影。它不是 ShadowMap，不依赖 URP 实时阴影开关，适合平地、MOBA 和移动端角色假阴影。

## 一、用胶囊体快速测试

1. 等 Unity 导入 Shader，确认 Console 没有 Shader 编译错误。
2. 在 Project 窗口右键，选择 **Create > Material**，命名为 `M_PlanarShadow`。
3. 材质 Shader 选择 **URPExercise > Mobile Planar Shadow**。
4. 在场景中创建 **3D Object > Plane**：
   - Position：`(0, 0, 0)`
   - Scale：`(2, 1, 2)`
5. 创建 **3D Object > Capsule**：
   - Position：`(0, 1, 0)`
   - 保留它原来的普通材质。
   - 将原 Capsule 的 **Cast Shadows** 设为 `Off`，先排除实时阴影，便于单独观察假阴影。
6. 选中 Capsule，按 **Ctrl+D** 复制，改名为 `Capsule_Shadow`：
   - Transform 必须与原 Capsule 完全一致。
   - 只把复制体的 Mesh Renderer 材质改为 `M_PlanarShadow`。
   - 将复制体的 **Cast Shadows** 设为 `Off`，**Receive Shadows** 设为 `Off`。
7. 确保场景有 Directional Light，建议 Rotation 设为 `(50, -30, 0)`。
8. 调整相机，以约 45° 俯视角观察地面，进入 Game 视图即可看到胶囊体及其地面投影。

> 不要直接用阴影材质替换原模型唯一的材质，否则原模型本身也会被压到地面。

## 二、推荐测试参数

| 参数 | 推荐值 | 作用 |
| --- | ---: | --- |
| Shadow Color | 深蓝黑色 `(0.025, 0.03, 0.045)` | 阴影颜色，略带冷色比纯黑自然 |
| Opacity | `0.45` | 整体不透明度 |
| Shadow Length | `1.0` | 投影长度倍率，0 表示不沿光线拉长 |
| Ground Height | `0.0` | 地面的世界空间 Y 高度 |
| Plane Offset | `0.01` | 将阴影稍微抬离地面，避免深度冲突 |
| Fade Start Distance | `0.2` | 距脚底中心这个世界单位距离内保持完整浓度 |
| Fade End Distance | `2.0` | 距脚底中心达到此距离时完成渐隐，之后保持终点透明度；设为 `0` 关闭距离渐隐 |
| Fade End Opacity | `0.3` | 终点保留的透明度比例：`0` 完全透明，`0.3` 保留 30%，`1` 不变淡 |
| Stencil Ref | `1` | 防止同一角色的三角形重叠处重复变暗 |

建议用以下操作验证效果：

- 把 Opacity 在 `0` 和 `0.45` 之间切换，确认阴影显隐正常。
- 把 Shadow Length 从 `0.5` 调到 `1.5`，观察长度变化。
- 保持 Fade Start Distance 为 `0.2`，将 Fade End Distance 分别设为 `0.8、2.0、3.0`，观察阴影末端渐隐范围的变化。
- 将 Fade End Opacity 分别设为 `0、0.3、0.6`，对比终点完全透明、保留 30% 和保留 60% 浓度的效果。到达 Fade End Distance 后会保持该透明度，不会继续消失。
- 将 Fade End Distance 设为 `0`，可关闭距离渐隐并对照均匀阴影。
- 将 Directional Light 的 X Rotation 在 `35°～70°` 之间调整，观察投影方向和长度变化。
- 播放角色动画，确认阴影跟随骨架运动。
- 临时关闭 URP 实时阴影，确认这个假阴影仍然显示。

## 三、放到带骨骼动画的角色上

1. 展开角色，找到带 **Skinned Mesh Renderer** 的子物体。
2. 只复制这个 Renderer 子物体，**不要复制整个角色，也不要复制 Animator**。
3. 复制体与原 Renderer 保持同一父物体和相同 Transform。复制体继续引用原来的 Mesh、Bones 和 Root Bone，因此会跟随原角色动画。
4. 将复制体的全部材质替换为 `M_PlanarShadow`，并将 Cast Shadows 设为 `Off`。
5. 如果角色有多个 Skinned Mesh Renderer，就为每个 Renderer 做一个阴影复制体；同一个角色的所有阴影材质使用相同的 Stencil Ref。
6. 为避免真、假阴影叠加，可将原角色的 Cast Shadows 设为 `Off`，或按项目需要关闭 URP 主光实时阴影。

## 四、常见问题

- **看不到阴影**：检查 Opacity、相机视角、Ground Height 是否等于地面高度，以及 Directional Light 是否向下照射。
- **阴影闪烁或出现条纹**：把 Plane Offset 从 `0.01` 增至 `0.02～0.03`。
- **阴影内部出现硬分界或局部更暗**：当前版本的透明度由投影后的地面坐标到脚底中心的距离决定，不依赖源三角形高度，可与 Stencil 正确配合。如果仍出现整块更暗的轮廓，检查原模型是否仍投射 URP 实时阴影，或是否复制了多个阴影 Renderer。
- **阴影过长**：减小 Shadow Length，或让主光更靠近头顶；代码已限制接近地平线时的投影长度。
- **多个角色的阴影相交后消失**：给不同角色分配不同的 Stencil Ref，例如 `1、2、3`；同一角色仍共用一个值。
- **角色上下台阶后阴影悬空或穿地**：这是固定世界 Y 平面投影，需要按角色脚下地面高度更新 Ground Height。斜坡和不规则地面应改用 Decal、圆形 Blob Shadow 或实时阴影。
- **原模型变成黑色或扁了**：误把阴影材质赋给了原 Renderer，恢复原材质即可。

## 五、实现要点

投影公式为：

```text
P' = P - L * ((P.y - GroundHeight) / L.y)
P'.y = GroundHeight + PlaneOffset
```

其中 `P` 是顶点世界坐标，`L` 是朝向主光的单位方向。Shader 只修改 XZ 偏移并把 Y 固定到地面。

距离渐隐公式为：

```text
d = distance(P'.xz, Foot.xz)
t = smoothstep(FadeStartDistance, FadeEndDistance, d)
fade = lerp(1, FadeEndOpacity, t)
alpha = ShadowColor.a * Opacity * fade * (1 - FogFactor)
```

`Foot` 默认取 Renderer 物体原点的 XZ，因此胶囊以及原点位于角色中轴线上的模型可以直接使用。片元透明度只由投影后的地面位置决定，不再依赖源顶点高度；重叠三角形在同一地面位置会得到相同透明度，与 Stencil 配合时不会产生高度差造成的硬色块。
