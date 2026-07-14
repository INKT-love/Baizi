# 白子 LLM 客户端实施计划

- 日期：2026-07-14
- 依据：`docs/superpowers/specs/2026-07-14-baizi-llm-client-design.md`
- 上游基线：`c8c9ff3`

## Mini Control Contract

### Primary Setpoint

把 Kelivo 改造为 Android 应用“白子”：固定单一网关、单 Key、统一模型列表、按模型名自动选择 OpenAI/Anthropic 流式协议，并完整支持 V1/V2/V3 PNG/JSON 酒馆角色卡；保留非供应商类高级功能。

### Acceptance

- 单元与组件测试证明 URL、鉴权、协议路由、角色卡解析、备份脱敏和 UI 状态转换符合设计。
- `flutter gen-l10n`、`flutter analyze`、`flutter test` 通过。
- `flutter build apk --release` 或等价 Android release 构建通过。
- Android 真机完成关键路径验收。

### Guardrails

- 不提交真实 API Key、签名文件或其他凭据。
- 不允许备份、旧偏好或高级设置覆盖固定网关。
- 不破坏聊天、消息、Assistant 和 WorldBook 的现有持久化兼容。
- 所有新增用户可见文字同步进入四份 ARB。
- 不手工编辑本地化和 Hive 生成文件。
- 不把桌面适配纳入首版验收，也不为此扩大改造范围。

### Boundary

主要范围：`lib/core/**`、`lib/features/home/**`、`lib/features/model/**`、`lib/features/settings/**`、`lib/features/provider/**`、`lib/features/assistant/**`、`lib/features/world_book/**`、`lib/l10n/*.arb`、`android/app/**`、`pubspec.yaml`、相关测试与品牌资源。

非目标：服务端实现、白子 API 行为修改、Android 签名凭据、应用商店发布、其他平台完整适配。

### Risks

1. Kelivo 多个后台功能绕过主聊天入口，若遗漏会产生协议或 URL 漂移。
2. PNG 角色卡元数据格式复杂，错误的解压或边界处理会造成安全与兼容问题。
3. Provider 配置与模型选择深度耦合，移除 UI 时必须保留高级功能所需的请求上下文。

## 最小场景集

### 正常路径

- 新用户填写有效 Key，获取全部模型，选择 GPT 模型并收到 OpenAI 流。
- 选择 Claude 模型并收到 Anthropic 流。
- 导入 V1/V2/V3 JSON 与 PNG 卡并创建角色会话。
- 从设置进入搜索、MCP、TTS、备份等高级功能。

### 边界输入

- `CLAUDE`、`my-claude-alias`、不含 `claude` 的模型 ID。
- 空模型列表、模型列表很大、重复模型 ID、选中模型下架。
- 最大允许角色卡、压缩 PNG 元数据、多开场白、大型世界书。
- 同名角色导入、未知角色卡扩展字段、空用户昵称。

### 失败路径

- 无效 Key、401、403、TLS 错误、超时、SSE 中断、用户取消。
- 损坏 PNG、CRC 错误、截断块、压缩炸弹、无效 Base64/UTF-8/JSON。
- 备份中含旧 Provider、旧 Base URL 和旧 Key。
- 安全存储不可用或读取失败。

## 阶段 1：基线、规格与品牌壳

1. 记录干净工作树、上游提交和可用 Flutter/Android 工具链。
2. 写入并审查设计规格和本实施计划。
3. 更新 Android applicationId、应用名称、关于页和 AGPL/Kelivo 来源说明。
4. 禁用 Kelivo 更新源，避免白子跳转到上游安装包。
5. 添加品牌与 package 配置测试。

验证：品牌搜索、Android manifest/Gradle 检查、相关 widget 测试。

## 阶段 2：固定网关与安全 Key

1. 新增唯一网关常量和集中协议解析器。
2. 引入 Android 安全存储，迁移并删除普通偏好中的 LLM Key。
3. 建立单一模型目录服务：Bearer `GET /models`、解析、缓存、错误分类。
4. 在配置加载、备份恢复和旧数据迁移边界强制忽略 Provider URL/Key。
5. 添加 URL 不可覆盖、Key 不落盘、模型列表解析测试。

验证：协议/URL/安全存储单元测试和备份脱敏测试。

## 阶段 3：统一协议路由

1. 把主聊天流式入口改为按模型 ID 解析协议。
2. 同步覆盖非流式或后台 LLM 调用：标题、翻译、摘要、OCR、建议与连接测试。
3. OpenAI 固定 Chat Completions；Anthropic 固定 Messages。
4. 删除 Responses API、自定义聊天路径和 Google Provider 的运行时分支入口。
5. 保留协议内部的工具、图片、思考与用量解析。

验证：模拟服务器/客户端测试请求 URL、鉴权头、请求体、SSE、取消和失败。

## 阶段 4：首次引导与设置分层

1. 新增首次启动状态机：Key -> 验证/取模型 -> 选择模型 -> 聊天。
2. 统一模型选择器，支持搜索、收藏、最近使用和家族分组。
3. 移除 Provider 管理入口与对应导航。
4. 重组设置页为常用设置和高级功能。
5. 模型下架或 Key 失效时提供明确恢复入口。
6. 同步四份 ARB 并生成本地化文件。

验证：首次启动、重启、无效 Key、空列表、模型下架、设置导航 widget 测试。

## 阶段 5：角色卡模型与解析器

1. 定义角色卡 DTO、版本归一化和字段验证器。
2. 实现 V1/V2/V3 JSON 解析。
3. 实现 PNG 签名、块、CRC、`tEXt/zTXt/iTXt`、`chara/ccv3` 解析与安全限制。
4. 实现占位符、示例对话、开场白、未知扩展和内嵌 WorldBook 转换。
5. 扩展 Assistant 兼容持久化字段，不破坏旧数据解码。

验证：固定样本、构造边界和恶意输入的 parser 单元测试。

## 阶段 6：角色卡导入体验

1. 在角色管理页增加 PNG/JSON 文件入口。
2. 增加导入预览、同名处理和事务式写入。
3. 保存原始 PNG 头像并绑定角色专属 WorldBook。
4. 新会话插入默认开场白；聊天菜单支持切换备用开场白。
5. 确保示例对话不成为可见真实历史。

验证：widget 测试、持久化测试、失败回滚测试和 Android 文件选择真机测试。

## 阶段 7：高级功能与迁移回归

1. 逐项验证搜索、MCP、TTS、代理、记忆、世界书、正则、快捷短语、日志、主题、字体和备份。
2. 将第三方搜索/TTS 密钥保留在各自高级服务设置，避免重新引入 LLM Provider 概念。
3. 实现 Kelivo 备份导入清洗：保留内容，丢弃 Provider URL/Key。
4. 确保日志和导出统一遮盖凭据。

验证：相关既有测试、新迁移测试和功能冒烟测试。

## 阶段 8：生成、静态检查与 Android 验收

1. 执行 `flutter pub get`。
2. 执行 `flutter gen-l10n` 并检查 `desiredFileName.txt`。
3. 如修改 Hive 类型，执行 `dart run build_runner build --delete-conflicting-outputs`。
4. 执行 `dart format`、`flutter analyze`、相关测试和 `flutter test`。
5. 构建 Android release APK/AAB。
6. 在 Android 真机验证首次引导、模型选择、两类流、角色卡文件、后台切换和安全存储。
7. 按设计规格第 11 节逐条收集完成证据。

## 提交策略

建议保持可审查的小提交：

1. `docs: add approved Baizi design and implementation plan`
2. `feat: add Baizi gateway and secure credentials`
3. `feat: route models through OpenAI or Anthropic streaming`
4. `feat: add guided setup and simplified settings`
5. `feat: import Tavern character cards`
6. `test: cover migration and Android acceptance paths`
7. `chore: rebrand Android app as Baizi`

