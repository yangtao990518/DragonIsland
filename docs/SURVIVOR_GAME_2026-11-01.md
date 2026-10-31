# 大肥鱼灵境试炼首版

## 用户本轮范围

在现有 mAIverse 内制作原生 2D 幸存者小游戏，先只开放大肥鱼。玩家只走位，普通攻击为小水泡，紫霄雷自动释放，升级暂停三选一，标准局实际战斗时长 20 分钟。UI 由 Codex 实现。小白暂不开放，不新增手动攻击按钮。

本轮继续遵守不启动模拟器、不打包 IPA 的限制。新增工作流只执行逻辑测试、素材检查与 App / Widget 的 iphoneos 编译。

## 已接入代码

- 我的世界下方新增「灵境试炼」入口，全屏选角、开始/续玩、战斗、升级、暂停和结算界面。
- 游戏选角不改变陪伴角色或聊天配置；主页动画被游戏遮挡时暂停。
- 左下虚拟摇杆走位，右侧显示已学水泡/雷阵等级；HUD 显示生命、灵晶升级进度、剩余时间和击败数。
- 水泡自动攻击附近目标，3/5级增加弹体。紫霄雷五级对应五组真实视频特效，学习后自动施放；另外提供伤害、冷却、走速、拾取和生命强化。
- 两种视频小怪自动追踪；分阶段提高密度，最后两分钟出现放大的小魔物首领。首领暂复用已有小魔物素材，没有另造首领视频。
- 升级、菜单、后台为独立暂停原因；只恢复对应原因。暂停期间不走计时、不移动、不扣血、不推进技能。
- 暂停/切后台/升级选择时保存本机 `Library/Application Support/SurvivorGame/run.json`，下次选角可继续。保存战斗状态和随机数，不计离线时间；完成/失败后删除本局续玩文件。此文件不是聊天记忆或聊天媒体备份。
- `Shared/Models/SurvivorBattle.swift` 为纯战斗规则；`App/SurvivorScene.swift` 为 SpriteKit；`App/SurvivorGameView.swift` 为 SwiftUI 界面及生命周期。

## 两条用户原片与正式素材

用户原目录为 `D:\AI视频素材\游戏技能素材`。归档原片已经放入 Git 的 `Art/Survivor/Sources/actors.mp4` 与 `thunder.mp4`，不依赖这台电脑的外部盘符构建。

两条均为 1280×720、240 个解码原帧，源轨道基准 60 FPS。原播放器总时长均为 **4.096009 秒**，包含较长帧间隔和最后一帧停留；不能改成简单的 240÷60=4 秒播放。时间基准为 1/15360，实际 PTS、停留时间保留在逐帧清单内。

人物视频出现了白色外边/格线，已经按整段固定区域拆分，不能直接按原首帧图的四等分坐标裁剪：

| 片段 | 固定裁剪 [左,上,右,下] | 结果 |
| --- | --- | --- |
| 大肥鱼左跑 | [656,14,992,369] | 240帧 |
| 紫色小怪左跑 | [288,398,626,706] | 240帧 |
| 蘑菇小怪左跑 | [656,398,992,706] | 240帧 |
| 紫霄雷1 | [0,0,427,360] | 240帧 |
| 紫霄雷2 | [427,0,853,360] | 240帧 |
| 紫霄雷3 | [853,0,1280,360] | 240帧 |
| 紫霄雷4 | [213,360,640,720] | 240帧 |
| 紫霄雷5 | [640,360,1067,720] | 240帧 |

小白仍保留在归档的原片里，本轮没有制作游戏片段。右跑镜像左跑；上下斜走按水平分量选左右，纯上下保留朝向。待机使用既有 `DafeiyuChibiDetail` 静态 Q 版，不扭曲跑步的腿制造新站姿。

抠像采用 PyMatting CF alpha、相邻遮罩对齐稳定、ML 分别求前景/背景颜色，再用已知绿幕颜色的混合关系约束污染边缘透明度并重求前景。只适用于本次已核对且本体无绿色材质的源片。没有最终轮廓侵蚀、邻色涂边、补姿势或重画腿。旧 rgba 试版仍留在忽略的 output 中，不清理用户预览。

每条片段只做一次全段联合透明边界裁剪，并固定脚底/法阵落点锚点，不逐帧重新居中。每组 240 个时间记录均保留，没有丢帧、补帧、加速。无损 WebP 正式图集和原片合计约 92.2 MB；源片 SHA256、每页 SHA256、固定区域、尺寸、锚点和时序详见 `Art/Survivor/manifest.json`。

普通构建只调用 `Scripts/prepare_survivor_assets.py`（已接入 prepare_assets），将正式图集无损转为 App 专用 PNG 文件夹。Widget 不打入这套游戏图集，不需要 PyMatting、原片解码工具或剪映。没有把游戏动作自动加入陪伴日常活动。

普攻按本轮“之前的小水泡”要求，复用 `output/survivor-skills-2026-10-31/dafeiyu-water-bubble-levels-v2.png` 中最左边的初级水泡，固定 [95,330,285,455] 抠图，没有重新生成。原整图、透明水泡及哈希/球心锚点已经归档到 `Art/Survivor/Static/`。旧 README 对整套升级技能的否决不覆盖本轮重新指定小水泡作为普攻的要求。弹体在游戏内按速度方向旋转、位移和增加数量，原图不是视频，不制造额外动画帧。

## 重做抠像 / 素材审查

普通开发不用重新抠像。确需重算时，准备 PyAV、Pillow、NumPy、OpenCV、SciPy、PyMatting；在 D 盘设置 TEMP/TMP，并从仓库目录运行：

```text
python Scripts/process_daily_video.py analyze Art/Survivor/Sources/actors.mp4 output/game-rematte/actors --id actors --title actors
python Scripts/process_daily_video.py analyze Art/Survivor/Sources/thunder.mp4 output/game-rematte/thunder --id thunder --title thunder
python Scripts/process_survivor_videos.py prepare output/game-rematte
python Scripts/process_survivor_videos.py matte output/game-rematte --workers 3 --pilot
python Scripts/process_survivor_videos.py matte output/game-rematte --workers 3
python Scripts/preview_survivor_assets.py output/game-rematte
python Scripts/process_survivor_videos.py pack output/game-rematte --output Art/Survivor
```

换原片、颜色、分辨率或排版时必须重新审查固定区域和抠像参数，用新的输出目录，不能照抄本次固定裁剪。

本机完整源帧/缓存/审查输出在 `output/survivor-video-import-2026-11-01/`，均不上传 Git。`all-clips-original-timing.mp4` 是八组源素材抠像对照预览，不是 App 录像。240 帧完整回解、视频轨时长 4.096009 秒已核对。黑白底与鞋边近景为 `edge-check-black-white.png`；代表片段全帧绿污染统计为 `edge-quantification-v2.json`，这项统计不能替代观感验收。

## 当前验证边界

本机5项素材回归通过：原片哈希、完整帧序及停留、图集透明度/尺寸/哈希、WebP→PNG 像素无损，以及旧小水泡的原图/透明图/安装资源一致性。初次云端158项 Swift 测试通过，App / Widget 最终编译结果将在下方补充。

尚未运行新的模拟器或真机游戏试玩。数值、地图及 UI 为首轮实现；不宣称已完成20分钟真机流畅度、耗电、内存或平衡性验收。源码本身不会更新手机上已有 IPA。

## 最终云端验证

功能源码 `8f810166e47db3af244614bc74f9fabe2c66e5fa` 的 [Actions 41222674142](https://github.com/yangtao990518/DragonIsland/actions/runs/41222674142) 全部成功：

- 158 项 Swift 测试，0 失败，覆盖原有聊天/记忆规则及新增战斗、暂停、自动攻击、升级、存档确定性、20分钟规则与原始帧时序。
- 5 项素材回归通过，包括原片/图集/小水泡哈希、原始完整时间轴及运行时 PNG 的无损转换。
- Xcode 26.2、Release、generic iphoneos 编译 App 和 Widget 成功；编译后确认 Widget 嵌入及游戏 manifest 随 App 复制。
- 只上传编译日志，没有生成或上传 IPA，没有启动模拟器。真机游戏、界面观感和20分钟性能仍未验收。

编译有项目既有竖屏方向警告，不阻断构建。初次运行因新增错误处理变量重名失败，修正后以上最终源码成功；中途取消的运行不计通过。后续若只补交接记录，不混用为新功能代码已重新验收。

重启前家中已有的两份未提交文档修改仍保留在工作区，本轮没有覆盖或代为提交：`docs/GAME_VIDEO_ASSET_GUIDE_2026-10-31.md`、`docs/SURVIVOR_GAME_CONCEPT_2026-10-31.md`。游戏新增代码、正式素材和本记录已推送 `codex/chat-media-tools`。
