# mAIverse 版本与交付命名

用户确定从 V1.0 开始对外编号，当前版本是 **V1.6**，后续按 V1.7、V1.8 等版本交付。早期原型记录中的 0.x 内部版本保留为历史事实，不回写旧产物或校验值。

- `project.yml` 的 `MARKETING_VERSION` 使用纯数字版本，例如 `1.6`，供 App 和 Widget 共用。
- `CURRENT_PROJECT_VERSION` 为递增的构建号，当前为 `10`；保持递增以支持覆盖更新。
- App 的“关于”页显示 `mAIverse V1.6`，直接读取安装包的真实版本。
- 本机交付目录必须带版本号：`D:\gpt_workspace\ios_ldd\mAIverse-V1.6\`。IPA、安装说明、测试说明与截图放在该目录中；保留旧版本目录。用户关心的是本机文件夹，单独修改 GitHub 名称或 IPA 文件名不能替代此要求。
- IPA 名称为 `mAIverse-V1.6-unsigned.ipa`，Actions 下载包名称为 `mAIverse-V1.6-unsigned`。
- 文件名由构建后的主 App Info.plist 自动生成，之后修改版本配置即可同步，避免手动重命名导致包内版本与文件名不一致。
- 版本更新时保留主 App 和扩展 Bundle ID，并同时签名扩展。

每次交付后，在 `docs/VALIDATION.md` 记录实际版本、构建结果、产物校验值及尚未完成的真机验证。
