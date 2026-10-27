# mAIverse · 我的 AI 小世界

> **2026-10-27 当前进度：**开发分支为 `codex/character-chat`，已加入单聊/群聊、大肥鱼和正常人物版头像；测试回复为“聊天功能测试中”，尚未接 AI。今日完整改动与待办见 [交接记录](docs/HANDOFF_2026-10-27.md)，原图/脚本及最新预览见 [动作资料归档](AnimationDrafts/2026-10-27/README.md)。御剑/骑鲸眨眼修正版已获确认；遛宠物步态仍有穿模、腿抖、接缝和步幅问题，未集成，不生成 IPA。

> 本分支为 **V1.8（build 14）角色语音闹钟**：在 V1.7 动作修复基础上加入 10 句小白语音、试听、角色独立定时及陪伴到点提醒。改动与验证状态见 [V1.8 清单](docs/RELEASE_V1.8.md)。V1.7 动作保持不变。

属于自己的 AI 角色小世界：让喜欢的角色在 iPhone 上陪伴你。当前有白紫色龙娘“小白”和活泼可爱的“大肥鱼”，角色目录支持继续扩展；单聊和群聊目前使用固定测试回复，没有调用 AI。SwiftUI 主 App + ActivityKit 实时活动 + WidgetKit 扩展。**Windows 用户通过 GitHub Actions 的 macOS runner 编译，无需本地 Mac。**

## 第一版做什么

- 使用本次确认的白角、紫瞳、白发、龙翼与鳞片尾巴角色；头像和全身形象均已打包。
- App 内有轻微上下浮动的待机效果，尊重系统“减弱动态效果”设置。
- 选择 1 / 25 / 50 / 120 分钟的一轮陪伴。
- 日常灵动岛紧凑态和最小态使用 Q 版小人物；长按展开和锁屏使用用户提供立绘的透明版本，主界面展示大尺寸立绘。
- 主 App 包含“我的世界 / 角色 / 聊天 / 闹钟 / 关于”；日常动作设置位于“我的世界”。提供日常、展开和锁屏预览，小白与大肥鱼均由统一角色目录驱动。
- 角色详情可设置一次性闹钟；陪伴开始前可开启到点语音。语音按角色筛选、试听并保存默认选择。iOS 26 及以上使用 AlarmKit，旧版使用受系统通知设置影响的通知提醒。
- V1.2 增加人物卡片与详情，Q 版和立绘分别支持全屏缩放、双击与拖动；详情可查看日常、展开与锁屏预览。
- V1.3 看图支持单击返回、未缩放时单指下滑关闭；放大后的拖动保留为查看图片，双击仍用于缩放。
- 主 App 可切换深色 / 白色背景并保存选择。关于页提供用户指定的五款桌面图标，默认 GPT 款。
- V1.4 接入新版 Q 版与待机、左右走、打滚素材；任务页可预览、勾选动作并保存。开始陪伴后回桌面自动播放，五秒一个时段，60 秒预排循环，开局选择两套种子之一；不需要点击动作按钮。
- 锁屏也有对应卡片；没有灵动岛的设备仍可测试锁屏实时活动。
- “招呼”轮换本地短句，“心情”切换三种状态，“结束”收起实时活动。
- 无联网、无账号、无 AI API 调用、无推送服务器。

## 先读清楚这三点

1. **当前分支版本为 mAIverse V1.8。** 主 App 和扩展均为 1.8（build 14）；本机交付使用独立目录 `D:\gpt_workspace\ios_ldd\mAIverse-V1.8\`，保留旧版目录。完整改动见[本版清单](docs/RELEASE_V1.8.md)，构建和模拟器验证不代替用户手机测试。
2. **自动动作采用系统计时字形 / 遮罩播放预排片段。** 当前 60 秒片段循环，开局选择两套种子之一；走路往返 20 秒、打滚往返 10 秒，不在中途打断。不靠后台常驻或每帧更新 Activity；30Hz 是目标采样频率，系统仍可能限帧，息屏低亮度与减弱动态时静态显示。
3. **签名必须保留 Widget 扩展。** 删除 `PlugIns/*.appex`、只签主程序，可能导致 App 可打开而灵动岛无内容。源代码不要求 App Groups、推送或 iCloud 权限，首次编译无需上传 Apple 证书。

## Windows：最快开始

1. 解压本工程，进入含 `project.yml`、`App`、`Shared`、`Widget` 的目录。
2. 登录 GitHub，新建一个空仓库，如 `DragonIsland`。公开仓库的标准 Actions runner 通常免费；私有仓库使用你的 Actions 配额。无需添加 Apple ID、密码或证书到仓库。
3. 在仓库选择 **Add file → Upload files**，上传这个目录里的所有内容，**包括 `.github/workflows/build-ios.yml`**。不要只上传整个 ZIP，也不要多套一层 `DragonIsland` 目录。
4. 提交到 `main` 后自动触发编译。或进入 **Actions → Build iOS IPA → Run workflow** 手动运行。
5. 等待绿色成功标志，进入该次运行，滚到 **Artifacts**，下载带版本号的 **mAIverse-V1.8-unsigned**（后续版本会相应更新）。
6. 解压下载到的 ZIP，里面才是 `mAIverse-V1.8-unsigned.ipa`、安装说明和 SHA-256 校验文件。
7. 按 [Windows 签名安装说明](docs/WINDOWS_INSTALL.md)给 IPA 及扩展签名并安装。

如果网页上传时漏了 `.github` 文件夹，可在仓库点击 **Add file → Create new file**，文件名填 `.github/workflows/build-ios.yml`，把本工程同名文件内容复制进去，提交后再进 Actions。

### 已经装好 Git 的 Windows 用户

在解压目录打开 PowerShell，依次运行（把远程地址换成自己创建的空仓库地址）：

```powershell
git init
git add .
git commit -m "Initial Dragon Island prototype"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/DragonIsland.git
git push -u origin main
```

Git 的登录和账号验证在你自己的电脑完成。如果新仓库预先创建了 README，先克隆仓库，再把工程内容复制进去提交，避免远程历史冲突。

## 运行要求与首次测试

- iOS 17.0 或更高；要在灵动岛查看，需有实际配备灵动岛的 iPhone。
- 不要求 A17 Pro，不能把前面 Switch 移植游戏的机型要求套到本 App。
- 安装后打开 App，允许实时活动。若 iOS 要求开发者模式，请按系统提示开启。
- 选 **1 分钟 → 开始陪伴 → 回到桌面 → 长按灵动岛**。
- 点击招呼，检查短句变化；点击心情，检查状态变化；点击结束，检查卡片消失。
- 再开始一轮并锁屏，检查锁屏卡片；从锁屏按钮更新状态后回到 App，状态应同步。
- 退出再打开 App，应恢复系统里仍在进行的活动，避免重复创建。

## 倒计时结束的实际行为

系统负责显示倒计时，不依赖 App 在后台每秒运行。到时计时停止，`staleDate` 标记活动过期；不保证卡片到秒自动收起，可手动结束。**开启到点语音且授权后，由系统闹钟（iOS 26+）或本地通知（旧版）在结束时间提醒。** 未开启时保持安静陪伴。结束本轮会取消关联提醒，单独设置的角色闹钟独立保留。

## 编译任务里做了什么

`macos-26` runner 与 iOS 26 SDK：安装 XcodeGen、Pillow 与 fonttools → Swift / Python 测试 → 生成图片与动作字体 → 生成 Xcode 工程 → `xcodebuild` 编译真机 arm64 App 和扩展（关闭签名）→ 打包并检查 IPA、语音与扩展 → 模拟器界面测试及真实系统闹钟/灵动岛验证 → 上传构建产物。

编译失败时，下载同次运行的 `mAIverse-build-log` 或查看失败步骤的红色错误行。上传工程包本身不表示已编译成功。依赖版本和 Apple SDK 变化也可能需要修正。

## 文件布局

| 路径 | 内容 |
|---|---|
| `App/` | SwiftUI 页面、活动状态管理 |
| `Widget/` | 锁屏和灵动岛布局 |
| `Shared/Models/` | 可独立测试的计时与心情模型 |
| `Shared/Resources/Characters.json` | 角色目录、名称和两种形象的资源映射 |
| `Shared/Activity/` | ActivityKit 属性、互动 Intent |
| `Shared/Resources/` | 小尺寸角色资源 |
| `Art/xiaobai-chibi-v2.png` | V1.4 新 Q 版高分辨率母图，旧图另行保留 |
| `Art/MotionV2/` | 透明动作帧、时长索引及完整提示词 |
| `Art/xiaobai-standing.png` | 从用户立绘处理得到的透明版本 |
| `Scripts/capture_previews.sh` | 云端模拟器深浅色页面截图、交互测试与实际系统灵动岛截图 |
| `Scripts/` | 资源处理、云端编译、IPA 结构检查 |
| `.github/workflows/` | GitHub Actions 工作流 |
| `Tests/` | Swift 状态测试、Python 打包检查测试 |

## 有 Mac 时

装好 Xcode 和 Homebrew 后：

```bash
brew install xcodegen
python3 -m venv .asset-venv
source .asset-venv/bin/activate
python3 -m pip install -r requirements-build.txt
swift test
bash Scripts/build_unsigned.sh
```

产物位于 `output/`。若要用 Xcode 自动签名，先生成工程，再打开 `DragonIsland.xcodeproj`，为 App 与 Widget 两个 target 选择同一开发团队，按需修改两者的 Bundle ID。上述脚本每次会重新生成工程，手工配置请保存在 `project.yml` 中。

## 素材与定位

mAIverse 是产品名称；源码 target、Bundle ID、URL scheme 与仓库暂沿用原有 DragonIsland 标识，方便沿用签名与覆盖升级。角色“小白”是第一个角色，不是整个 App 的名称。

角色是根据用户提供参考生成的同人形象，不代表 OpenAI 官方角色。当前 Q 版源图为 `Art/xiaobai-chibi-v2.png`，`Art/dragon-original.png` 保留为旧版。此版本只是本地陪伴 UI，未接入 ChatGPT，也不会生成 AI 对话。

0.2.0 新增的立绘原图与透明处理版本均保存在 `Art/`，Q 版与立绘分别用于不同场景。详见 [角色接入说明](docs/CHARACTERS.md)与[立绘处理记录及提示词](docs/ARTWORK.md)。

## 官方参考

- [Apple ActivityKit](https://developer.apple.com/documentation/activitykit)
- [添加 Widget 与实时活动交互](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [实时活动动画限制](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities)
- [GitHub macOS runners](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
- [Sideloadly](https://sideloadly.io/)


