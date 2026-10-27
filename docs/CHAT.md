# 聊天功能

基于 `codex/character-voice-alarms` 的 V1.8 / build 14 增加聊天，开发分支为 `codex/character-chat`。本次不更新版本号、不生成或发布 IPA。

## 用户功能

- 底部新增「聊天」，可以选择人物进行单聊。同一角色会继续已有单聊，不重复建立会话。
- 支持创建群组、修改群名、添加和移除角色。用户自动成为成员；当前只有小白时，可建立「我 + 小白」的群组。
- 群组每一轮由所有已选角色分别回复，显示各自头像、姓名及时间。单聊和群聊的固定回复均为 **聊天功能测试中**。
- 会话列表按最近消息排序，支持搜索角色、群名、最近消息，以及删除会话。
- 聊天窗口支持多行文字、复制、回复中提示、清空记录、删除聊天，空白消息和超过 4000 字的消息不能发送。
- 会话、成员、消息和草稿保存在本机。退出聊天或进入后台时保存草稿，重启后可继续查看记录；删除 App 会删除本机数据。
- 回复中途被打断后，显示重试入口。群聊重试只补齐尚未回复的角色，不重复已经完成的回复；删除会话会取消正在等待的回复。
- 角色列表来自现有 `CharacterCatalog` / `Characters.json`，没有另建仅含小白的聊天角色名单。未来加角色时不必修改聊天页面。
- 底部保留五个直接可见入口：我的世界、角色、聊天、闹钟、关于。原「任务」中的走路、打滚及自动活动设置迁至「我的世界 → 日常动作」，陪伴卡片内的「挑选自动动作」仍可使用。

## 代码与 AI 扩展

- `Shared/Models/Chat.swift`：会话、消息、发送校验、持久化文件、回复请求和 `ChatReplyProvider` 协议。
- `Shared/Models/ChatStore.swift`：主线程会话管理、逐个角色异步回复、持久化、取消与重试。使用 Combine，在 App / macOS 单元测试可用；无 Combine 的平台跳过该文件的实现。
- `App/ChatViews.swift`：会话列表、角色选择、群组编辑、聊天窗口与消息气泡。
- `App/ContentView.swift`：聊天入口与日常动作入口调整。

默认注入 `TestChatReplyProvider`，无外部请求、无账号或 API Key。后续实现 `ChatReplyProvider.reply(to:)` 并注入 `ChatStore` 即可替换回复来源；请求提供会话 ID、单聊/群聊类型、群名、此次轮次的角色、当前回复角色、触发消息及截至该条消息的历史。以后增加流式输出需要扩展协议及消息更新逻辑，当前未实现流式 AI、语音聊天、跨设备同步或真人群聊。

历史存储在 App 的 Application Support 下 `Chat/history.json`，包含版本号并采用原子写入。读取失败或格式版本不受支持时保留原文件，禁用新建和发送，并提供重读入口。聊天记录独立于现有陪伴状态、动作设置及闹钟状态。

## 验证

新增 10 个聊天领域测试、6 个会话管理测试、2 个界面流程测试：

- 单聊去重、不同角色隔离、群组成员去重和名称校验。
- 多行文字、4000 字上限、空白和不可用角色校验，回复期间禁止重复发送。
- 群成员各回复一次、部分回复重试、重试上下文不混入之后发送的消息。
- JSON 往返保存、草稿恢复、损坏文件保留、不支持的格式版本。
- 失败后重试、删除时取消任务且不恢复已删除会话、群名/成员编辑、清空记录。
- 界面建立单聊和群聊、固定回复、重新进入原会话、重启恢复、群组改名和清空。

2026-10-27 已在 [GitHub Actions 40448657287](https://github.com/yangtao990518/DragonIsland/actions/runs/40448657287) 完成真实验证，整体结果 **success**。验证源码为 `ddc7f96e46c5bffeda3dd231817cd1c70ad9a31e`，环境为 macOS 15、Xcode 26.2、iPhone 16 Pro / iOS 26.2 模拟器。

- 全部 40 项 Swift 单元测试通过，其中包含新增的 16 项聊天领域和会话管理测试。
- App、Widget、界面测试程序编译通过。
- 两条聊天界面流程通过：单聊发送/回复、重启恢复、再次选择同一角色复用会话；群组创建、发送/回复、管理、改名保留消息和清空记录。
- 本机另已完成全部 41 个 Swift 文件的语法树检查，以及原有走路、打滚资源的 14 项 Python 回归测试。

真实截图共八张：角色选择、会话列表、恢复后的单聊回复、群组创建、群聊回复、成员管理、改名及清空。均来自 XCTest 的 `XCTAttachment(screenshot:)`，由 xcresult 导出；测试输入和群名使用英文，角色的测试回复为中文。可在本次运行的 `chat-test-screenshots-and-logs` artifact 下载原图和日志，本地保存于 `output/chat-verification/screenshots/`，验证摘要为 `output/chat-verification/VERIFICATION.json`。

`.github/workflows/chat-checks.yml` 明确启动 iOS 26.2 模拟器后，分别编译和执行界面用例，并保留截图及日志，不生成或上传 IPA。此验证覆盖模拟器中的聊天流程，未做新版本真机安装或 AI 联网验证。

用户已授权仓库持续保持公开，之后由用户自行改回私有；本任务不自动恢复私有。

可运行检查的 macOS 环境：

```sh
swift test
python3 -m venv .asset-venv
.asset-venv/bin/python -m pip install -r requirements-build.txt
.asset-venv/bin/python Scripts/prepare_assets.py
.asset-venv/bin/python Scripts/prepare_motion.py
xcodegen generate --spec project.yml
xcodebuild -project DragonIsland.xcodeproj -scheme DragonIsland \
  -destination 'platform=iOS Simulator,name=<本机可用的 iPhone 模拟器名称>' \
  -only-testing:DragonInterfaceTests/ChatInterfaceTests \
  CODE_SIGNING_ALLOWED=NO test
```

界面测试使用 DEBUG 专用 `--chat-test-store <UUID>` 将记录写入单独的测试目录；重启沿用相同参数，正常用户数据不受影响。Release 不启用这个入口。

人工验收：打开聊天选小白发送文字，收到固定回复；返回再选小白应继续同一会话；建立群组、发送、改名、退出重进；返回或切后台后草稿保留；重启后历史仍在；确认「我的世界 → 日常动作」及原有闹钟入口正常。
