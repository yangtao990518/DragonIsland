# 已确认HD-2D素材来源与交接

仅保留确认的人物v4、四项技能、20怪物行走与攻击施法/死亡包，不收录否决的旧眼部/整身重排预览。SourceBundles可直接解压取得透明帧、图集、原画、提示词、时序与哈希。SourcesVideos原始双人视频只作来源保存，正常接入不必重新抠像。

processing是现有处理脚本快照，包含办公室绝对路径，运行前需按接续机器修改。依赖Python、NumPy、Pillow，以及人物抠像的OpenCV、PyMatting、FFmpeg；部分脚本引用generate2dsprite技能里的背景处理函数，也需调整到接续电脑安装位置。下载/接入确认图集无需安装这些重处理依赖。不能把脚本路径未修改的运行失败当成已交付透明素材丢失。

网站源码在Tools/HD2DMaterialReview。qa里的PNG是网页审阅，原生游戏的上午测试另见docs/GAME_FEEDBACK_2026-11-02.md；下午像素素材尚未替换原生游戏。详见docs/HANDOFF_2026-11-02_HD2D.md。


## 拉取后的大文件还原

为避免当前网络大文件POST超时，超过2 MiB的来源包/源视频/参考图按1 MiB无损分片提交Git。先在仓库根目录运行 `python Tools/HD2DMaterialReview/restore_sources.py`，再打开网页或解压来源包；只需Python标准库。source-parts.json包含完整文件与每个分片的SHA256，脚本会逐片和整包校验，遇到已存在但内容不同的文件会保留它并报错，不覆盖用户文件。`--check-parts`只核验全部分片拼回的哈希而不写文件。还原后的文件与办公室确认稿逐字节相同，不重新生成或重新压缩。
