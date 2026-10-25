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
- 本版本云端编译与实际 IPA 名称检查结果待补充。
