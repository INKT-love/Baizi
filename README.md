<div align="center">
  <img src="assets/app_icon.png" alt="Baizi icon" width="112" />
  <h1>Baizi</h1>
  <p>A focused LLM chat client with a simple, guided setup.</p>

  <a href="https://github.com/INKT-love/Baizi/releases/latest">Download</a>
  ·
  <a href="README_ZH_CN.md">简体中文</a>
</div>

## Overview

Baizi keeps connection setup deliberately small: enter one API key, refresh the model list, and choose a model. The gateway endpoint is fixed to:

```text
https://api.inktandwkx.top:51000/v1
```

The app selects the request format automatically:

- Models whose name contains `claude` use the Anthropic Messages format.
- All other models use the OpenAI Chat Completions format.

Model choices are loaded from the gateway, so there is no provider URL, protocol, or request-template configuration to complete before chatting.

## Features

- Guided first-run setup for one API key and a model choice.
- Streaming responses for both supported request formats.
- Searchable model picker with refresh, recent models, and pinned models.
- Import SillyTavern character cards from PNG or JSON, with preview and overwrite/copy choices.
- Assistants, chat history, Markdown rendering, image input, backups, and restore.
- Advanced settings for experienced users without complicating initial setup.
- Local API-key storage through the platform secure-storage service.
- Android, iOS, Windows, macOS, Linux, and Web project targets.

## Install

Download the current Android build from [Releases](https://github.com/INKT-love/Baizi/releases/latest).

- **ARM64-v8a**: recommended for most modern Android devices.
- **ARMv7**: for older 32-bit Android devices.
- **x86_64**: for compatible emulators and devices.

The current release is [v1.1.18](https://github.com/INKT-love/Baizi/releases/tag/v1.1.18).

## Quick Start

1. Open Baizi and enter your API key.
2. Refresh the available models.
3. Choose a model and begin a chat.

Selecting a Claude model automatically switches the request format. Selecting any other model uses the OpenAI-compatible format.

## Development

Requirements:

- Flutter `>= 3.44.1`
- Dart SDK `^3.12.1`

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

## Contributing

Issues and pull requests are welcome at [INKT-love/Baizi](https://github.com/INKT-love/Baizi).

## License

Baizi is distributed under the [AGPL-3.0 license](LICENSE).
