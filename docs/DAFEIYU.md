# 大肥鱼与正常版头像

显示名为“大肥鱼”，稳定角色 ID 为 `dafeiyu`，性格为活泼可爱。正常人物立绘用于首页、详情、大图和身份头像；Q 版用于岛上小人物与动作。小白的聊天、首页和提醒头像同样改用正常版头部裁图，岛上形象仍为 Q 版。

## 已接入

- 角色目录、选择与持久化、角色详情、立绘和 Q 版大图。
- 独立单聊、历史记录、群组选择与成员管理；测试回复仍为“聊天功能测试中”，没有调用 AI 接口。
- 陪伴、招呼、心情、倒计时、锁屏/展开立绘、三种岛上背景和自动活动。
- 独立的待机、左右走路和左右打滚资源。走路每个方向 10 秒，低抬脚，连续完整步态；打滚每个方向 5 秒并横向移动。
- 大肥鱼尚无角色语音。闹钟和陪伴结束提醒可使用系统提示音；保留小白原有语音及独立偏好，不借用其他角色的录音。

## 表情与动作

待机有挥手、眯眼笑、歪头、好奇张嘴和俏皮眨眼。走路按一个完整步态变化微笑、半眯眼和开心闭眼。打滚依次有准备时的认真表情、鼓脸用力、闭眼翻滚、惊讶睁眼、短暂晕乎乎和开心笑。表情按阶段保持，不逐帧随机换脸。左向动作由已验收的右向绘图机械镜像，身份和服装不变。

在 App 的“日常动作”中轻点小人物，会播放约 1.2 秒的好奇、挥手与微笑回应，再继续原来的活动。此点击互动位于 App 内预览，不改变系统灵动岛的点击行为。

素材通过内置 `image_gen` 生成，提示词在 [generation.json](../Art/DafeiyuMotion/generation.json)，帧时长与表情说明在 [manifest.json](../Art/DafeiyuMotion/manifest.json)。生产 PNG 为 512×640 透明图，底部锚点为 y=600；同一动作共用缩放系数，避免逐帧自适应大小。原始生成文件和处理报告保存在本次工作区 `output/dafeiyu/`，不属于运行时资源。

## 构建与扩展

执行 `Scripts/prepare_assets.py` 和 `Scripts/prepare_motion.py` 后再运行 XcodeGen。头像由 `Characters.json` 的 `avatarCrop` 裁取正常版立绘，避免把 Q 版误用作身份头像。

大肥鱼的正常立绘以 `Art/dafeiyu-standing-top.png` 和 `Art/dafeiyu-standing-bottom.png` 两个无损分块提交，准备资源时原像素拼回 `Art/dafeiyu-standing.png`；不缩小、不压成有损图片。

动作配置以角色为单位提供 manifest、图片命名空间、字体前缀和时间轴文件名。两位角色共享移动几何和计时机制，但表情帧、待机停留时间、预览、字体与资源彼此独立。当前两位角色共生成 361 个计时字体（每位三种背景各 60 个，加一个共用遮罩字体）；这是生成产物，不提交字体二进制。

验证包括原有 14 项动作回归、4 项跨角色资源检查、Swift 领域测试、CoreText 实际字形校验，以及 iPhone 模拟器界面测试和截图。本次不打包 IPA。模拟器结果不等于实体 iPhone 动画、声音或后台耗电已验收。

最终代码提交 `a000d9a661b50bc1af2d0738a99e8adc731b7a7c` 已通过 [GitHub Actions 模拟器验证](https://github.com/yangtao990518/DragonIsland/actions/runs/40469188795)：42 项 Swift 单元测试、18 项 Python 资源/动作回归、672 组 CoreText 字形校验及 4 项 iPhone 16 Pro / iOS 26.2 界面测试。包含大肥鱼单聊与记录恢复、双角色群聊、正常版头像、首页立绘、点击回应、左右动作预览和系统提示音闹钟编辑入口。App 与 Widget 编译成功。

测试原始附件共 16 张，保存在 Actions 的 `chat-test-screenshots-and-logs` 中（保留 7 天），本次工作区另存于 `output/dafeiyu/verification/final/`。该目录有原始截图、日志与 `VERIFICATION.json`；ZIP 的 SHA-256 为 `5c2becbf7c6ce45e0e32b838706984b28777c374af423dae780dafd8326a6ef8`。
