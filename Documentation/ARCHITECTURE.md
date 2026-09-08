# Arcora 架构

## 分层与边界

```text
SwiftUI / AppKit (MainActor)
    │ 编辑参数、拖放、浏览、任务状态、Quick Look
    ▼
AppModel 调度器
    │ 有界并发、总线程数、估算内存、会话内 Secret
    ▼ Task.detached
ArchiveService
    ├─ 元数据 / 分卷识别 / 安全预检
    ├─ ProcessRunner → 官方 7zz 或用户授权 rar
    └─ ProcessRunner → arcora-worker → CArcora → 静态 libarchive + liblzma（macOS）
    │
    ▼
目标磁盘上的私有 Workspace → 复检 / 测试 → 独占 rename 提交
```

没有 Electron、WebView、JavaScript、后端服务或压缩数据 HTTP 上传。引擎是编译成本机代码的独立可执行文件；不是把压缩器在主线程内同步调用。C 桥接是原创安全 I/O 封装，不是自行实现 ZIP / RAR 编解码器。

## 工程模块

`Models.swift` 定义格式能力、压缩参数、保守内存估计、限制、条目、错误及进度事件。参数先校验后构建命令，不为不支持的格式展示无效能力。

`Secret.swift` 持有非 Codable 的密码缓冲区并尽力清理；`ProcessRunner.swift` 使用结构化参数数组，密码通过 stdin 单独发送。输出按块消费并限制保留大小，避免 stdout / stderr 独立管道互相阻塞。普通诊断和错误会去除密码值；成功的结构化目录列表不对内容做密码替换，以免密码恰好是文件名子串时破坏真实元数据。

`SevenZip.swift` 管理引擎定位、7-Zip 与 RAR 参数和 SLT 目录解析。开发 CLI 可以显式指定 `ARCORA_7ZZ` / `ARCORA_RAR`；打包 GUI 和 CLI 使用应用 Helper，不受外部同名环境变量或开发工作目录影响。RARPackage.swift 按实际硬件（包含 Rosetta）提供官方原包链接，RARInstallationStore 仅导入本地原包：先校验固定摘要，再安全解包，保留完整原包/条款并原子提交到应用私有目录。无运行时下载器。RARLicenseStore 在独立私有 XDG 配置目录核验客户许可证；GUI 和打包 CLI 创建前都重新核验受管理引擎及注册状态。开发显式工具覆盖仅用于合法编解码评估，客户包不采用环境变量绕过许可证。

`NativeArchive.swift` 和 `arcora-worker` 通过 JSON Lines 传输条目 / 进度 / 错误。目录元数据按条目生成；主应用最多接收设定的目录数据总量。普通文件内容不经过 JSON，也不全部缓存到 Swift 内存。

`Safety.swift` 管理路径验证、输入检查、输出审计、私有 Workspace 和独占提交。`Volumes.swift` 对同目录匹配卷排序并检查序号，不通过不可靠后缀猜测修补实际文件内容。

## 任务调度

AppModel 维护 FIFO 等待队列，结合 `maxConcurrent`、总线程预算、每任务估算内存决定是否启动。压缩选项和 Secret 在排队时快照保存到当前会话，不把密码写入持久化队列。

任务有 queued / running / paused / succeeded / failed / cancelled / interrupted 状态。JobControl 处理取消、暂停和当前子进程引用。暂停通过 SIGSTOP / SIGCONT；取消先终止，再在必要时强制杀死未退出的受控进程。超时计时不把暂停时间算入活动执行时间。进程状态同步避免对已回收任务继续发送控制请求。

应用关闭时请求取消并等待；重新启动读到未完成历史会标记 interrupted，不虚构已恢复或继续压缩。历史仅保存结果元数据，不保存可自动重放的秘密或执行命令。

## 性能设计与限制

C 路径按 64 KiB 缓冲流式解码 / 写入；ProcessRunner 按块持续排空管道。普通日志仅保留最后 1 MiB；完整目录传输默认上限 64 MiB。最大条目数默认 250,000，避免无界元数据增长。输入文件内容不整体读入内存。

压缩到 TAR 组合格式需要两阶段，中间 TAR 会占用额外磁盘空间；不伪称零中间文件。固实压缩 / 选中项解压可能需要扫描未选中数据，但最终只提交选择项。

GUI 目录聚合和搜索在可取消的后台任务中计算，并使用版本标记避免旧结果覆盖新目录。原生 Table 提供行虚拟化；排序仍须按实际数据规模做 macOS 性能验收。未提供任何伪造的 GB/s、CPU 利用率或内存峰值跑分。

线程 / 内存预算是调度控制；不等于对外部编解码器强制施加系统级资源隔离。libarchive 路径是单档案串行；格式和引擎决定实际内部并行度。

## 发布与系统集成

Swift Package 避免额外项目生成器。Universal 构建分别编译 arm64 / x86_64，再 lipo 合并。GUI 与 CLI 放在不同目录，避免大小写不敏感文件系统的命名冲突。三语资源由 Bundle 中的专用资源包读取。

Info.plist 声明扩展名和 Finder 服务，并使用 Alternate 角色，不主动篡改用户默认打开方式。AppKit 提供打开 / 保存面板、剪贴板、Finder reveal、Quick Look 和应用终止协调。

直接分发使用 Developer ID 签名、公证和 Gatekeeper 验证。当前代码未完成 App Sandbox / Mac App Store 特有 entitlement、安全作用域书签和所有商店政策审查，因此不应作为“可直接上架”工程宣传。
