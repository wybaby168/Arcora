# RAR 交付方案 · Arcora 1.2.0

标准公开版按 Mac 硬件架构打开 RARLAB 官方原包链接；客户在浏览器下载后，由 Arcora 一键导入和配置原包，再导入客户自己的许可证。无需手工解压、命令行、Homebrew 或管理员安装。本机专用内置版本见 [LOCAL_RAR.md](LOCAL_RAR.md)，不属于可分发产品。

产品及源码交付包不包含 RAR 编码器、RAR 原包或客户许可证。运行时没有自动下载器、镜像、转发服务器或静默安装；只有用户主动点击的官方网页链接和本地文件导入。RAR/RAR5 浏览、校验和解压不需要以上配置。

## 客户操作

1. 设置 → 引擎 → 打开官方下载。Apple Silicon 选择 ARM 原包，Intel 选择 x64；在 Apple Silicon 上以 Rosetta 运行 Arcora 也优先原生 ARM。
2. 下载完成后点击“导入原包并配置”，选择未经解压或修改的 .tar.gz。Arcora 校验固定版本、架构和 SHA-256，并在用户应用目录配置。
3. 点击“导入 RAR 许可证”，选择自己购买的原始 rarreg.key，确认使用权覆盖本机。官方 RAR 确认注册状态后启用创建。

当前固定 RAR 7.23。[官方下载页](https://www.rarlab.com/download.htm)提供 ARM 与 x64 原包，具体文件与摘要见 Vendor/engines.lock.json。摘要在开发阶段固定，不是声称上游发布了签名摘要。未知版本、改动、损坏和错误架构均拒绝导入，不会自动追随新下载或不受信任的镜像。上游撤下旧版本时需要维护者核验新版本后更新应用；不得关闭摘要检查作为兼容手段。

浏览器可能自动解压安全下载（如 Safari 的相应设置）。请保留原始 .tar.gz，必要时在浏览器关闭自动解压或从废纸篓恢复原包后重试；不要重新打包。

## 本机安全与隐私

编码器及完整原包存放于 ~/Library/Application Support/Arcora/RAREngine/current。全部官方文件、说明和条款保留，不运行上游安装脚本，不修改系统目录。导入验证和解包在临时私有目录进行，成功后整目录替换；失败或取消保留旧配置，原始下载不变。

原包摘要先验证，再使用静态集成的 libarchive 解包；限制文件数和展开大小，拒绝危险路径、链接和特殊文件，核验 rar 可执行文件摘要。每次创建重新核验受管理编码器及注册状态。不会清除 quarantine、关闭 Gatekeeper 或重新签名官方文件；如 macOS 阻止运行，需要按系统提示由用户处理。安装便利性不等于绕过系统安全。

许可证保存在单独私有目录，详见 [许可证与隐私](RAR_LICENSES.md)。未导入、无效或核验失败时，GUI 与打包 CLI 均锁定 RAR 创建，解压仍然可用。删除导入副本只移到废纸篓，不删除客户原始文件。

## 合规边界

此方案避免将 RAR 软件随产品交付、重新托管或通过应用下载器提供组合下载。它是工程层面的分发边界，并非 RARLAB 对本产品的书面认可或全面法律保证。

[RARLAB EULA](https://www.rarlab.com/license.htm)（2026-09-08 核对）区分软件分发、试用与客户使用权。客户自带许可证不能替代任何另行需要的分发许可；若将来改为捆绑编码器或应用内下载安装，应先另行审查并取得所需书面许可。商业席位及使用范围由客户遵守官方条款。引擎显示已注册不等于购买来源、转让、撤销或席位数量的法律审计。

默认 build-app.sh 拒绝 ARCORA_RAR_DISTRIBUTION_DIR；assert-distribution-clean.py 拒绝编码器、原包、注册文件和评估开关。保留的 package-rar.py 是未启用的授权组件工具，不属于当前发行流程，不能用它绕过默认构建检查。

## 验证和发行

```bash
bash Scripts/build-app.sh
python3 Scripts/assert-distribution-clean.py dist/Arcora.app
python3 Scripts/verify-app.py dist/Arcora.app --require-rar \
  --rar-package /private/path/to/rarmacos-arm-723.tar.gz --expect-license-required
```

Intel Mac 使用对应 x64 原包。验证器创建独立临时编码器和许可证目录，不读取或覆盖客户配置。无证测试不能替代真实购买许可证的正向验收。

正式发布使用 Scripts/release-rar.sh，需要：
- SIGN_IDENTITY：真实 Developer ID Application 证书。
- NOTARY_PROFILE：发行方 Keychain 中的 Apple 公证配置。
- ARCORA_RELEASE_RAR_PACKAGE：本机对应的官方原包，仅在临时测试中导入，不打包。
- ARCORA_RELEASE_LICENSE_FILE：发行者合法持有且适用于本机的真实测试许可证，不打包、不输出正文。

流程核验发行包无 RAR 编码器或许可证、真实注册和加密分卷往返，然后签名、公证 App/DMG。当前没有真实测试许可证、Developer ID 和公证凭证，因此不能把本地构建标为已经完成正式发行验收。参见 TEST_REPORT.md 与 MACOS_ACCEPTANCE.md。
