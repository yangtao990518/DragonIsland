# 大肥鱼舞蹈：系统灵动岛模拟器演示

用户于 2026-10-29 要求先以最新去绿幕候选在 GitHub iOS 模拟器演示，暂不生成 IPA。独立分支 `codex/dance-island-review` 基于 `codex/character-chat` 的 `cfc0ba5`；原 `DragonIsland-Latest` 工作目录中全部未提交修改保留，没有拿被否决的旧 v4 图集上传。

## 本次素材

两段均为「原片 closed-form 稳定 alpha + CorridorKey 边缘前景 RGB + 深层内部原 RGB + RGB-only 局部去污染」。不使用逐帧 AI 图片重绘，不删除小连通区，不侵蚀轮廓，不逐帧重新居中，不生成新姿势。1440 帧颜色校正前后 alpha 与深层内部 RGB 不变性断言通过。

本机视频名与 Git 动作编号相反，沿用既有 Git ID 和开关，避免交换用户设置：

| 本机源文件 | Git ID | SHA256 |
| --- | --- | --- |
| 大肥鱼舞蹈1 .mp4 | dafeiyu-dance2 | 1f22d4ffb88bb0ca84566cfdd829db4bd3c2947fe6ca881f9da3e930e6e3fc30 |
| 大肥鱼舞蹈2.mp4 | dafeiyu-dance1 | 56db978c9569dc12e778153504ac7b959c42a475a73034600ff02a8bbb606b60 |

每段完整 720 帧、12.096009 秒、原始 PTS 和末帧停留不变，原始 1280×720 RGBA 固定裁剪后打包为 60 张 3×4 无损 WebP。全部 1440 帧从图集还原原画布，RGBA SHA256 与本次预览源帧一致。预览 MP4 只是黑白背景检查视频，App 和灵动岛仍使用透明源图集派生资源。已确认的遛狗 1.6 秒、御剑、骑鲸等素材不改。

使用的 [CorridorKey](https://github.com/nikopueringer/CorridorKey) 及 [ONNX 导出](https://github.com/alexandremendoncaalvaro/CorridorKey-Runtime) 来自 CC-BY-NC-SA-4.0 项目；本次本机非商业测试不把模型或运行库放入 App/Widget。原模型 SHA256 `9e764280cd41ca7241af19f5f778dd9031e995f55e191199c87791a7e09452f8`，本机 DirectML 兼容图 `7853460432046f1a7deb0bd699feb8a15081954dc85b28d017d00bd79c8dbe24`。兼容改写仅将 FP16 提升为 FP32、48 个高维 attention MatMul 展平成等价三维批量运算，权重未训练/修改；4 帧对照 CPU 图的预乘 RGB 最大差异 <0.136/255。候选动态观感尚待用户判断。

## 实际演示范围

`.github/workflows/dance-island-review.yml` 生成实际 App/Widget、原生计时字体，在 iOS 26.2 Pro 模拟器启动真实 ActivityKit 实时活动，退到 SpringBoard，录制收起状态下两个完整舞蹈，再长按展开。不是 App 内黑色预览框或网页模拟图。

DEBUG 参数 `--preview-island-dances` 只启用大肥鱼的两个舞蹈，固定选择真实 bank 96（mask 48，seed 0），把 epoch 提前 65 秒，从第一个舞蹈开始前 10 秒进入录制；两段分别使用原生计划 75、88 秒处的 13 秒时间槽，源动作时长和播放速度不改。元数据保存实际 epoch、计划开始时间和源码提交，以便从全屏系统录像定位片段。

**现有展开区域显示正常版立绘及交互按钮；舞蹈发生在 compactLeading 收起区域。** 本次如实展示两种现状，没有声称展开后已在播放舞蹈。岛上字体目标采样 30 Hz、系统实际刷新由 iOS 决定，完整源图集仍保留全部 720 帧。模拟器结果不能冒充真机签名、耗电、后台长期或静音表现验收。

产物 `dance-system-island-review` 包含原始系统录像、实际截图、无障碍树、实时活动日志、录制/计划元数据及编译/测试日志；不含 IPA、签名身份、会话或模型。完成后在本文件补充运行链接和实际结果，不用旧云端通过记录代替本次运行。

本机发布前：Swift 新改动语法检查通过，差异空白检查通过；完整视频专项 6 项中 5 项通过、1 项因尚未生成 App 显示图集而跳过。完整打包时另逐帧核对了全部 1440 帧的无损还原；App 显示图集、字体、Swift 编译和实际系统录像由本次云端任务继续验证。
