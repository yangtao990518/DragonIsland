# 小白立绘处理记录

立绘使用内置 ImageGen 的背景移除模式生成透明 PNG，没有使用 CLI 或 API Key。以下为原始立绘处理记录；V1.4 新 Q 版见文末，旧 Q 版继续保留。

- 用户提供的原始立绘：`Art/xiaobai-standing-original.png`。
- 用于 App 和实时活动的透明立绘：`Art/xiaobai-standing.png`。
- 旧版日常 Q 版素材：`Art/dragon-original.png`（V1.4 起作为备份）。
- 两套素材的尺寸资源由 `Scripts/prepare_assets.py` 生成到各自的 imageset。

处理提示词如下，目标是移除外部白底、保留角色白色细节与原形象。生成式抠图的细微边缘变化不代表原图完全逐像素保持。

```text
Use case: background-extraction. Edit target: the provided full-body white-haired lavender-eyed dragon woman illustration. Prepare a clean transparent PNG cutout for an iPhone character companion app. Remove ONLY the outside white background and white negative space between the silhouette's limbs, hair, wings and tail. Preserve the same character identity, pose, expression, outfit, full body from horn tips to shoes, white dragon horns, white long hair, lavender eyes, pointed ears, white and lavender dress, white-edged lavender dragon wings and white scaled tail. Preserve all white details within the character; they are NOT background. Do not redesign, repaint, change the style, recolor, add details, or crop away the horns/wings/tail/feet. No text, no shadows, no white rectangle, no checkerboard pattern: actual alpha transparency around the figure. Keep the entire single character centered with a little transparent padding.
```

## V1.2 桌面图标与看图资源

- 用户指定原图目录为 `D:\gpt_workspace\ios_ldd\mAIverse_5_icons_4K`，包含 GPT、Claude、DeepSeek、Gemini、Grok 五款 4096×4096 PNG。
- 仅按比例缩小、转换为不透明 RGB 并保存到 `Art/AppIcons/`；没有重新生成图案。资源脚本据此生成默认 GPT 图标、四款备用图标及选择界面的缩略图。
- Q 版看图使用独立的高分辨率 `XiaobaiChibiDetail` 资源，避免把灵动岛的小尺寸资源直接放大。详情大图与岛上小图仍来自同一张原图。

## V1.4 新 Q 版与动作

- 当前母图为 `Art/xiaobai-chibi-v2.png`，1122×1402 RGBA。角色目录 `chibiSource` 已更新，头像、卡片、详情大图与静态岛上小图由此生成；大图没有使用 512×640 动作帧放大替代。
- `Art/MotionV2/frames/` 包含待机、左右走、打滚、转身共 36 个透明 PNG 帧文件，共用中立端点包含在计数内。时长、首尾帧索引见 `manifest.json`，完整生成提示词见同目录提示词文件。
- 步行包含抬腿与重心变化，打滚包含蹲下、蜷身、倒转和起身；源文件及预览另存本机 `mAIverse_DragonGirl_Animation_Assets_V2`，没有覆盖用户输入素材。
- `Scripts/prepare_motion.py` 生成共享 imageset、60 秒播放计划与彩色字体，字体重复帧采用引用去重；App 预览和 Widget 使用同一套帧与计划。素材由 ImageGen 绘制后确定性切分、统一画布与透明边缘，没有把简单图片旋转称为补画。
- 母图已更新为白紫造型、两只白角、小握拳。发梢与衣纹仍有轻微生成差异，不声称所有帧逐像素一致。大立绘继续使用原已确认版本。

## V1.5 左右走路替换

`Art/MotionV3/` 保存两套独立生成的 4×4 步行图集、各 16 个透明帧和全部提示词。`Scripts/import_walk_v3.py` 确定性切分、移除邻格孤立碎片并按统一比例 / 地面线打包，需要本地 Pillow 和 NumPy；构建直接消费已提交帧，不需要运行切图脚本。待机、打滚、转身引用 V2，主静态母图与大立绘保留。播放代码以 30fps 采样，岛上字体使用 96 像素黑色不透明底面防旧姿势透出，App 中的帧仍保留透明。
