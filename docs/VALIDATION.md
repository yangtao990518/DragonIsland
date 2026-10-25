# 验证记录 · 2026-10-25

## 本次实际执行并通过

- 10 个 Swift 文件经 tree-sitter Swift 语法树解析，无 ERROR 或缺失节点；这是语法检查，不是 Swift 类型检查。
- `project.yml` 与 Actions 工作流通过 YAML 解析；主 App、Widget 两个 target 和 scheme 均存在。
- 图片资源处理脚本实际运行；各 imageset 的 JSON、PNG 文件与尺寸有效；App 图标为不透明 RGB。
- 人工查看深色背景下的全身、头像和图标缩略图，角色保留白角、紫瞳及白紫配色。
- 隐私清单通过 plist 解析。
- `build_unsigned.sh` 通过 `bash -n`。
- Python 打包验证器的 4 项回归测试通过：完整容器接受、漏掉扩展拒绝、版本不一致拒绝、未开启实时活动拒绝。测试使用构造的容器，不代表已产生真正 IPA。

## 已配置，尚未实际执行

- `swift test`：5 项 Swift 模型测试（计时边界、时长限制、互动不延时、心情循环、序列化）。GitHub Actions 会运行。
- XcodeGen 生成 `.xcodeproj`。
- `xcodebuild` 编译真机 App 与 Widget 扩展，以及 Swift/SDK 类型与可用性检查。
- 对真实编译产物运行 IPA 结构验证。
- 签名安装、实时活动授权、锁屏与灵动岛真机显示和互动。

本次环境为 Linux，没有 Swift 编译器或 Xcode，因此不能把语法通过写成“已编译通过”或“已真机运行”。第一次 GitHub Actions 的结果将补上编译验证；真机签名及显示仍需用你的 iPhone 测试。
