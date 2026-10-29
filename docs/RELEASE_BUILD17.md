# mAIverse V1.8 build 17

2026-10-30，按用户要求打包已完成的 DeepSeek 聊天功能。包含主 App 与 Widget 扩展；本包未签名，使用 Sideloadly 签名安装。

## 本次改动

- 接入 DeepSeek 官方流式单聊和群聊，支持停止回复、保留未完成内容、失败重试。正式版不再返回固定测试回复。
- “角色 → 人物详情 → AI 与人格”设置角色的模型、思考模式、上下文轮数、输出上限和人格；聊天页左上角也能进入。
- 增加我的昵称和资料，可选择是否提供给角色。完整聊天、草稿、群组和公开配置保存在手机本地。
- DeepSeek 密钥由用户在手机中填写，仅保存在本机钥匙串，不内置于 IPA、源码或聊天备份。所有角色共用密钥，各自保存模型和人格。
- 聊天页提供本地 JSON 备份导出和恢复，单份上限 20 MiB；备份不含密钥、动作及闹钟设置。聊天目录排除系统备份，应使用 App 内导出另存。
- 保留 build 16 中的透明照片选择、角色卡片、语音和闹钟，以及已确认的完整舞蹈、遛狗、御剑和骑鲸资源与排程。

## 验证范围

聊天功能代码 `2574677` 已通过 [67 项 Swift、13 项模拟器界面测试及 App/Widget 编译、资源和字体检查](https://github.com/yangtao990518/DragonIsland/actions/runs/40910797995)。本次版本号递增为 build 17，打包工作流另检查 Release 设备构建、IPA 结构与资源，结果见随包 BUILD_STATUS.md。

仍未完成真实 DeepSeek 账号联网、Sideloadly 真机覆盖升级、长期后台与耗电验证。

## 安装时保留数据

- 不先卸载旧 App；核对并沿用原 Sideloadly Apple ID、实际 Bundle ID 和签名身份。身份不匹配时不能保证覆盖升级和钥匙串访问。
- 必须保留 Widget 扩展，不能删除 PlugIns 或只签主程序。
- 正式源 Bundle ID 保持 App `com.dragonisle.prototype.app`、Widget `com.dragonisle.prototype.app.widget`；重签后的实际值需在本机核对。
- 本包不包含公司安装助手、私密签名缓存或这台电脑的任何凭据。
