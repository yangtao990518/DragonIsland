# 验证记录 · 2026-10-25

## 源码包交接时已完成的检查

- 10 个 Swift 文件经 tree-sitter Swift 语法树解析，无 ERROR 或缺失节点；这是语法检查，不是 Swift 类型检查。
- `project.yml` 与 Actions 工作流通过 YAML 解析；主 App、Widget 两个 target 和 scheme 均存在。
- 图片资源处理脚本实际运行；各 imageset 的 JSON、PNG 文件与尺寸有效；App 图标为不透明 RGB。
- 人工查看深色背景下的全身、头像和图标缩略图，角色保留白角、紫瞳及白紫配色。
- 隐私清单通过 plist 解析。
- `build_unsigned.sh` 通过 `bash -n`。
- Python 打包验证器的 4 项回归测试通过：完整容器接受、漏掉扩展拒绝、版本不一致拒绝、未开启实时活动拒绝。测试使用构造的容器，不代表已产生真正 IPA。

## 2026-10-25 首次实际云端编译通过

- 私有仓库：<https://github.com/yangtao990518/DragonIsland>。
- 成功运行：<https://github.com/yangtao990518/DragonIsland/actions/runs/40171957891>，提交 `6f4c0e84ee492549f949bcfcd44c958690f7a122`。
- 环境：GitHub Actions `macos-15`，实际 runner 为 macOS 15.7.9 arm64，Xcode 16.4（16F6）。
- `swift test`：5 项模型测试全部通过，0 失败。
- Python 打包验证器：4 项回归测试全部通过。
- XcodeGen 实际生成工程；`xcodebuild` 真机 Release 构建主 App 与 Widget 扩展，日志为 `BUILD SUCCEEDED`，未签名。
- 真实 IPA 通过结构检查：主程序、`PlugIns/DragonIslandWidget.appex`、可执行文件、编译资源、版本号与包名关系均通过。
- 产物 `DragonIsland-unsigned`（artifact ID `12590656993`）已下载到本机并解压至 `output/`。下载 ZIP 的 SHA-256 与 GitHub artifact digest 一致，解压后的真实 IPA 再次通过结构检查。
- `output/DragonIsland-unsigned.ipa`：4,031,267 字节；SHA-256 为 `4a37685f62d0fbb0f2bbd78b1e8fc04c0929425f91e33adaec3cbad2ff37094d`，与产物中的 `SHA256SUMS.txt` 一致。
- 编译有一项界面方向警告：`All interface orientations must be supported unless the app requires full screen`。本项目仅面向 iPhone、仅竖屏；此警告未阻止打包，显示效果仍需真机检查。

## 用户反馈与后续验证

- 用户提供的设备信息：iPhone 18 Pro Max、iOS 27.01；签名工具为 Sideloadly。未直接检查设备信息。
- 用户提供了初版实时活动展开态截图，显示角色、短句、倒计时与互动按钮，反馈底部按钮裁切；该布局问题待下一步修复。
- 紧凑态、最小态、锁屏、按钮实际执行、结束及 App 重开恢复，仍待逐项反馈验证。
- 到期后的实际系统显示与收起行为；仍不保证到秒自动收起或响铃。

本地工作区为 Windows；实际 Xcode 编译已在 GitHub 的 macOS runner 完成。编译通过与 IPA 结构检查通过，不代表已签名成功或已真机运行。

## mAIverse 更名版 0.1.1（build 2）

- 产品名称定为 mAIverse，含义为 My + AI + Universe；当前角色仍为小白，其他 AI 角色是后续计划。
- 统一桌面显示名、App 内标题、扩展显示名及下载产物名称；Bundle ID、target、URL scheme 保持原值，以便覆盖升级。
- 本次不调整展开态布局；底部按钮裁切问题仍保留为下一步工作。
- [本版本云端构建](https://github.com/yangtao990518/DragonIsland/actions/runs/40173652726)成功，源码提交 `700008b8d38482fdebccc97bf929192c31e3b981`；Xcode 16.4（16F6），5 项 Swift 模型测试、4 项 Python 打包测试及真实 IPA 结构检查均通过。
- 产物 `mAIverse-unsigned`（artifact ID `12591376046`）已下载至 `output/mAIverse-unsigned.ipa`，4,031,281 字节；下载 ZIP 校验值与 GitHub artifact digest 一致。
- IPA SHA-256：`3b02159a317476d2e69179a67fb1252b957220eca30e23c4633de53c3fd1fdec`，与产物中的 `SHA256SUMS.txt` 一致。
- 实际解析 IPA 内主 App 和扩展的 Info.plist，确认显示名分别为 `mAIverse`、`mAIverse 实时活动`，版本均为 0.1.1（build 2），Bundle ID 与旧版本一致，Widget 扩展保留。
- 原有竖屏相关编译警告仍在；本次没有新增编译错误。更名版的实际覆盖安装与桌面显示待用户验证，按钮裁切仍待下一步修复。

## 双形态与界面更新 0.2.0（build 3）

- [云端构建](https://github.com/yangtao990518/DragonIsland/actions/runs/40175751176)成功，源码提交 `17ce20ee57a0de29da5eeefa9acbb582e89203cd`，使用 Xcode 16.4（16F6）。
- 8 项 Swift 测试（含角色目录、不同形象映射、无效目录拒绝和旧角色 ID 回退）与 4 项 Python 打包测试通过。
- 主 App 与 Widget 的真机 Release 编译和真实 IPA 结构检查通过；扩展仍为 `DragonIslandWidget.appex`。原有竖屏警告保留。
- iPhone 16 Pro 模拟器 Debug 编译、安装与运行成功，实际捕获 `world.png`、`characters.png`、`about.png`；已目视检查主界面文字、立绘、开始按钮、角色页和关于页。截图为 1206×2622，保存在 `output/previews/`。
- 紧凑态、最小态使用 Q 版全身小人物；展开态与锁屏使用透明立绘。展开布局把按钮移到立绘右侧并减少纵向堆叠，底部留出 8pt；本次未捕获系统灵动岛展开截图，真机是否完全解决裁切仍待用户确认。
- App 和 Widget 均包含同一份 `Characters.json`，已从真实 IPA 逐字解析对比源码目录。每轮 Activity 绑定稳定角色 ID，未来可通过角色目录扩展；当前只有小白，没有新增 AI 对话能力。
- 真实 IPA 显示名为 mAIverse，主 App 和扩展版本均为 0.2.0（build 3），Bundle ID 保持原值。
- 产物 `mAIverse-unsigned`（artifact ID `12592086975`）下载 ZIP SHA-256 与 GitHub digest 一致。IPA 为 6,338,720 字节，SHA-256 为 `bf599b7181c6f73d24261afadf3c918768f7e7d0f82dfb2591ed9728151fb119`，与产物校验文件一致。
- 立绘处理来源、原图、最终素材和完整提示词见 `docs/ARTWORK.md`；多角色配置方式见 `docs/CHARACTERS.md`。
