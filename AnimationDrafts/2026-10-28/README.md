# 2026-10-28 本地步态修订归档

**当前 v13 被用户反馈步幅仍太小，需继续改造，尚未集成。** 本轮虽将人物与宠物的前后行程增加约三成，并调整衣服下的髋部连接点，但未获通过。下次先读 [今日交接](../../docs/HANDOFF_2026-10-28.md) 和 [步态审阅记录](../../docs/PET_WALK_REVIEW_2026-10-28.md)。第一批御剑/骑鲸 revision3 与原 10 月 27 日归档保留。

- [完整人物与宠物，60fps](previews/pet-walk-full-v13.mp4)
- [人物腿部与鞋袜，60fps](previews/human-feet-v13.mp4)
- [宠物四肢，60fps](previews/pet-feet-v13.mp4)

以上每个预览为 6.4 秒、384 帧。当前 v13 保存 RGBA 透明帧，但仍只用于本地审阅，尚未制作 App 的正式资源与时间轴。正常速度回放还未验收；之前的本地浏览器预览地址被权限检查拒绝，本轮未重试该操作；用户可直接打开本地视频文件检查。用户确认后才能开始集成。

先恢复 [10 月 27 日基础归档](../2026-10-27/README.md)，再在仓库根目录执行：

```powershell
python AnimationDrafts/2026-10-28/restore.py
python AnimationDrafts/2026-10-28/restore.py --verify-only
```

最新 `sources-v13.zip` 保存生成原图、完整提示词、姿势草图、v13 帧与关节数据以及脚本快照。逐项记录 SHA256，ZIP 有 CRC 验证，恢复时保留不同内容的本地文件并报告冲突。`sources-v12.zip` 与 `manifest-v12.json` 保留上轮试稿；`sources.zip` 与 `manifest-v11.json` 是旧 v11 归档（含 v10 宠物补帧依赖）。不会删除其他试稿。失败预览仍留在原本机输出目录，不作为正式完成结果。

本机脚本使用工作区外层 `tools/animation-env.ps1` 设置 D: 临时目录与缓存。运行需要 Python、Pillow、NumPy、可用 libx264 的 FFmpeg；透明边缘整理使用工作区外层 `tools/python-animation/` 中的 OpenCV。v13 不运行 RIFE。若仅为复现旧版神经补帧试验，`Scripts/fetch_animation_rife.py` 可下载官方便携文件。这些环境依赖、GPU 驱动和缓存不进源归档。

当前分支仍为 `codex/character-chat`，基于 `bafc996f`。本次按用户要求提交保存；无 IPA，无 App/Widget 改动，无正式素材清理。提交与远端同步状态以 Git 记录为准，不能把提交等同于动作验收。
