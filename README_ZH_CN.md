<div align="center">
  <img src="assets/app_icon.png" alt="白子图标" width="112" />
  <h1>白子</h1>
  <p>面向日常聊天的 LLM 客户端，配置只保留真正需要填写的内容。</p>

  <a href="https://github.com/INKT-love/Baizi/releases/latest">下载</a>
  ·
  <a href="README.md">English</a>
</div>

## 项目说明

白子将连接配置简化为三步：填写一个 API Key、刷新模型列表、选择模型。网关地址固定为：

```text
https://api.inktandwkx.top:51000/v1
```

应用会按模型自动选择请求格式：

- 模型名包含 `claude` 时，使用 Anthropic Messages 格式。
- 其他模型使用 OpenAI Chat Completions 格式。

模型列表直接从网关获取，不需要配置供应商地址、协议或请求模板。

## 功能

- 首次启动引导：只填写一个 API Key，再选择模型即可开始。
- OpenAI 与 Anthropic 两种格式统一流式输出。
- 可搜索的模型选择器，支持刷新、最近使用和收藏模型。
- 支持导入酒馆（SillyTavern）PNG 与 JSON 角色卡，可预览并选择新建副本或覆盖角色。
- 助手管理、聊天记录、Markdown 渲染、图片输入、备份与恢复。
- 将进阶选项收纳到高级设置，不干扰日常使用。
- API Key 使用系统安全存储保存于本机。
- 工程支持 Android、iOS、Windows、macOS、Linux 与 Web。

## 下载与安装

前往 [Releases](https://github.com/INKT-love/Baizi/releases/latest) 下载 Android 安装包。

- **ARM64-v8a**：绝大多数现代 Android 手机选择此版本。
- **ARMv7**：较旧的 32 位 Android 设备使用。
- **x86_64**：适用于兼容的模拟器或设备。

当前版本为 [v1.1.18](https://github.com/INKT-love/Baizi/releases/tag/v1.1.18)。

## 快速开始

1. 打开白子并填写 API Key。
2. 刷新可用模型。
3. 选择模型后开始聊天。

选择 Claude 模型会自动切换到 Anthropic 格式；选择其他模型则使用 OpenAI 兼容格式。

## 开发

环境要求：

- Flutter `>= 3.44.1`
- Dart SDK `^3.12.1`

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

## 参与贡献

欢迎通过 [INKT-love/Baizi](https://github.com/INKT-love/Baizi) 提交 Issue 或 Pull Request。

## 许可证

本项目使用 [AGPL-3.0 许可证](LICENSE)。
