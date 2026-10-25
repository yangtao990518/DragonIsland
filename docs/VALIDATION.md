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

## 对外版本统一为 V1.1（内部 1.1 / build 4）

- 按用户要求，对外版本从 V1.0 阶段起计，当前为 V1.1；后续 IPA 和 Actions 下载包都包含版本号，规则见 `docs/VERSIONS.md`。
- [本版云端构建](https://github.com/yangtao990518/DragonIsland/actions/runs/40176430230)成功，源码提交 `90d6a9fc764f0e37b8ecc2e447da18050e31f660`；8 项 Swift 测试、4 项 Python 测试、真机 Release 构建、真实 IPA 结构验证和模拟器三页截图步骤均通过。
- 产物名称为 `mAIverse-V1.1-unsigned`（artifact ID `12592541853`），已下载并校验 ZIP digest。
- 真实 IPA 为 `output/mAIverse-V1.1-unsigned.ipa`，6,338,696 字节；SHA-256 为 `f0b17b133465880805f1c4cb7fdc0913719718a6de4bec837d4b35c7439e7838`，与产物校验文件一致。
- 已逐项解析主 App 与 Widget 的 Info.plist，二者版本均为 1.1（build 4），文件名与包内版本一致；Widget 扩展和原 Bundle ID 保留。关于页显示版本带 V 前缀。
- 本次为版本与交付命名更新，功能及待真机验证事项沿用上一版。

## 四项改造 V1.2（内部 1.2 / build 5）

- [最终云端构建](https://github.com/yangtao990518/DragonIsland/actions/runs/40179759854)成功，源码提交 `f00f1ee5952dae77e4de4e962d464e7efba929f6`，Xcode 16.4（16F6）。主 App 与 Widget 真机 Release 编译、打包和结构检查通过。
- 10 项 Swift 模型测试、4 项 Python 打包测试通过；另外 4 项 XCUITest 通过，涵盖卡片进入详情、Q 版缩放与还原、独立立绘查看、外观重开保留及实际系统灵动岛动作截图。无启动失败跳过，实际导出 26 张测试附件。
- 在 iPhone 16 Pro 模拟器实际捕获 12 张页面截图：世界、角色、详情、Q 版大图、立绘大图、关于，各有深浅两色。已目视检查浅色文字对比、双形态图片、图标选择和展开态按钮；实际系统展开态三个按钮完整显示。用户手机上的裁切是否解决仍需安装验证。
- 实际 SpringBoard 灵动岛连续截图记录一次短位移和一次旋转。位移序列中角色左边界依次为 328、329、335、342、346 个原生像素；旋转序列出现倾斜及横向中间画面后回正，证实过渡实际播放。此证据仅覆盖模拟器中的单次图片位移 / 旋转，不能视为逐帧走路、持续自主循环或真机成功。
- 人物卡片和详情使用统一角色目录，分别提供高分辨率 Q 版与立绘大图；看图支持双指缩放、双击、拖动、还原和背景切换。主 App 深色 / 白色设置持久化。
- 使用用户指定五款图标，默认 GPT，其余四款为备用图标；真实 IPA 的 `CFBundleAlternateIcons` 包含 Claude、DeepSeek、Gemini、Grok。实际系统桌面截图已看到 GPT 默认图标；备用图标的手机切换行为待用户验证。
- 最终 artifact ID `12594411449`，下载 ZIP 为 138,374,901 字节，SHA-256 为 `bae53d166b8dffccbbe2d0acd06e25511c5f27010e5a79667c7437ac186f0a11`，与 GitHub artifact digest 一致。
- 本机交付路径为 `D:\gpt_workspace\ios_ldd\mAIverse-V1.2\mAIverse-V1.2-unsigned.ipa`。IPA 为 34,771,178 字节，SHA-256 为 `c5f189a26bab59e32ac924344f30751b46d35fd3351ff0122d89626c0a216c8d`，与产物校验文件一致。旧版目录保留。
- 本机再次运行真实 IPA 结构检查，并解析 App 与 Widget 的 Info.plist：二者均为 1.2（build 5），Bundle ID 沿用旧版本，`DragonIslandWidget.appex` 完整保留。
- 本轮未实际操作 Sideloadly、签名或用户 iPhone。按 `docs/TEST_GUIDE.md` 验证 1 分钟陪伴、主题、图片操作、图标、短动作、互动、结束及重开恢复；原有到期不保证精确收起的边界保留。

## 看图关闭手势 V1.3（内部 1.3 / build 6）

- 用户反馈看图必须点 X 退出。加入单击图片返回、未缩放时单指下滑关闭；双击等待识别后缩放，放大后拖动不直接关闭。
- [云端构建](https://github.com/yangtao990518/DragonIsland/actions/runs/40180604685)成功，源码提交 `353ea7b2e24f7148d501d30dda880df2eaad99cb`。App、Widget、10 项 Swift 模型测试、4 项 Python 打包测试及 5 项界面测试步骤通过。
- 新的界面测试实际覆盖双击放大、放大后的下拉仍停留、单击退出、另开立绘并下滑退出。原有页面与灵动岛截图步骤通过；下载产物保留测试附件。
- artifact ID `12594296988`，下载 ZIP 为 138,407,214 字节，SHA-256 为 `2e6fd6d773d19c64724b29004f7fb90d1831d9e45739790431b1c410f3e6da52`，下载后已比对一致。一次下载遇到传输中断，重试后成功且校验值正确。
- 本机 IPA 为 `D:\gpt_workspace\ios_ldd\mAIverse-V1.3\mAIverse-V1.3-unsigned.ipa`，34,773,288 字节，SHA-256 为 `5f2d06ba81f60e5ba91bf56cdbfd815efcc358187d503c4fcdee3fe471f9a503`，与产物校验文件一致，真实 IPA 结构检查再次通过。
- 用户随后要求先暂停代码、讨论自动随机并制作新 Q 版动作素材；V1.3 没有替换新 Q 版，也没有新增持续随机功能，真机手势仍待安装检查。

## 新 Q 版动作素材 V2（未接入 IPA）

- 用户提交的初版素材位于 `D:\gpt_workspace\ios_ldd\mAIverse_DragonGirl_Animation_Assets`，左右走各 4 帧，镜像逐像素一致；旧站姿备份与 App 原图 SHA-256 相同。已查看全部走路姿势和图集，发现缺少明显交替步态、待机、翻滚及新中立母图。
- 用户授权补画、自测后使用内置 imagegen 另存 `mAIverse_DragonGirl_Animation_Assets_V2`，未覆盖输入。包括中立母图、待机 / 左走 / 右走 / 打滚 / 转身 36 个透明 PNG 帧文件、动画预览、动作片段索引和完整提示词。重复端点未计为额外绘制。
- 6 项素材检查实际通过；浏览器实际验收图片加载、暂停逐帧、深浅背景、小尺寸及随机池筛选 / 无动作时待机，保存截图与检查记录。原始候选、处理脚本和逐帧图均保留。
- 素材与浏览器演示验证不能代替真实灵动岛播放；新素材尚未集成，基于系统计时字形 / 遮罩的后台持续随机仍是待验证候选方案，研究见 `docs/RANDOM_MOTION_RESEARCH.txt`。

## 新 Q 版与自动动作 V1.4（内部 1.4 / build 7）

本节更新并取代上一节“未接入 IPA”的阶段状态。新素材与自动播放器已进入下列最终安装包；没有进行用户手机签名或实机测试。

- [最终云端构建](https://github.com/yangtao990518/DragonIsland/actions/runs/40196702922)成功，源码提交 `42c3cc94a1bbdd70c1264e205f2d97b72241253d`。macOS 15 runner、Xcode 16.4；App 与 Widget 真机 arm64 Release 构建、真实 IPA 检查、模拟器 Debug 构建和界面测试步骤全部通过。
- 共 24 项测试：12 项 Swift 模型、6 项 Python 资源 / 打包、6 项 XCUITest。界面覆盖图片缩放 / 还原 / 背景、独立立绘、深浅主题重开保留、单击 / 下滑关闭及缩放手势冲突、动作选择重开保留与旧测试按钮移除，以及不点击动作按钮直接回桌面的自动活动取证。界面测试失败会使工作流失败，不以跳过测试代替通过。
- iPhone 16 Pro 模拟器实际导出 14 张 1206×2622 页面截图：世界、角色、任务、详情、Q 版大图、立绘大图、关于，各含深浅两色。本机已目视检查；大图使用 1122×1402 新 Q 版母图，立绘保留原版本。
- 系统 SpringBoard 自动活动取证 60 张，三个时间段，总跨度 159.976 秒；期间未点击动作按钮。对不含倒计时的角色区域进行像素对比，后两段分别有 18 和 14 种不同画面，且角色持续可见。逐图目视可见站姿、蜷身翻滚和回正；这证明本次模拟器离开 App 后仍换帧，不能推导为用户 iOS 27.01 长时间运行稳定。
- 实际系统展开态截图已检查：新 Q 版在名称旁，大立绘在左侧，招呼 / 心情 / 结束三个按钮完整显示。深浅页面、系统展开图、角色连续裁剪图和计算报告保存在本机交付目录的 `previews/`、`ui-test-attachments/`、`verification/`。
- 实现为系统计时字形 / 遮罩播放离线预排帧；当前目标 8fps、每段五秒、60 秒循环，开局从两套种子中选择。任务页勾选决定四种动作集合之一，关闭自动活动为静态。未新增后台 Timer 循环、逐帧 Activity.update、服务器、推送或 App Groups；息屏低亮度 / 减弱动态效果主动静态。系统调度可能限帧，截图不证明稳定达到 8fps。
- 字体内重复帧引用去重，单个 bundle 字体资源由 138,927,792 字节降至 16,500,928 字节；最后一轮截图取自去重后的最终构建，不沿用中间候选安装包。
- artifact ID `12600257974`；下载 ZIP 为 287,849,926 字节，SHA-256 为 `fc1e9e571e1324183ee0dfc244e307031ee827e82b6e233e1ede428797af0a65`，本机与 GitHub digest 一致，全部 ZIP 成员 CRC 检查通过。
- 最终本机 IPA：`D:\gpt_workspace\ios_ldd\mAIverse-V1.4\mAIverse-V1.4-unsigned.ipa`，72,501,163 字节；SHA-256 为 `9e13b98d38a1794bc918d099828a8793dc685bbfc7baeeccc85fb54a0ca7c84a`，与产物 `SHA256SUMS.txt` 一致，本机重新运行 `Scripts/verify_ipa.py` 通过。
- 逐项解析 IPA 的 App 与 Widget Info.plist：二者均为 1.4（build 7），原 Bundle ID 关系保留，`PlugIns/DragonIslandWidget.appex` 完整，双方均含 129 个注册字体及 8×480 帧计划。五款图标配置保留（GPT 默认、四款备用）。MIT 第三方声明已打包。
- 保留既有仅竖屏的编译警告，未出现阻止构建的错误。到期仍不保证精确收起或响铃。Sideloadly 签名、用户手机上连续至少五至十分钟播放、筛选、锁屏 / 解锁、招呼 / 心情 / 结束和重开恢复按 `TEST_GUIDE.md` 安装确认；编译、模型和模拟器通过不能代替这些实机结果。
