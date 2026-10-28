> 新取帧规则：当前遛狗保留 1.6 秒；后续视频必须完整取帧、保留原时序，上限 20 秒。详见 [视频取帧要求](VIDEO_FRAME_EXTRACTION_RULES.md)。下文挑短循环的做法仅为本次已确认素材的历史过程。

> 最新状态与回家继续入口：请先读 [当日最新交接](HANDOFF_2026-10-28_EVENING.md)。下文保留历史过程，旧恢复路径和未集成状态已被正式图集、build 15 交付及本轮角色动作改造覆盖。

# 大肥鱼遛狗：改用 AI 视频提帧的本地试验

用户否决继续用现有腿部骨架试稿制作步态，改为：由 Codex 制作视频首帧，用户在即梦生成动画，再由 Codex 提帧、去底和整理。v14 不作为已通过动作，未接入 App。

## 首帧与输入

- 首帧由内置 image_gen 生成，保存在 `output/jimeng-dafeiyu-firstframe/dafeiyu-dog-firstframe-v1.png`；完整提示词为同目录 `prompt-used.txt`。
- 用户视频：`E:/素材测试/大肥鱼遛狗.mp4`，12,696,060 字节，SHA256 `ed9d1cc82267c4157962756e900c8736d051e7db50df80c83a912141bcd6e3b8`。原视频未修改。
- 视频为 1280×720，解码 300 帧，帧间隔主要为 1/60 秒；前段含一个 1/30 秒间隔，因此容器平均帧率约 59.80。解码视频跨度约 5.017 秒，容器还带音轨；本次预览不含音频。

## 当前输出

目录 `output/ai-video-dafeiyu-walk-v1/`：

- `frames-source-rgba/`：300 张完整分辨率 RGBA，保留全部解码姿势。
- `frames-loop-rgba/`：源帧 49–144（从 0 开始，末端 145 不包含），96 张、60 FPS、1.6 秒的循环候选；统一裁剪区域 `[129,0,1155,709]`，固定画布 1026×709。
- `full-keyed-review.mp4`：全片去绿底后放在棋盘格上检查边缘，301 个显示帧，保留原视频中额外的一次停留；没有生成中间姿势。
- `loop-keyed-review.mp4`：循环候选重复四次，384 帧、6.4 秒、60 FPS，深色背景。
- `dafeiyu-dog-loop-transparent.webp`：96 帧真正透明的动画 WebP，整数毫秒时序累计 1600 毫秒。
- `dafeiyu-dog-loop-pngs.zip`：96 张透明 PNG 和 manifest，ZIP CRC 检查通过。
- `manifest.json`、`extraction-analysis.json`：原视频哈希、时间戳、帧映射、裁剪、候选接缝评分和导出结果。
- `loop-seam-review.png`：源帧 143、144、49、50 的接缝对照；`keyed-poster.png` 为预览海报。

## 处理方法与限制

脚本 `Scripts/extract_ai_walk_video.py` 从视频解码，用非绿前景核心和最近前景颜色估计做绿幕边缘解混，过滤小型离散压缩色块。没有重画人物，没有骨骼变形、光流补帧或动作重建。

`Scripts/preview_extracted_ai_walk.py` 使用整段共享的外接区域裁剪，不按每帧外接框重新居中，以免把步态摆动变成位置抖动。源视频的轻微重心变化保留。视频均已完整回解；透明 WebP 帧数和 RGBA 模式检查通过；源文件哈希在结束时再次核对。

**当前仅证明提帧、绿底处理和透明输出流程可用。循环候选尚未获用户验收，不是已通过的无缝动画。** 手臂、发梢和服饰在源视频中并非严格周期，硬切循环仍可能看到接缝。边缘应继续在深浅背景、实际显示尺寸下审阅。源视频中的步态、形体变化不会因截帧自动修好。

另将源帧 49 的原绿底与去底鞋部进行并排核对（`feet-source-key-comparison.png`）：换腿经过时的鞋子轮廓重叠、模糊在原视频中已经存在，不能说是去底修好了。当前没有额外补画或消除这部分源视频重影。

本轮未上传 Git、未覆盖旧素材、未修改 App/Widget、未生成 IPA。当前动画源归档仍为之前版本，不包含这些本地视频提帧输出。

## 用户认可动作后的 v2 边缘修订

用户反馈“这个没啥问题了”，但明确指出人物与狗仍有绿边。保持已审阅的源帧 49–144、96 帧、1.6 秒、裁剪和时间轴，停止调整步态，只修透明边缘。

新增 `Scripts/refine_ai_walk_edges.py`，从 v1 的 RGBA 做选择性轮廓去色，并轻微收紧低透明度色晕；同时压制前一次去混色产生的异常紫边。头发和牵引绳内部的正常青蓝色保留。输出为 `output/ai-video-dafeiyu-walk-v2/`，v1 保留作比较。

全部 300 帧已核对不透明像素覆盖位置不变、可见像素红蓝通道不变；绿色占优像素（G 超过 max(R,B)+2，Alpha>24）合计由 544531 降至 0。该统计仅表示指定色彩条件，不替代观感验收。已放大发丝、牵引绳、鞋袜、狗耳朵和脚掌在深浅背景上的对照，见 `edge-comparison.png`。新版本沿用两段预览、透明 WebP 和 96 张透明 PNG ZIP 的文件名，路径改在 v2 目录。

用户当前已认可动作；v2 边缘处理仍待用户看新预览确认。没有把本轮描述为重新设计步态，也没有接入 App 或生成 IPA。

## v3：用户指出 v2 仍像绿色描边，修正轮廓覆盖

v2 的“绿色占优像素为零”不代表绿幕污染已经从视觉上消失。用户再次指出发绿描边；用原尺寸 64×64 区域放大 6 倍、分别合成近黑与近白背景检查后，确认 v2 保留了带青色的原外轮廓，只调绿色通道不足以解决。

新增 `Scripts/remove_ai_video_outline_fringe.py`，从 v2 的透明帧处理中移除约 1.25 个源像素的污染轮廓覆盖，并从剩余不透明邻域重建半透明边缘颜色。此次有意允许去掉污染的不透明外沿，不能继续用“所有不透明像素必须保留”作为约束。深处内部纹理核对不变，动作、帧范围、画布、位置和时间轴不变。

鞋子轮廓内侧另有压缩带来的暗青色污染，增加窄边缘区域的暗色去污染，使原海军蓝鞋边回到蓝色；亮青发丝与牵引绳内部不做该暗色校正。距原轮廓 8 像素以外的内部区域逐像素核对不变。

输出目录 `output/ai-video-dafeiyu-walk-v3/`。放大对照为 `contour-6x-comparison.png`；300 帧的边缘记录为 `edge-verification.json`。对整段检查，未发现原本连接的牵引绳因本轮处理而断开；按 Alpha 总量计算，覆盖面积减少约 3.04–3.56%，主要为外轮廓。已通过 6 倍深浅背景对照确认鞋底、发丝、绳子、狗耳与脚外沿的污染边有实质减少，不再仅依据色彩统计宣布完成。

沿用源帧 49–144 的循环，重导出透明 PNG/WebP 和预览；仍未上传 Git 或接入 App。v1/v2 保留供比较，本轮以 v3 为最新边缘处理稿。

当时从导出的 v2/v3 MP4 各解码首帧放大 8 倍，认为抽样位置的描边已改善；两段视频回解与 ZIP CRC 通过，但这些检查没有证明连续播放自然。**用户随后明确否决 v3：残绿仍在，轮廓出现波浪，更丑。之前“已修复”的结论不成立。v3 不作为正式或已通过的素材。**

## v4：回到原视频，分开求透明遮罩与前景颜色

用户提供 `yshuang722-spec/xiaoxiao-zhuochong` 作为对照。读过其 `scripts/chroma_step02.py`、`scripts/pr_import_step02.py` 和 `docs/UPSTREAM_README.md`：自动 HSV 方案是备选，上游说明明确记载其原项目成品使用 PR 手工抠像。不能据此断言该分支所有后加动作均为 PR，也不能冒称本机在使用 PR。

用户授权再次尝试后，新增 `Scripts/matte_ai_walk_video.py`：直接读取原 MP4，使用 PyMatting 的 closed-form alpha 求解与 multilevel foreground estimation，分别求透明度和前景色。腐蚀/膨胀只用于确定哪些像素是可信前景/背景，**不直接用作最终轮廓，也不继续收缩轮廓或用最近邻像素替换边缘颜色**。

为减少逐帧跳动，使用相邻原视频帧的光流对齐 alpha，按原图颜色一致性加权做轻量稳定；只作用于不确定的透明边缘，冻结可信前景与背景。光流没有用于生成图像、腿或中间动作。首次连续帧检查发现发丝狭缝中的纯绿被当作前景，已增加画面内部的纯绿背景锚点并重算；不是靠削去发丝解决。

进一步抽查源帧 86，发现狭缝经视频压缩后不一定仍是纯绿色，因此将角色不存在的高置信绿色色相也作为背景锚点；同时用高置信深蓝像素保护细发丝和头顶呆毛，防止几何种子缺少前景点导致细线消失。先在源帧 84–91 的邻域重算并检查，才更新整段。最终缓存标记为 `trimap-v4`，旧缓存不代表最终结果。

当前处理源帧 49–144，另读前后相邻帧作稳定参考。输出 `output/ai-video-dafeiyu-walk-v4/`：96 帧、1.6 秒循环，沿用原裁剪与位置，原视频不变。由 `Scripts/preview_matted_ai_walk.py` 打包，包含四种背景下的循环、v3/v4 鞋边与绳子动态对照、透明 PNG ZIP 和透明 WebP。**属于重新抠像的候选版，仍待用户审阅；没有声称达到 PR 人工逐帧精修效果。**

新依赖仅安装到工作区外层 `tools/python-matting/`：PyMatting 1.1.16、NumPy 2.5.4、Pillow 13.0.0、SciPy 1.18.1、Numba 0.68.1、llvmlite 0.50.0；原 OpenCV 保存在 `tools/python-animation/`。运行抠像时先将新依赖目录加入 PYTHONPATH，Numba/OpenBLAS 线程设为 4。由于本机受限进程读取这批依赖受阻，计算使用已授权的进程；未修改系统 Python、未安装 PR 或剪映。

最终导出的两段 MP4 均完整回解 384 帧，透明 WebP 为 96 帧，PNG ZIP CRC 通过，全部 96 帧在固定裁剪外没有可见内容，牵引绳连接检查均通过，原视频 SHA256 不变。另从最终 MP4 解码源相位 73、86、121 的黑白背景对照，保存 `encoded-background-contact.png` 并查看；解码源相位 73–80 的连续鞋部近景，保存 `encoded-consecutive-feet.png` 并查看。检查覆盖连续帧和多背景，但仍不将其等同于用户动态观感通过。

算法与接口来源：[PyMatting alpha 文档](https://pymatting.github.io/alpha.html)、[foreground 文档](https://pymatting.github.io/foreground.html)。原画和动作保持用户的视频来源；新试稿未上传 Git、未接入 App、未生成 IPA。

## v4 用户验收与小白下一步

用户看完 v4 后明确回复“这个可以 没问题”，认可当前大肥鱼遛狗的动作和边缘观感；v4 为当前已获用户认可的提帧抠像版本。保留现有导出内容，尚未接入 App。

下一步由本助手生成“小白遛小龙”绿幕首帧，用户在即梦生成视频，再由本助手提帧与抠像。新首帧位于 `output/jimeng-xiaobai-firstframe/xiaobai-dragon-firstframe-v1.png`，详细图生视频提示词位于同目录 `即梦视频提示词.txt`，图片生成提示词为 `prompt-used.txt`。使用内置 image_gen，并保留默认目录原图。角色以 `Art/xiaobai-chibi-v2.png` 为准，等待动作图仅提供幼龙及长牵引绳参考，不使用旧失败腿部动画。

提示词明确慢速自然交替迈步、轻微重心起伏、同步渐变眨眼、含蓄表情与看向小龙、长裙分层和饰品惯性、头发与尾巴跟随、四足幼龙步态、长绳持续连接、固定机位纯绿幕。尚未收到小白新视频，首帧不能代替视频动作验收。本轮未上传 Git、未接入 App、未生成 IPA。

## 本机复现

**后续状态覆盖：用户取消小白遛龙，并要求提交及准备 IPA，明确批准删除 3414 个旧文件。大肥鱼遛狗 v4 与先前确认的御剑/骑鲸已迁入 `Art/DailyMotions/` 并接入运行时；旧恢复归档、失败试稿、重复预览和小白首帧已删除。本文件以下及早期段落保留为历史过程，当前资源与验证状态以 `docs/RELEASE_BUILD15.md` 为准。**

小白首帧纠错：用户指出 v1 幼龙额头/鼻梁多出一只角，该检查遗漏已确认。通过内置 image_gen 局部编辑去除多余角，输出 `output/jimeng-xiaobai-firstframe/xiaobai-dragon-firstframe-v2.png`。查看结果，幼龙保留头顶一对角，额头至鼻梁轮廓圆滑。v1 保留作历史但不再用于视频生成；同目录视频提示词已改用 v2，并增加“幼龙只有头顶一对角，额头和鼻梁不长第三只角”的约束。未生成视频，未接入 App，未上传 Git。

设置 `PYTHONPATH=E:/ai_workspace/ios_ldd/tools/python-animation`，`DRAGON_FFMPEG` 指向该目录中 `imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe`，使用带 Pillow、NumPy 的 Python。依赖 OpenCV，输出使用独立 FFmpeg 的 libx264，不依赖剪映。

在仓库根目录执行：

```powershell
python Scripts/extract_ai_walk_video.py 'E:/素材测试/大肥鱼遛狗.mp4' output/ai-video-dafeiyu-walk-v1
python Scripts/preview_extracted_ai_walk.py output/ai-video-dafeiyu-walk-v1 --start 49 --end 145
```
