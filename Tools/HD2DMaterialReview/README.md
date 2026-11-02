# HD-2D素材审阅网页

从仓库根目录运行 `python -m http.server 8768 --bind 127.0.0.1`，打开 `http://127.0.0.1:8768/Tools/HD2DMaterialReview/`。仅使用静态文件，无需npm安装。必须从仓库根目录提供HTTP服务，才能访问../../Art中的来源包；不要直接双击HTML或只把本文件夹单独作为服务器根目录。

线上同一网站：https://maiverse-fireball-hd2d-20261102.blithebough2.chatgpt.site

四项技能1—5级与20种怪物的行走/攻击施法/简短死亡都在此。母版、原图、实际提示词与脚本位于Art/HD2DReview/2026-11-02。网页小人物图集是显示派生图，正式人物素材请用人物v4母版包，不要把64×72缩略图当原分辨率。

网页演示没有接入App/SpriteKit，也不是模拟器或手机实机截图。详细接续状态见docs/HANDOFF_2026-11-02_HD2D.md。


## 拉取后的大文件还原

为避免当前网络大文件POST超时，超过2 MiB的来源包/源视频/参考图按1 MiB无损分片提交Git。先在仓库根目录运行 `python Tools/HD2DMaterialReview/restore_sources.py`，再打开网页或解压来源包；只需Python标准库。source-parts.json包含完整文件与每个分片的SHA256，脚本会逐片和整包校验，遇到已存在但内容不同的文件会保留它并报错，不覆盖用户文件。`--check-parts`只核验全部分片拼回的哈希而不写文件。还原后的文件与办公室确认稿逐字节相同，不重新生成或重新压缩。
