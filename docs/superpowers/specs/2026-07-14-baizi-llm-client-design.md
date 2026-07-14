# 白子 LLM 客户端设计规格

- 状态：已批准
- 日期：2026-07-14
- 上游基线：`Chevey339/kelivo` `master`，提交 `c8c9ff3`
- 目标平台：Android
- 应用名称：白子
- Android applicationId：`top.inktandwkx.baizi`
- 许可证：AGPL-3.0

## 1. 产品目标

白子是基于 Kelivo 的 Android LLM 聊天客户端。用户首次使用只需要完成两项输入：填写一个 API Key，选择一个模型。客户端固定连接白子网关，隐藏 LLM 供应商和协议概念，同时保留 Kelivo 的聊天、角色、搜索、MCP、TTS、备份、主题等能力。

核心成功标准：全新安装后，用户通过“填写 Key -> 获取模型 -> 选择模型”即可开始流式聊天，不需要理解 Base URL、Provider、OpenAI/Anthropic 协议或请求路径。

## 2. 硬性约束

1. Base URL 必须严格固定为 `https://api.inktandwkx.top:51000/v1`。
2. 应用内不能提供修改 Base URL 的入口。
3. 模型列表只通过 `GET /models` 获取，使用 `Authorization: Bearer <key>`。
4. 模型 ID 不区分大小写包含 `claude` 时使用 Anthropic Messages 协议；其他模型全部使用 OpenAI Chat Completions 协议。
5. OpenAI 请求固定为 `POST /chat/completions` 且 `stream: true`。
6. Anthropic 请求固定为 `POST /messages` 且 `stream: true`。
7. 用户只维护一个 API Key；Key 不得写入源码、普通偏好、日志或备份。
8. 首版只验收 Android，不承诺其他平台可运行。
9. 支持导入常见 V1、V2、V3 酒馆角色卡，输入格式包括 PNG 和 JSON。
10. 作为 Kelivo 衍生项目按 AGPL-3.0 开源，保留上游版权和来源说明。

## 3. 总体架构

### 3.1 单网关配置

系统只有一个 LLM 网关。固定地址由代码常量提供，不从 SharedPreferences、备份、二维码、环境变量或用户输入读取。旧 Provider 配置只能作为迁移输入，不能成为运行时网络地址来源。

运行时配置由以下三项组成：

- 固定网关地址
- Android 安全存储中的 API Key
- SharedPreferences 中当前选择的模型 ID

### 3.2 集中协议解析

所有 LLM 调用必须经过同一个协议解析函数：

```text
modelId.toLowerCase().contains('claude')
  true  -> Anthropic Messages
  false -> OpenAI Chat Completions
```

该规则适用于主聊天、标题生成、翻译、摘要、OCR、建议生成、连接测试，以及任何复用 LLM 的高级功能。禁止在各功能内复制一份模型判断逻辑。

### 3.3 统一流式输出

现有 OpenAI 和 Anthropic 请求构造器与 SSE 解析器继续复用。协议层将两类事件转换为 Kelivo 已有的统一流式消息对象，界面继续处理：

- 正文增量
- 思考内容
- 工具调用
- Token 用量
- 完成原因
- 网络与协议错误

## 4. API 契约

### 4.1 模型列表

```http
GET https://api.inktandwkx.top:51000/v1/models
Authorization: Bearer <key>
```

客户端读取 OpenAI 风格的 `data[].id`，展示接口返回的全部模型。成功结果可缓存，用于短暂离线时展示；缓存不能用于判定 Key 仍然有效。

### 4.2 OpenAI 聊天

```http
POST https://api.inktandwkx.top:51000/v1/chat/completions
Authorization: Bearer <key>
Content-Type: application/json
```

请求体使用 Chat Completions 消息格式并固定 `stream: true`。不保留 Responses API 或自定义聊天路径开关。

### 4.3 Anthropic 聊天

```http
POST https://api.inktandwkx.top:51000/v1/messages
x-api-key: <key>
anthropic-version: 2023-06-01
Content-Type: application/json
```

请求体使用 Anthropic Messages 格式并固定 `stream: true`。系统提示词必须提升到顶层 `system` 字段。

## 5. 首次启动与设置体验

### 5.1 首次启动

首次启动直接进入配置引导，不显示营销页：

1. 填写 API Key：密码框默认隐藏，提供粘贴、显示/隐藏和清空操作。
2. 验证并获取模型：调用 `/models`，明确区分 Key 无效、网络异常、服务异常和空列表。
3. 选择模型：支持搜索、最近使用、收藏和模型家族分组；选择后进入聊天。

已有有效 Key 与模型时直接进入聊天。模型不存在时不得静默切换，必须要求用户重新选择。

### 5.2 设置分层

常用设置包含：

- 当前模型与切换模型
- 刷新模型列表
- 更换 API Key
- 角色管理
- 外观与主题
- 数据备份

高级功能包含：

- MCP 与内置工具
- 联网搜索
- TTS 与语音服务
- 代理
- 自定义请求头、请求体和模型参数
- 上下文、记忆、世界书、正则规则、快捷短语
- 调试日志

界面不出现 LLM Provider 管理、Provider 分组、Provider 二维码、Provider 头像、多 Key、余额、Base URL、请求路径或 Responses API 设置。

搜索与 TTS 自身需要的第三方服务配置仍保留在各自高级页面，但不得与 LLM Provider 混在同一信息架构中。

## 6. 酒馆角色卡

### 6.1 支持范围

- V1 平铺 JSON
- V2 `spec/spec_version/data` JSON
- V3 `spec/spec_version/data` JSON
- PNG `tEXt`、`zTXt`、`iTXt` 中的 `chara` 元数据
- PNG 中的 V3 `ccv3` 元数据

PNG 必须从原始字节解析元数据，再把原图保存为头像。不得先经过图片压缩、裁剪或重新编码。

### 6.2 内部结构与字段映射

解析器先输出独立的角色卡 DTO，再由导入服务事务式写入 Assistant、头像、标签和 WorldBook。字段映射如下：

| 酒馆字段 | 白子字段/行为 |
| --- | --- |
| `name` | 角色名称 |
| PNG 原图 | 角色头像 |
| `description` | 角色描述提示词组件 |
| `personality` | 性格提示词组件 |
| `scenario` | 场景提示词组件 |
| `system_prompt` | 系统提示词组件 |
| `post_history_instructions` | 历史后指令组件 |
| `first_mes` | 默认开场白 |
| `alternate_greetings` | 可切换开场白列表 |
| `mes_example` | 示例对话上下文，不写入真实聊天历史 |
| `character_book` | 仅绑定当前角色的 WorldBook |
| `tags` | 角色标签 |
| `extensions` 和未知字段 | 原样保留 |

`{{char}}` 替换为角色名，`{{user}}` 替换为用户昵称；昵称为空时使用本地化的“用户”。

### 6.3 导入交互

流程为“选择文件 -> 解析预览 -> 确认导入”。预览显示头像、名称、卡片版本、设定摘要、开场白数量和世界书条目数。同名角色默认创建副本，用户可主动选择覆盖。

新会话默认插入 `first_mes` 作为首条角色消息，不调用模型。聊天菜单可更换备用开场白。备用开场白和示例对话不能被批量写成真实历史消息。

### 6.4 输入安全边界

- 单个角色卡文件最大 32 MiB
- 单个 PNG 元数据块最大 8 MiB
- 解压后的角色 JSON 最大 16 MiB
- JSON 最大嵌套深度 64
- JSON 最大集合节点数 100000
- 校验 PNG 签名、块边界、长度和 CRC
- 拒绝无效 Base64、无效 UTF-8、截断 PNG 和压缩炸弹
- 不自动下载角色卡中的远程资源
- 导入必须先完整验证，再写持久化数据；失败时不得留下半个角色或孤立文件

## 7. 数据与迁移

### 7.1 存储

- API Key：Android Keystore 支持的安全存储
- 当前模型、收藏、最近模型和普通设置：SharedPreferences
- 对话与消息：现有 Hive 存储
- 角色卡结构化数据：Assistant 兼容字段与角色卡扩展数据
- 头像与背景：现有应用数据目录
- 世界书：现有 WorldBook 存储并记录角色绑定

### 7.2 备份

备份包含聊天、角色、世界书和普通设置，但不包含 API Key。恢复后用户必须重新填写 Key。恢复入口必须忽略任何旧 Base URL、Provider Key 或 Provider 凭据。

### 7.3 Kelivo 迁移

支持导入 Kelivo 旧备份：

- 保留聊天、助手、世界书、主题和兼容设置
- 丢弃旧 Provider、URL 和 API Key
- 尽量保留模型 ID
- 模型不在白子模型列表时，引导用户重新选择

白子使用独立 applicationId，不直接读取已安装 Kelivo 的应用沙箱。

## 8. 品牌与许可

- 用户可见产品名改为“白子”
- Android applicationId 改为 `top.inktandwkx.baizi`
- 关于页显示白子版本、源码许可、Kelivo 上游来源和 AGPL-3.0
- 不复用 Kelivo 的发布更新源作为白子更新源
- 未配置白子发布源前，更新检查应明确禁用，不得跳转到 Kelivo 安装包

## 9. 错误恢复与隐私

- `401/403`：提示 Key 无效并提供更换入口
- 模型列表获取失败：可展示上次缓存并标注离线状态
- 流式中断：保留已生成内容，提供继续生成或重新生成
- 用户停止：取消当前流并保留内容
- 模型下架：发送前阻止请求并要求重新选择
- HTTPS 证书错误：直接报告，不允许绕过
- 聊天请求不自动重试，避免重复生成和重复计费
- 日志、异常、调试导出和 UI 自动遮盖 API Key、Authorization 与 x-api-key

## 10. 保留与删除范围

保留 Kelivo 的聊天、图片输入、Markdown、LaTeX、代码高亮、消息编辑、重新生成、分支、导出、历史、上下文、MCP、搜索、TTS、代理、记忆、世界书、正则、快捷短语、日志、主题、字体和备份能力。

删除或不可达化 LLM 多供应商配置：Provider 新增/编辑/分组/排序/导入/分享、多 Key、余额、Provider 头像、Google Provider、Base URL、聊天路径与 Responses API。

## 11. 验收标准

1. 全新安装只填一个 Key、选一个模型即可流式聊天。
2. `/models` 返回的全部模型均可搜索和选择。
3. 模型 ID 含 `claude` 的所有 LLM 调用只走 `/messages`。
4. 其他模型的所有 LLM 调用只走 `/chat/completions`。
5. 运行时不存在白子固定 Base URL 之外的 LLM 请求地址。
6. 应用内不存在可编辑 LLM Base URL 或 Provider 管理入口。
7. V1/V2/V3 PNG/JSON 角色卡完整导入，头像、开场白、示例对话、标签和世界书不丢失。
8. API Key 不出现在普通偏好、备份、日志或源码中。
9. Kelivo 保留功能可从常用或高级功能入口使用。
10. 本地化生成、静态分析、相关测试、全量测试和 Android release 构建通过。
11. 至少一台 Android 真机完成首次引导、文件导入、流式聊天、后台切换和安全存储验收。

