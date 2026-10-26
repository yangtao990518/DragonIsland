# 验证记录 · 2026-10-25

## V1.8 候选保存（2026-10-26，尚未交付）

- 功能源码 `9e04f0ff4daf3a58d36831a1d673342c1b4c44d3`，分支 `codex/character-voice-alarms`；恢复说明见 `V1.8_RESUME.md`。
- [运行 40345351544](https://github.com/yangtao990518/DragonIsland/actions/runs/40345351544)：App / Widget 编译、真实 IPA 结构、24 项 Swift、20 项 Python、336 个 CoreText 检查通过；10 项界面测试中 9 项通过。
- 未通过项为真实一分钟闹钟的系统停止控件检查。系统标题存在断言通过，保存截图为紧凑态；停止控件未找到，展开与系统停止操作仍待验证。失败后从 App 取消并确认记录清空通过。后续视频分析和最终 IPA 发布未执行，不能把候选编译通过说成最终验收完成。
- [诊断运行 40348647821](https://github.com/yangtao990518/DragonIsland/actions/runs/40348647821) 因账户付款 / Actions 支出限制未启动任何步骤。用户要求先保存代码，待通知后继续；当前暂停触发云端构建。手机签名、实际音频听感及静音 / 专注模式仍未实机验证。

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

## V1.5 修复准备与前版遗漏

- 用户安装 V1.4 后反馈真实动作叠影、左右脚步异常、移动太慢，并要求目标先提高到 30fps。V1.4 的连续截图只证明换帧，没有证明透明帧叠放正确；之前目视验收漏查叠影，不能再把那组截图当作无残影证据。
- 确认代码原因：累积字体层与透明 PNG 直接叠放，旧姿势从新帧透明部分透出；左走预留转身 / 收脚时间与横移区间不一致，原 8fps 还会跳过部分短时长步态帧。
- V1.5 本地改为岛上独立黑色不透明帧面、30fps / 60 相位、左右各 16 帧及 16 帧打滚。迈腿区间内才横移，横移速度约提高到 2.25 倍。注册 481 个字体，96 像素图像避免使用过大的纹理；App 图集仍透明。
- 首轮本地 9 项 Python 检查通过；另逐个解码实际生成字体，核对 3,724 个 PNG 位图 alpha 全不透明及 25,076 个直接去重引用。该数字对应打滚补帧前的中间候选，最终生成结果另行记录。
- 本节只记录修复准备，不代表最终 Xcode / 系统视频验证已完成；后续最终记录为准。没有操作用户手机或签名安装。

## V1.5 build 8 候选：构建通过，录像发现闪帧，未交付

本节记录上节后的一次候选检查，尚不是最终交付结论。虽然自动测试通过，逐帧录像仍发现左走中偶发一帧正面姿势，因此此候选未向用户交付。下面的安装包数字仅对应 build 8；后续采用字形提前准备、遮罩随后打开的 build 9 再验证。

- [候选云端构建 40208298270](https://github.com/yangtao990518/DragonIsland/actions/runs/40208298270)成功；源码 `4602cab2206a1f6a23b9dfad99df26d72eed6bb8`，job `121213884453`，macOS 15 / Xcode 16.4。App 与 Widget 真机 arm64 Release 构建、真实 IPA 结构检查、模拟器 Debug 构建与 XCUITest 全部通过；通过不等于帧序完全正确。
- 共 29 项测试通过：12 项 Swift 模型、11 项 Python 资源 / 打包、6 项 XCUITest。新增回归检查覆盖透明旧姿势透出、30fps 阶段顺序、只在有效迈腿区间横移、16 帧资源和两小时内隐藏时段不串动作集合。另有 macOS CoreText 实际字形检查 112 个集合 / 阶段用例通过；本地 HarfBuzz 21,600 个小时 / 分钟 / 秒 / 阶段格式用例通过。
- 失败候选如实保留：`40202824908`、`40203767963` 的数百字体方案在回桌面后丢失活动；`40205453544` 的运行时可变字体方案也未通过系统显示检查；`40206961187` 的命名可变实例未通过原生字体检查。它们没有作为成功包交付。不能仅凭这些失败推断精确内存上限，未测量运行时 RSS。
- 最终改为 60 个普通阶段字体加一个遮罩字体，八套动作集合放入每个阶段字体，通过隐藏计时小时段选择；只在普通紧凑态装载完整动画。最小态与展开名称旁使用静态 Q 版，大立绘不变。每个 bundle 的字体为 10,787,176 字节；不再是准备阶段的 481 个字体。
- 本机直接解码候选 IPA 两个 bundle 的全部字体：每个 bundle 检查 1,004 个实际编码位图，均为 96×96、alpha 全 255；全局去重后为 136 种位图，另有 27,796 个重复引用。覆盖旧帧的黑色底面已进入候选包，App 的图片帧仍透明。结果随候选归档至 `build/qa-v15-build8-release/verification/release-verification.json`。
- 左右走分别使用 16 个独立绘制姿势，打滚 16 个帧文件含共用中立首尾；待机 / 转身沿用 V2。走路在约 1.07 秒的有效步态中完成横移，前后转身 / 收脚停止横移，相同尺寸横移速度约为旧版 2.25 倍；走路与打滚循环各连续播放两次。不是将原来八帧重复标注为 30fps。
- 实际 iPhone 16 Pro 模拟器输出 14 张深浅页面截图、60 张 SpringBoard 采样图和系统展开图。本机已目视检查深浅主题、卡片、两种大图、任务勾选与展开按钮。界面测试在三段采样各自检查人物像素，且回到 App 后确认活动仍在；首页切换的首张过渡截图不作为人物持续可见证据。展开图大立绘和三个按钮完整，选中帧未见 V1.4 的双轮廓透出。
- 原始系统录像长约 267.86 秒，实际解码 11,675 帧；选取六个左右步行时窗共 746 个视频样本，保存 360 个原始人物裁剪。每个采样分钟都有实际人物像素，未使用 App 内动画录像替代 SpringBoard。视频名义帧率约 44.23fps 是录屏数据，不是人物动画或真机帧率；姿势停留、压缩噪声与计时对齐均影响分析，30fps 仍为目标。
- IPA artifact `12605216182`：ZIP 64,206,379 字节，SHA-256 `91caed63d9209100e25401bb7d4cacb78c2a5ec3598c7713a3f21acb405df741`，已与 GitHub digest 核对。实际 IPA 64,349,886 字节，SHA-256 `d1d161512c8f19127d80e917de5ec6a429567de33055745a88be7ccf13b63be5`，与产物 `SHA256SUMS.txt` 一致；再次运行真实 IPA 结构检查通过。
- 本机候选从版本目录移到 `DragonIsland/build/qa-v15-build8-release/`，避免与最终交付混淆。App / 扩展均为 1.5（build 8），原 Bundle ID 对应关系、`PlugIns/DragonIslandWidget.appex`、双方 61 个注册字体和 8×1800 帧计划完整，旧版本文件夹保留。
- 保留原有竖屏警告；视频诊断脚本有 AVFoundation 同步读取 API 弃用提示，未阻止实际解码。未替用户操作 Sideloadly 或手机，不声称 iOS 27.01 真机稳定 30fps；长时间后台、锁屏解锁、耗电和实际签名仍需用户按 `TEST_GUIDE.md` 验证。更新后先结束旧活动再开启新一轮，并保留、签名 Widget 扩展。

## 最终交付 V1.5（内部 1.5 / build 9，2026-10-26）

- [最终构建 40213328156](https://github.com/yangtao990518/DragonIsland/actions/runs/40213328156)全部成功；源码 `0aa65452957c39ebc85c6da1a077038ee237af01`，job `121229049396`。App / Widget arm64 Release、模拟器 Debug、真实 IPA 校验通过。
- 共 30 项测试：12 项 Swift 模型、12 项 Python 资源 / 打包、6 项 XCUITest，均通过。原生 CoreText 112 个动作集合 / 阶段字形用例也通过。新增用例在每个 30fps 边界重放 20ms 字形提交延迟：旧时序会读到前一秒姿势，提前一个阶段准备后结果正确。
- 对 build 8 实际录像裁剪应用连续性判据，能检出约 30.443 秒处的窄正面姿势横跳再返回。build 9 增加实际视频分析：仅比较连续变化的屏幕画面，检测相邻短时窗内人物横向突跳、轮廓变窄再返回；覆盖录像中全部六个步行时窗，结果 `isolatedPoseJumps: []`、180 个明显变化样本。此判据针对已观察到的缺陷，不等于覆盖全部可能的视觉问题。
- 最终系统录像长约 268.79 秒，实际解码 10,292 帧，六个步行时窗共 645 个视频样本，保存 360 张未经重绘的人物裁剪。三个采样分钟均有实际人物，回 App 后活动仍在。已目视核对新裁剪中的左右迈腿、正常回正、单个人物轮廓，以及 14 个深浅页面和系统展开图；未再观察到上一候选的插入站姿。
- 明显画面变化之间、间隔 15–120ms 的 150 个相邻样本，中位间隔约 33.33ms，支持本次模拟器活跃步态约 30Hz 的目标节奏。此统计排除了待机长间隔和极短重复，不能称为全程稳定帧率，也不能代替用户真机帧率。录屏名义帧率约 38.51fps 仅属于视频容器。
- 最新字体资源与 build 8 一致：每个 bundle 61 个字体、10,787,176 字节，8×1800 帧计划。本机再次从最终 IPA 解码每个 bundle 的 1,004 个位图，96×96、alpha 全 255；136 种去重图像和 27,796 个重复引用。黑色覆盖面进入实际交付资源；App 图片继续透明。
- IPA artifact `12606976831`：下载 ZIP 64,206,492 字节，SHA-256 `154d3498b79f12e215342893f40772b39f951005d81a9f683a989caa130c0ef4`，与 GitHub digest 一致，ZIP CRC 全部通过。验证资料 artifact `12607121315`：8,317,170 字节，SHA-256 `73374d1917a5e79c7279813fe921249bd59cd4000b51c898f3e6eb8f54bc5a6c`，同样核对通过。
- 最终 IPA 为 `D:\gpt_workspace\ios_ldd\mAIverse-V1.5\mAIverse-V1.5-unsigned.ipa`，64,349,874 字节；SHA-256 `3ea3eb78a53f52c805dfd5919503768bf4da62a68d80758e36a83d1bf8c8b98f`，与 `SHA256SUMS.txt` 一致。App / Widget 版本均为 1.5（build 9），原 Bundle ID 和 `PlugIns/DragonIslandWidget.appex` 完整保留；本机真实 IPA 结构检查再次通过。旧 V1.4 文件夹保留，build 8 候选单独归档在 ignored build 目录，不作交付。
- `verification/` 保存最终页面 / 展开 / 连续裁剪图、界面日志、视频像素分析、连续性结果和本地包检查报告。大体积原始录像单列为[系统录像 artifact](https://github.com/yangtao990518/DragonIsland/actions/runs/40213328156/artifacts/12606971926)，完整截图单列为[截图 artifact](https://github.com/yangtao990518/DragonIsland/actions/runs/40213328156/artifacts/12607061591)，GitHub 保留期七天；未将前一候选录像冒充最终录像。
- 实现范围和边界见 `RELEASE_V1.5.md`：普通紧凑态播放，最小态与展开名称旁静态；每五秒一个时段、60 秒预排循环；减弱动态 / 息屏低亮度静态。没有新增服务器、逐帧后台更新、AI 聊天或响铃。Sideloadly 实际签名与用户 iOS 27.01 长时间体验未操作或验证，不能承诺真机锁定 30fps。安装前结束旧活动，并保留、签名 Widget 扩展。


## V1.6 build 10 候选：场景切换检查失败，未交付

- 源码 e31058ce4aebacc76a03318840335b2179447a1b，Actions 40217735834。App / Widget Release、14 项 Swift 模型、14 项 Python 资源 / 打包及 336 项原生字形检查通过。
- 7 项界面测试中，持续活动与原有图片 / 外观等 6 项通过；场景测试有两次失败：固定等待三秒后，紧凑态人物区仍显示上一种场景。持久化及展开态正确，但不能据此称当前场景即时应用成功。流程在界面失败时停止，未执行后续系统视频行程测量，也未交付该 IPA。
- 实际截图：切到草地后紧凑态暂留黑色；随后切到星夜时人物区仍为草地，倒计时区已为星夜，并出现人物淡化叠像。不是通过降低颜色像素门槛绕过检查。候选证据提取于 Actions 40218811759，本机 build/qa-v16-first；原诊断 artifact 12608500478。
- build 11 为场景更换计时视图身份、禁用切换时的交叉淡化；测试改为有时限地等待真实人物区出现所选场景，同时继续要求人物可见。结果待下一轮实际验证。


## V1.6 build 11 中间验证通过

- 源码 652584b6b89e1ea9872bc7f12d7f9c6dc0d8cf7f，Actions 40219306492 全部成功。35 项测试（14 Swift、14 Python、7 XCUITest）与 336 个原生字形用例通过。
- 场景切换测试现等待实际画面稳定到所选场景；草地 / 星夜的人物可见、内容颜色及保存重开均通过。系统视频分析检验三分钟中的六段去程 / 返程，每段屏幕行程至少 70 像素，连续性检查通过。
- 此包未交付；最终 build 12 为展开 / 锁屏补充独立 900×300 场景，改用优化编译的视频诊断程序以减少处理时间，再进行完整验证。最终包与校验值以后续记录为准。

## 最终交付 V1.6（内部 1.6 / build 12，2026-10-26）

- [最终构建 40220525320](https://github.com/yangtao990518/DragonIsland/actions/runs/40220525320)全部成功；源码 `f580a36efc82aa2b9c17de7e40511f9e9be28838`，job `121250908691`，macOS 15 / Xcode 16.4。App 与 Widget 真机 arm64 Release、模拟器 Debug、真实 IPA 结构检查和系统视频步骤均通过。
- 共 35 项测试通过：14 Swift 模型、14 Python 资源 / 打包、7 XCUITest；另有 CoreText 对三种场景 / 八套动作 / 选定阶段的 336 个原生字形用例通过。新用例覆盖旧会话回退黑色、场景编码且保持计时 / 动作、完整往返与端点不裁切，以及三种不透明背景清除旧姿势。
- 实际系统场景测试从正在进行的黑色活动切换到草地、再到星夜；有时限地等待人物区真正显示所选颜色，同时保持人物可见，随后检查展开并重开 App 确认保存。两种彩色紧凑态、展开态截图均已目视核对，未再出现首轮候选的旧背景滞留。此检查不声称 API 返回就代表系统已显示新画面。
- 原始 SpringBoard 录像约 289.84 秒，解码 13,003 帧，选取 1,861 个完整步行时窗样本，保存 753 张未经重绘的人物裁剪。六段单程（第 0 / 1 / 2 分钟各去程、返程）的屏幕行程分别为 101 / 101、101 / 101、100.5 / 101 像素，超过 70 像素门槛；去程和回程连续，人物在两端完整，已目视查看逐图联系表。
- 视频连续性结果 `isolatedPoseJumps: []`，753 个明显画面变化样本。判据针对已观察到的窄正面姿势短暂横跳再返回，不代表穷尽所有视觉缺陷。实际画面变化中，15–120ms 的 728 个相邻间隔中位数约 35ms；排除了待机与极短重复，不能用于保证全程或真机锁定 30fps。录屏名义帧率约 45.31fps 属于视频容器。
- 实际导出并检查 18 张页面截图的联系表：原有七页深浅两色，加草地 / 星夜的关于页和任务页。展开背景采用独立 900×300 资源，已核对完整月亮与地形、立绘、短句、三个按钮。此轮未捕获真实系统锁屏卡片，锁屏配色与长期息屏仍待手机验证。
- 本机从最终 IPA 逐一解析 App / Widget：二者均为 1.6（build 12），原 Bundle ID `com.dragonisle.prototype.app` / `.app.widget` 关系保留，`PlugIns/DragonIslandWidget.appex` 完整。每个 bundle 181 个字体、14,778,632 字节，三种场景各 60 个阶段字体与一个公共遮罩；8×1800 帧计划、180×96 舞台及 100 像素设计行程完整。
- 本机解码每个 bundle 的全部 2,802 个直接位图，均为 180×96、alpha 全 255；全局去重后 855 种图像，另有 83,598 个重复引用。实际计划中的相邻去程 / 返程、1.125 秒步态和一秒单次打滚时长再次核对。结果在 `verification/release-verification.json`。
- IPA artifact `12609329461`：下载 ZIP 为 65,683,356 字节，SHA-256 `9725c11ad5809ae25d79c27387791c10c5a35389ffc45f97cc7bd8320eafe573`；验证资料 artifact `12609695211`：25,129,876 字节，SHA-256 `361352e24629e8d35428fe757b348ad7372ce9c8e0c46fddb22828a04d59bae5`。两者均比对 GitHub digest 且全部 ZIP CRC 通过。
- 最终本机 IPA：`D:\gpt_workspace\ios_ldd\mAIverse-V1.6\mAIverse-V1.6-unsigned.ipa`，66,172,253 字节；SHA-256 `b3cd275551a8724522ace9bddaf96e14f938e145dd2d8e07f8305c1348e23024`，与产物清单一致，真实 IPA 结构检查再次通过。安装说明、改动、测试说明及实际截图 / 视频裁剪位于同一版本目录，现有 V1.5 目录未修改。
- 大体积原始录像单列为[系统录像 artifact](https://github.com/yangtao990518/DragonIsland/actions/runs/40220525320/artifacts/12609587711)，完整截图单列为[截图 artifact](https://github.com/yangtao990518/DragonIsland/actions/runs/40220525320/artifacts/12608944909)，GitHub 保留七天。本机保留最终实际裁剪和分析，未用中间候选冒充最终验收。
- 原有竖屏警告和视频脚本 AVFoundation API 弃用提示未阻止构建。系统黑色外壳保留，彩色图形是 App 内容；仅普通紧凑态装载完整动画，最小态与展开名称旁静态。保持 30fps 目标、预排 60 秒循环、减弱动态 / 息屏低亮度静态；未操作 Sideloadly 或用户 iPhone，不声称已完成真机签名、长期稳定性、内存或耗电测量。升级后结束旧活动再开始，并保留、签名 Widget 扩展。
