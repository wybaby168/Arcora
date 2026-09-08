# macOS 构建、签名、公证与发布

本次已完成 macOS universal 编译和本机运行验证，尚未执行 Apple 公证或客户发布。所有证书、团队 ID、账号和服务密钥均由实际发行者提供，不写入仓库。当前结果见 TEST_REPORT.md。

## 本地开发构建

```bash
./Scripts/bootstrap-engines.sh
./Scripts/build-app.sh
open dist/Arcora.app
```

脚本编译 Apple Silicon 和 Intel 原生二进制，核验架构并对应用与 Helpers 签名。默认 ad-hoc 签名只适于开发验证，不是可向用户承诺“无安全提示”的发行版。

检查 `Configuration/Info.plist` 中的 `CFBundleIdentifier`、版本、名称和最低系统要求。`app.arcora.desktop` 是此源码的工作标识，正式发布前修改为发行者控制的标识；变更需要一致处理偏好迁移与签名。产品名称尚未完成商标法律检索。

## Developer ID 构建

在 Keychain 中安装发行者的 Developer ID Application 证书，并确认该身份可以使用。

```bash
export SIGN_IDENTITY='Developer ID Application: YOUR LEGAL NAME (TEAMID)'
./Scripts/build-app.sh
```

脚本为引擎、工作进程、CLI 和应用启用签名；发行身份使用 hardened runtime 和时间戳。不要对应用包修改文件后继续使用旧签名。

## 公证

按 Apple 当前文档在本机 Keychain 预先保存 `notarytool` profile。此处不提供或保存任何 Apple ID 密码、应用专用密码或 API 私钥。

```bash
export NOTARY_PROFILE='YOUR_KEYCHAIN_PROFILE'
./Scripts/notarize.sh
```

脚本检查 Developer ID 签名、生成提交 ZIP、等待 notarytool 返回、staple 应用并执行 Gatekeeper 验证。失败时停止，不把未公证产物标记成正式版本。得到的发行 ZIP 名称以脚本输出为准。

## DMG

```bash
./Scripts/make-dmg.sh
```

生成包含 Arcora.app 和 Applications 链接的只读压缩 DMG。建议先公证并 staple App。脚本可给 DMG 签名，但不自动替 DMG 完成独立公证；需要发布公证 DMG 时，再按 Apple notarytool 流程提交 DMG、staple 并验证下载后的 Gatekeeper 行为。

## 发行内容与许可证

App 内包含 7-Zip、libarchive、XZ 对应原始源代码压缩包与许可文件，位于 `Contents/Resources/ThirdParty`。不要在“瘦身”时删掉这些材料。Arcora 的 MIT 许可证不替代这些依赖的许可证或 unRAR 限制；当前发行包严格不包含 RAR 编码器、RAR 原包或许可证；可选 RAR 创建通过官方下载链接、本地原包导入和客户许可证启用，见 RAR_DELIVERY.md。

发布 ZIP / DMG 时一并保留第三方说明。若修改上游 7-Zip、改为静态链接、添加其他解码器或采用不同分发方式，需要重新审查对应源代码、重新链接等许可义务。本说明不是全面法律意见。

## 自动化

仓库含 `.github/workflows/ci.yml`。在实际 GitHub 仓库运行后，会在 macOS runner 上检查三语文案、获取已锁定引擎、编译、运行核心和真实 7-Zip 集成测试、生成 Universal ad-hoc 测试包。设置 `ARCORA_REQUIRE_7ZZ=1`，防止因依赖缺失把跳过当作绿色成功。

每次提交的实际 CI 状态以 [GitHub Actions](https://github.com/wybaby168/Arcora/actions/workflows/ci.yml) 为准；存在工作流不等于工作流已成功。公开 CI 不下载 RAR，可选编码测试会明确跳过。完整 RAR 集成仅在私有环境合法配置 `ARCORA_RAR` 时执行，不把 RAR 原包、注册文件或本地应用上传到普通 CI artifact 或日志。

正式发行使用 `bash Scripts/release-rar.sh`，要求 Developer ID Application、公证 profile、`ARCORA_RELEASE_RAR_PACKAGE` 和 `ARCORA_RELEASE_LICENSE_FILE`。后两项仅供隔离目录中的真实原包导入、注册和加密分卷往返验收，不进入 App。构建拒绝分发 RAR 编码器，发行扫描也拒绝注册文件和本地评估开关。没有真实许可证的锁定验证不是正向激活验收。遗留 `.local` 编解码评估包绝不用于客户分发。

## 最终门槛

在 Apple Silicon 与 Intel 的目标环境完成 MACOS_ACCEPTANCE.md，验证可信下载的实际用户安装过程、所有主流格式往返、中文 / 日文布局、加密 / 分卷、损坏 / 磁盘满 / 取消，以及大文件峰值内存与界面响应。缺少这些结果时应标记开发构建，而不是宣称稳定正式版。
