# 2026-10-27 动作与验证资料

完整交接：[HANDOFF_2026-10-27.md](../../docs/HANDOFF_2026-10-27.md)。本目录为开发归档，不在 App/Widget 的资源构建路径内。

**状态：第一批御剑/骑鲸的眨眼修正版已获用户确认；第二批遛小龙/遛小狗的走路仍未通过。最新问题是小白裙子穿模、迈步后腿抖、大肥鱼腿部接缝和步幅过小。不要把试稿直接集成。**

后续本地修订见 [2026-10-28 交接](../../docs/HANDOFF_2026-10-28.md)、[审阅记录](../../docs/PET_WALK_REVIEW_2026-10-28.md) 与 [新素材归档](../2026-10-28/README.md)。v4/v5 被用户否决，v6–v11 也未通过；v12、v13 仍被反馈步幅太小，需要继续改造，不能集成。本目录原始分卷、预览与反馈截图保留作对照。

## 只看最新预览

- [第一批：御剑与骑鲸鱼，眨眼 v3](previews/ride-batch1-blink-v3.mp4)
- [第二批：当前完整人物走路](previews/pet-walk-full-60fps.mp4)
- [第二批：当前脚部放大](previews/pet-walk-feet-60fps.mp4)
- [用户最后指出问题的截图](evidence/latest-user-feedback.png)

这些视频都是已有回放，没有为了交接重新修改动作。旧版本 MP4、GIF 不再上传；历史 README 中提到的旧预览路径可能因此不存在，以这里为准。

## 回家恢复资料

在仓库根目录执行：

```sh
python AnimationDrafts/2026-10-27/restore.py
```

Windows 也可以使用 `py`。无需安装第三方包。它验证每个 ZIP 的 SHA256/CRC、每个原始文件的 SHA256 和最新视频哈希，然后恢复原 `output/` 相对目录。相同内容只归档一份，manifest 记下全部原路径；分卷是彼此独立的普通 ZIP，恢复脚本按索引重建目录。

```sh
python AnimationDrafts/2026-10-27/restore.py --verify-only
python AnimationDrafts/2026-10-27/restore.py --destination /path/to/repository
```

遇到同名而内容不同的本地文件，默认保留本地修改并报告冲突；先核对，确定需要替换才使用 `--overwrite`。脚本不会删除多余文件。恢复后的 `output/` 仍被 gitignore 忽略，原归档是本次搬运的持久副本。

## 保存了什么

- `output/chat-verification/`：今天聊天测试的截图、日志与摘要。
- `output/dafeiyu/`：角色素材处理、原图、切帧和最终模拟器取证。
- `output/ride-batch1/`：第一批原图、透明切帧、眨眼原始版及 revision2/3 的图层、脚本和检查记录。
- `output/pet-walk-batch2/`：第二批长绳原图、透明帧、眼层，gait-revision、walk-rig-v2、walk-rig-v3-stable 的贴图/网格脚本/帧/检查记录。所有失败试稿保留作依赖与问题对照，验收状态看交接文件。
- `output/animation-generated-sources/`：上述脚本/记录引用的生成原图备份（如可在本机找到），按原 `exec-*.png` 名保存；来源索引也在 manifest 中。

旧预览、Python 缓存与系统缓存不进入源归档，准确排除清单见 `manifest.json`。不搬运虚拟环境、生成字体、Apple 会话、证书私钥、密码或废弃技能特效。

## 脚本依赖与路径迁移

恢复 PNG/查看视频无需重跑处理器。继续改动画时需要 Python + Pillow + NumPy；导出视频还需本机可用的 ffmpeg，编码器应选本机支持的类型。历史处理脚本曾使用 `h264_nvenc`，不保证另一台电脑有同样的显卡/编码器。

历史脚本中 `GEN`、`FF`、`FONT`、`PROCESSOR` 等常量保留当时值，回家重跑须改为本机路径。`GEN` 可指向恢复后的 `output/animation-generated-sources/`；字体可换为可用中文字体；`PROCESSOR` 是本机 `generate2dsprite` 技能处理脚本，需在新工具环境提供同等的切帧/抠色能力。原画与处理结果均已保存，不必为了路径问题重新生成。

`ride-batch1/revision3/build.py` 会读取 `revision2/build.py` 和上级原始帧；`pet-walk-batch2/walk-rig-v3-stable/rig.py` 会读取 `walk-rig-v2` 的贴图与 `gait-revision` 的身体前景/裙衬。必须保留相邻目录。重新运行历史导出脚本会再生成旧预览，当前没有这样操作。

用户要求在正式改造完成后统一删除无用素材与预览。届时先确认运行时资源和脚本依赖已经迁出，再清理本目录、恢复后的试稿和对应索引；现在保留它们用于回家继续。
