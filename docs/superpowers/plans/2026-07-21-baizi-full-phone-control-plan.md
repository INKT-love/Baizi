# 白子完整手机控制实施计划

> 前置设计：[完整手机控制设计](../specs/2026-07-21-baizi-full-phone-control-design.md)

## 实施原则

- Android 专属实现；非 Android 平台不注册手机工具、不显示配置入口。
- 不允许模型直接运行原生命令。所有调用经 Flutter `PhoneControlService` 和 Android `PhoneControlCoordinator` 验证。
- 复用现有本地工具链：`LocalToolsService` 提供定义，`ToolHandlerService` 负责调用分发，`ToolApprovalService` 承接待确认操作。
- Shizuku 是首选执行通道，Root 是补充；界面读取和操作统一依赖无障碍服务。
- 任何阶段必须保留现有聊天、角色卡、经期关怀、更新检测和后台任务行为。

## 阶段 1：基础模型、通道与首次配置

### 1. Android 依赖和清单

修改 `android/app/build.gradle.kts`，加入 Shizuku API 与 AIDL 依赖，保持现有 R8 和 ABI 配置。新增 AndroidX 无障碍、前台任务所需依赖只在确有对应原生组件时引入。

修改 `android/app/src/main/AndroidManifest.xml`：

- 注册 `PhoneControlAccessibilityService`，声明无障碍元数据 XML。
- 注册前台执行服务与工作流调度接收器（仅在后续阶段实际实现后加入）。
- 仅声明实现功能真正需要的权限；不使用无关的广泛存储权限作为替代方案。

新增 `android/app/src/main/res/xml/phone_control_accessibility_service.xml`，声明读取窗口内容、执行手势和检索节点所需的无障碍能力。

### 2. 原生控制中枢

新增 `android/app/src/main/kotlin/com/psyche/kelivo/phonecontrol/`：

- `PhoneControlCoordinator.kt`：单一执行队列、能力检查、工具分发、超时、取消和事件发布。
- `PhoneControlModels.kt`：状态、能力、结果、风险、执行策略和错误代码。
- `PhoneControlMethodChannel.kt`：在现有 `MainActivity.kt` 注册 `baizi.phone_control`，暴露状态、连接、执行、取消和设置操作。
- `ShizukuAdapter.kt`：监听 Binder 状态、请求授权、执行系统/Shell 能力。
- `RootAdapter.kt`：检测 `su`，以参数数组和超时运行受控命令，绝不拼接不可信命令文本。
- `AccessibilityAdapter.kt`：与服务通信并提供可用状态。

在 `MainActivity.kt` 只安装桥接和转发 Activity 生命周期；不要把业务逻辑继续堆入现有文件。

### 3. Flutter 手机控制基础

新增 `lib/features/phone_control/`：

- `models/phone_control_models.dart`：Dart 枚举和序列化模型，与原生结果一一对应。
- `services/phone_control_platform.dart`：唯一 `MethodChannel` / `EventChannel` 客户端。
- `services/phone_control_service.dart`：能力刷新、策略持久化、工具执行、运行中任务和日志摘要。
- `providers/phone_control_provider.dart`：供设置和聊天 UI 监听的状态。
- `services/phone_control_risk_policy.dart`：风险分级与三种确认策略的纯 Dart 判定。

在 `lib/main.dart` 注册 Provider，仅在 Android 实例化原生桥接；在 `SettingsProvider` 中持久化确认策略、是否启用手机控制、截图/UI 树保留偏好。

### 4. 傻瓜式配置 UI

新增 `lib/features/phone_control/pages/phone_control_setup_page.dart` 和组件目录。设置页 `lib/features/settings/pages/settings_page.dart` 增加“手机控制”入口，页面按以下顺序引导：

1. 首先检测并连接 Shizuku，显示推荐标记与“检查并连接”。
2. Shizuku 不可用时才突出显示 Root；Root 可用则提示已可作为补充通道。
3. 打开无障碍系统设置并实时检查返回状态。
4. 选择按风险确认、全部确认或全部允许；开启全部允许必须使用明确的二次确认对话框。

高级页面展示诊断信息、通道重连、日志和立即停用。配置未完成时，聊天入口仅导航至此页面。

### 验收

- 未安装或未启动 Shizuku、未授予 Shizuku、Root 不可用、无障碍关闭时均显示准确可操作状态。
- 全部允许只在用户完成二次确认后写入；切回默认策略立即影响之后的任务。
- Android 以外平台无崩溃、无手机工具定义、无设置入口。

## 阶段 2：工具协议、审批与聊天执行卡

### 1. 本地工具定义与分发

扩展 `lib/features/home/services/local_tools_service.dart`：新增 `PhoneControlToolNames` 或独立 `phone_control_tools.dart`，以分组、稳定的函数名和精简 JSON Schema 注册观察、界面、系统、文件、Shell 与工作流工具。工具仅在以下条件同时满足时暴露：Android、手机控制总开关开启、当前模型支持函数调用、至少一个需要的基础能力可用。

扩展 `lib/features/home/services/tool_handler_service.dart`：在现有本地工具前后接入 `PhoneControlService`。统一错误结果保持现有 `tool_error` 格式，并回传可执行的恢复建议。

不要将手机控制伪装为 MCP 工具，也不修改现有 MCP 选择或审批逻辑。

### 2. 风险与确认

扩展 `lib/features/home/services/tool_approval_service.dart`，支持手机控制的风险级别、等待用户状态、单个任务取消和“本次会话允许”所需元信息；现有 MCP 审批行为不得改变。

实现策略：

- 按风险确认：观察和安全导航直接运行，高风险工具请求批准。
- 全部确认：所有改变设备状态的工具请求批准。
- 全部允许：不生成逐项批准请求，但依然经过参数、能力和系统保护页检查。

### 3. 聊天 UI

新增 `lib/features/phone_control/widgets/phone_control_execution_card.dart`，在现有消息工具展示路径中渲染：当前步骤、进度、摘要、展开详情、停止、等待用户接手、完成和失败状态。

扩展相关聊天消息模型时保留向后兼容的 JSON 解析。截图、UI 树和命令输出仅在展开后显示；默认不永久存储。

### 验收

- OpenAI 与 Anthropic 格式的工具调用均能获取相同手机工具定义和结构化结果。
- 三种确认策略按设计触发或跳过审批，停止按钮可取消未开始和可取消的当前动作。
- 失败、取消、无权限和受保护页面的卡片状态清晰且不阻塞下一条普通聊天。

## 阶段 3：无障碍 UI 自动化与观察

### 1. 无障碍服务

新增 `PhoneControlAccessibilityService.kt`、节点序列化和操作辅助类：

- 提取压缩且有边界信息的 UI 树，过滤无意义节点并限制深度、节点数和文本长度。
- 支持按资源 ID、文本、描述、类名、可点击属性和屏幕坐标定位。
- 支持点击、长按、输入、滚动、返回、主页和通知栏。
- 每次执行后校验窗口或目标节点变化；找不到目标时返回明确错误而非盲点。

### 2. 屏幕观察

实现 Android 允许的截图路径与用户授权流程。图片在进入聊天工具结果前压缩、限尺寸、限频率；不可截图时返回 UI 树和原因，不以失败掩盖当前状态。

### 3. 工具实现

实现 `get_ui_tree`、`capture_screen`、`find_element`、`tap`、`long_press`、`input_text`、`scroll`、`back`、`home`、`open_notifications` 和 `get_device_state`。所有工具在 Coordinator 中共享取消、超时、风险和结果转换逻辑。

### 验收

- 真实设备上可读取常见应用 UI、按可见文本点击、输入和滚动。
- UI 变更时最多重新读取并定位一次；之后停止并回传失败原因。
- 锁屏、支付、生物识别和受保护页面不能被自动绕过，任务进入等待用户状态。

## 阶段 4：系统、应用、文件与命令能力

### 1. 系统与应用

通过 Shizuku 优先、Root 退回实现应用枚举、启动、停止、包信息、主页/最近任务、音量和亮度、允许范围内的系统状态开关、通知与剪贴板操作。每项工具声明需要的能力与风险，不能执行时解释需要 Shizuku、Root 还是无障碍。

### 2. 文件与包管理

实现文件列举、读取、创建、写入、复制、移动、删除、压缩、解压以及应用安装、卸载。使用路径规范化和允许范围校验，阻止路径穿越。删除、卸载和覆盖写入标为高风险，但在全部允许策略下依照用户已确认的规则直接执行。

### 3. Shell

实现受控 `run_shell`：参数使用列表传递，设置运行时长、输出大小和退出码；日志中隐藏敏感片段。命令结果归一为工具结果，不向模型泄露原始异常堆栈。

### 验收

- Shizuku 可用时优先选择它；未满足时才显示 Root 回退。
- 文件、应用和 Shell 的错误均包含操作摘要、错误代码和恢复建议。
- 命令超时、输出超限、无 Root、无 Shizuku 或路径不合法均不会导致应用崩溃。

## 阶段 5：工作流、后台任务与历史

### 1. 工作流模型和存储

新增 `PhoneControlWorkflowStore`，存储工具步骤、参数模板、触发规则、启停状态、最近执行摘要和版本。采用现有本地数据模式并提供迁移策略。

### 2. 调度与恢复

复用项目既有 WorkManager 组织方式，为定时和条件触发建立独立 Worker。后台任务只能执行仍具备授权的步骤；如果需要前台界面或无障碍实时交互，发送通知并等待用户回到应用，不伪造成功。

### 3. 历史与高级设置

新增工作流与执行历史页面：可暂停、恢复、取消、查看摘要、删除用户主动选择的记录。清理日志或工作流文件前必须在 UI 列出确切项目并请求确认。

### 验收

- 工作流重启应用后仍可恢复定义和状态。
- 后台权限丢失、通道断开、需要解锁或受保护页面时任务停止并通知用户。
- 历史记录默认只含摘要，截图/UI 树/Shell 输出遵循用户的保留开关。

## 阶段 6：测试、兼容性、构建与发布

### 测试

新增 Dart 单元测试：策略判定、工具 Schema、通道选择、结果映射、路径校验、工具处理分发和任务状态机。扩展 Flutter widget 测试覆盖配置向导、全部允许二次确认、状态卡、执行卡和非 Android 隐藏行为。

增加 Android 原生测试覆盖 Coordinator、Shizuku/Root 状态转换、无障碍节点序列化和 Shell 超时。使用真实 Android 设备验证至少一个原生 Android 系统和一个厂商系统。

执行现有完整测试集，重点回归聊天流式输出、经期关怀、后台任务、更新检查和 ABI 分包。

### 发布

在 ASCII 工作副本 `E:\Tools\BaiziBuilds\workspace` 构建。继续只输出 `arm64-v8a` 与 `armeabi-v7a`，不构建 x86；保留 R8、资源压缩和签名配置。发布 APK 命名为 `Baizi-<version>-armv8a.apk` 和 `Baizi-<version>-armv7a.apk`，放至 OpenList `/Baizi/<version>/` 并同步 GitHub Release 与更新清单。

发布说明按正常版本日志描述完整手机控制功能和必要授权，不能声称绕过 Android 系统安全保护。
