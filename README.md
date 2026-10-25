# mAIverse · 我的 AI 小世界

属于自己的 AI 角色小世界：让喜欢的角色在 iPhone 上陪伴你。当前只有白紫色 ChatGPT 同人龙娘“小白”，角色目录和选择界面已准备好，后续可配置其他 AI 角色；目前没有 AI 对话。SwiftUI 主 App + ActivityKit 实时活动 + WidgetKit 扩展。**Windows 用户通过 GitHub Actions 的 macOS runner 编译，无需本地 Mac。**

## 第一版做什么

- 使用本次确认的白角、紫瞳、白发、龙翼与鳞片尾巴角色；头像和全身形象均已打包。
- App 内有轻微上下浮动的待机效果，尊重系统“减弱动态效果”设置。
- 选择 1 / 25 / 50 / 120 分钟的一轮陪伴。
- 日常灵动岛紧凑态和最小态使用 Q 版小人物；长按展开和锁屏使用用户提供立绘的透明版本，主界面展示大尺寸立绘。
- 主 App 包含“我的世界 / 角色 / 关于”，提供两种岛上形态的示意预览。更多角色可通过统一目录配置，当前只有小白。
- 锁屏也有对应卡片；没有灵动岛的设备仍可测试锁屏实时活动。
- “招呼”轮换本地短句，“心情”切换三种状态，“结束”收起实时活动。
- 无联网、无账号、无 AI API 调用、无推送服务器。

## 先读清楚这三点

1. **当前对外版本统一为 mAIverse V1.1。** 原型阶段归为 V1.0 阶段，此后交付的 IPA 均带版本号，例如 `output/mAIverse-V1.1-unsigned.ipa`。主 App 和扩展的内部版本均为 1.1（build 4），后续文件名直接读取实际 App 版本自动生成。功能沿用已经过[云端构建](https://github.com/yangtao990518/DragonIsland/actions/runs/40175751176)验证的双形态与三页界面；本次版本更新的实际构建结果见 [验证记录](docs/VALIDATION.md)。系统灵动岛展开布局的真机显示仍待用户验证。
2. **灵动岛不会永久循环播放小人跑步、眨眼动画。** 第一版在 App 内做待机浮动，在实时活动中使用角色图片、系统倒计时和状态更新时的短过渡。实时活动的显示与调度由 iOS 控制。
3. **签名必须保留 Widget 扩展。** 删除 `PlugIns/*.appex`、只签主程序，可能导致 App 可打开而灵动岛无内容。源代码不要求 App Groups、推送或 iCloud 权限，首次编译无需上传 Apple 证书。

## Windows：最快开始

1. 解压本工程，进入含 `project.yml`、`App`、`Shared`、`Widget` 的目录。
2. 登录 GitHub，新建一个空仓库，如 `DragonIsland`。公开仓库的标准 Actions runner 通常免费；私有仓库使用你的 Actions 配额。无需添加 Apple ID、密码或证书到仓库。
3. 在仓库选择 **Add file → Upload files**，上传这个目录里的所有内容，**包括 `.github/workflows/build-ios.yml`**。不要只上传整个 ZIP，也不要多套一层 `DragonIsland` 目录。
4. 提交到 `main` 后自动触发编译。或进入 **Actions → Build iOS IPA → Run workflow** 手动运行。
5. 等待绿色成功标志，进入该次运行，滚到 **Artifacts**，下载带版本号的 **mAIverse-V1.1-unsigned**（后续版本会相应更新）。
6. 解压下载到的 ZIP，里面才是 `mAIverse-V1.1-unsigned.ipa`、安装说明和 SHA-256 校验文件。
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

系统负责显示倒计时，不依赖 App 在后台每秒运行。到时计时停止，`staleDate` 标记活动过期；系统下一次渲染时可显示完成提示。**没有后台服务器时，不保证到秒自动收起卡片或自动响铃。** 点结束收起，或回 App 点“收起这一轮”；开始下一轮也会清理旧活动。用户和系统都可能提前结束或隐藏活动。

## 编译任务里做了什么

`macos-15` runner：安装 XcodeGen 与 Pillow → `swift test` 跑计时与状态测试 → 生成图片资源 → 生成 Xcode 工程 → `xcodebuild` 编译真机 arm64 App 和扩展（关闭签名）→ 打包 IPA → 验证扩展、可执行文件、资源、版本号 → 上传构建产物。

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
| `Art/dragon-original.png` | 本次确认的生成角色原图 |
| `Art/xiaobai-standing.png` | 从用户立绘处理得到的透明版本 |
| `Scripts/capture_previews.sh` | 云端 iPhone 模拟器三页实际截图 |
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

角色是根据用户提供参考生成的同人形象，不代表 OpenAI 官方角色。Q 版源图保存在 `Art/dragon-original.png`。此版本只是本地陪伴 UI，未接入 ChatGPT，也不会生成 AI 对话。

0.2.0 新增的立绘原图与透明处理版本均保存在 `Art/`，Q 版与立绘分别用于不同场景。详见 [角色接入说明](docs/CHARACTERS.md)与[立绘处理记录及提示词](docs/ARTWORK.md)。

## 官方参考

- [Apple ActivityKit](https://developer.apple.com/documentation/activitykit)
- [添加 Widget 与实时活动交互](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [实时活动动画限制](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities)
- [GitHub macOS runners](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
- [Sideloadly](https://sideloadly.io/)
