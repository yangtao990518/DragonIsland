# mAIverse 角色配置

角色目录是 `Shared/Resources/Characters.json`。App 与 Widget 都读取它，避免在各处分别写死角色名称、头像或立绘。当前只有小白；未来增加角色时，在目录中增加条目、放入对应素材、重新编译即可。

每个条目包含稳定的 `id`、名称、介绍、来源说明和三种资源：

- `chibiAsset` / `chibiSource`：日常灵动岛紧凑态、最小态使用的 Q 版小人物。
- `portraitAsset` / `standingSource`：展开态和锁屏使用的透明背景立绘。
- `heroAsset`：主界面和角色页的大尺寸立绘，由同一个 `standingSource` 等比生成。

原始素材放在 `Art/`，资源由 `python3 Scripts/prepare_assets.py` 生成。每个角色的资源名称应各不相同，立绘必须带透明 alpha；图片会等比放入目标画布，不拉伸人物。Widget 只打包适合实时活动尺寸的共享资源，大图只进入 App。

V1.4 小白的 `chibiSource` 为 `Art/xiaobai-chibi-v2.png`。自动动作另由 `Scripts/prepare_motion.py` 编译到两端；当前仅小白具有动作计划，其他角色默认静态。新增角色的卡片不等于已有动作，后续需补对应帧、计划和字体注册资源。

用户选中的角色保存在本机。开始陪伴时把 `characterID` 写入 ActivityAttributes，本轮活动绑定该角色，重新打开 App 时从活动恢复；陪伴期间不切换角色，避免主 App 和灵动岛显示不同人物。老版本没有 `characterID` 的活动会回退到小白。

当前互动仍是本地预设短句，没有 ChatGPT API、联网 AI 聊天或账号。新增角色不会自动获得模型对话能力。

展开态把立绘放在文字和按钮旁边，而不是把按钮另起一行堆在图片下面；图片区高度 88pt，按钮高度 28pt，并在底部留出 8pt。苹果说明实时活动超过 160pt 可能被裁切，具体设备的系统边距与最终显示仍需安装验证。

参考：[Apple — Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)。
