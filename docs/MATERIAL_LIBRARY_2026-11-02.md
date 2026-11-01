# 2026-11-02 自制素材库备份与恢复

用户要求将自己制作的素材库上传，供公司电脑继续开发。独立备份入口：

[GitHub 素材备份](https://github.com/yangtao990518/DragonIsland/releases/tag/material-library-2026-11-02)

普通App构建仍直接使用仓库中的 `Art/SurvivorV3`，不要求下载这份约1.05 GB的创作库。备份不是新游戏版本，历史素材和暂停草稿不代表已经接入。

## 备份内容

| 文件 | 字节 | 内容 |
| --- | ---: | --- |
| LocalEffects-2026-11-02.zip | 126734843 | 技能JS源码、40级正式图集与JSON、13张V2图标原图、网页预览、视频预览、UI原型和历史草稿 |
| MonsterAssets-2026-11-02.zip | 906673483 | 20段最新骷髅的完整透明帧、图集、离体箭、原始解码帧、取帧/分离脚本、源图提示词、旧参考库和原有交付ZIP |
| MaterialSources-2026-11-02.zip | 13115898 | 两段骷髅完整原视频、原始交接和原始素材清单 |
| manifest.json | 2134596 | 7813个文件的相对路径、字节大小与SHA-256 |
| SHA256SUMS.txt | 289 | 三个ZIP的SHA-256 |

不上传本机工具二进制、node_modules、.git和缓存目录。工具路径需使用公司电脑实际目录。融合魔法继续暂停；水元素与其它Review草稿只备份，不自动进入正式技能清单。旧代码怪物、旧图标与静态候选仅为历史参考，不能替代最新视频骷髅。

## 恢复

将以上五个文件下载到D盘同一目录，例如 `D:/downloads/MaterialLibrary-2026-11-02`。在已拉取代码的仓库中执行：

```powershell
$env:TEMP='D:\tmp\Codex'
$env:TMP=$env:TEMP
python Scripts/restore_material_library.py --archives D:/downloads/MaterialLibrary-2026-11-02 --workspace D:/gpt_workspace/material-library-2026-11-02
```

`--workspace`请选择公司电脑的新目录。脚本先校验三个ZIP，再逐文件校验、恢复；已有文件相同则复用，不同则报错保留，避免覆盖本机工作。

恢复后入口：

- `LocalEffects/index.html`：玩家技能库。
- `MonsterAssets/index.html`：怪物素材总入口。
- `MonsterAssets/Video-Extract-V1/index.html`：最新透明骷髅预览。
- `MaterialSources/交接_技能与骷髅动画_2026-11-02.txt`：原始制作交接。
- `MaterialSources/portable-integration-catalog.json`：按本次恢复目录调整过路径的清单。
- `MaterialSources/portable-video-inputs.json`：指向备份内原视频的取帧输入。

原始清单和原始inputs.json保持原字节，仍包含家里旧绝对路径；不要直接照抄。原制作脚本中可能还有本机工具路径，重新生产前按公司环境调整。静态预览与已打包的源图集无需重做视频处理。

## ZIP校验

```text
e6fb605f85bf5f1db4dae30dab89e8bde8992ebeea615bfebdb024652903fc34  LocalEffects-2026-11-02.zip
0862bae863272504f8c7c3f28d71086d57700f08a1461e0e89e3f730f4df91f5  MonsterAssets-2026-11-02.zip
531982d7551d28f0d831f78116f2fc66a707b642456a9f566b4e877ae0bc9e4a  MaterialSources-2026-11-02.zip
```

上传状态、完整恢复实测结果与本次IPA结果在 `HANDOFF_2026-11-02_GAME_BUILD24.md` 记录，不以本文件中列出压缩包代替实际上传成功。
