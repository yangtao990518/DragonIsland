# 小白立绘处理记录

本次使用内置 ImageGen 的背景移除模式生成透明 PNG，没有使用 CLI 或 API Key。Q 版原素材继续保留。

- 用户提供的原始立绘：`Art/xiaobai-standing-original.png`。
- 用于 App 和实时活动的透明立绘：`Art/xiaobai-standing.png`。
- 日常 Q 版素材：`Art/dragon-original.png`。
- 两套素材的尺寸资源由 `Scripts/prepare_assets.py` 生成到各自的 imageset。

处理提示词如下，目标是移除外部白底、保留角色白色细节与原形象。生成式抠图的细微边缘变化不代表原图完全逐像素保持。

```text
Use case: background-extraction. Edit target: the provided full-body white-haired lavender-eyed dragon woman illustration. Prepare a clean transparent PNG cutout for an iPhone character companion app. Remove ONLY the outside white background and white negative space between the silhouette's limbs, hair, wings and tail. Preserve the same character identity, pose, expression, outfit, full body from horn tips to shoes, white dragon horns, white long hair, lavender eyes, pointed ears, white and lavender dress, white-edged lavender dragon wings and white scaled tail. Preserve all white details within the character; they are NOT background. Do not redesign, repaint, change the style, recolor, add details, or crop away the horns/wings/tail/feet. No text, no shadows, no white rectangle, no checkerboard pattern: actual alpha transparency around the figure. Keep the entire single character centered with a little transparent padding.
```
