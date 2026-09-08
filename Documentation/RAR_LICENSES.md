# 客户 RAR 许可证与隐私

Arcora 1.2.0 不分发 RAR 编码器或许可证。先按设置中的官方链接下载并导入原包，再导入客户自己的 rarreg.key。RAR4/RAR5 浏览和解压不要求导入许可证。

## 导入与核验

设置 → 引擎 → 导入 RAR 许可证，选择 RARLAB 或授权经销商发送的原始 rarreg.key，确认其授权覆盖当前电脑，然后“导入并核验”。不要提供截图、购买凭证、共享注册码或他人许可证。

仅接受非空、非符号链接的普通文件，大小上限 16 KiB。基本结构检查不是真实性校验；随后由官方 RAR 的注册响应核验，不能仅凭文件存在或退出码为 0 宣称已注册。未知输出保持锁定。失败候选不替换旧许可证，每次创建前重新检查。

目前未获提供真实购买的测试许可证；正向存储事务测试使用明确无效的测试数据和内部模拟验证器，不能作为真实激活证据。真实官方引擎对无效许可证的拒绝已经纳入回归。

## 本机存储

导入副本：
```text
~/Library/Application Support/Arcora/RARLicense/config/rar/rarreg.key
```

同目录 arcora-acceptance.json 仅记录 schema、许可证摘要及客户确认，不保存注册人姓名或正文。目录权限 0700，key 和记录 0600。导入在独立私有目录核验，成功后原子替换整套 key 和记录。

按官方 macOS 原包 order.htm，RAR 支持 $XDG_CONFIG_HOME/rar/rarreg.key。Arcora 仅对 RAR 子进程设置该路径，不修改用户 HOME，不覆盖其他 RAR 的许可证，不修改签名 App。许可证不上传、不遥测、不放入日志或发行包；RAR 诊断中的注册人信息会被隐藏。

“移除导入副本”把本应用的许可证副本移到废纸篓，原始文件不变；RAR 创建随即锁定。废纸篓、系统备份、交换文件或系统崩溃转储可能保留副本，应用不承诺系统级安全擦除。移除编码器不会删除客户许可证。

## 使用权

客户确认与引擎注册状态不能证明购买渠道真实、许可未撤销、转让有效或企业席位足够。请遵守 [RARLAB 官方条款](https://www.rarlab.com/license.htm)，并通过 [官方渠道](https://www.rarlab.com/registration.php)购买覆盖实际使用电脑/设备的许可。详见 [交付方案](RAR_DELIVERY.md)。

## 命令行

```bash
Arcora.app/Contents/Helpers/arcora rar-license-status
Arcora.app/Contents/Helpers/arcora rar-license-import /private/path/rarreg.key --acknowledge-rar-license
Arcora.app/Contents/Helpers/arcora rar-license-remove
```

--rar-license-directory 可指定隔离测试目录，不会关闭许可证验证。不得把许可证放到源码、Vendor、dist、普通 CI 工件或公共日志。--rar-engine-directory 只隔离本地原包导入目录，不提供网络下载功能。
