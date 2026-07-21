import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_appearance.dart';
import '../../../core/providers/chat_appearance_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../../../utils/sandbox_path_resolver.dart';

class ChatAppearancePage extends StatelessWidget {
  const ChatAppearancePage({super.key, this.initialModelId});

  final String? initialModelId;

  @override
  Widget build(BuildContext context) {
    if (initialModelId != null && initialModelId!.trim().isNotEmpty) {
      return ModelAppearanceEditPage(modelId: initialModelId!.trim());
    }
    final settings = context.watch<SettingsProvider>();
    final appearance = context.watch<ChatAppearanceProvider>();
    final user = context.watch<UserProvider>();
    final modelIds = <String>{
      ...settings.baiziModels
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty),
      ...appearance.profiles.map((profile) => profile.modelId),
    }.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('聊天外观')),
      body: ListView(
        children: [
          _SectionTitle('我的资料'),
          ListTile(
            leading: _UserAvatar(user: user, size: 42),
            title: Text(user.name),
            subtitle: const Text('昵称和头像会立即应用到全部历史消息'),
            trailing: const Icon(Lucide.ChevronRight),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UserAppearanceEditPage()),
            ),
          ),
          const Divider(height: 1),
          _SectionTitle('背景切换规则'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<ChatBackgroundMode>(
              segments: const [
                ButtonSegment(
                  value: ChatBackgroundMode.selectedModel,
                  icon: Icon(Lucide.Image, size: 18),
                  label: Text('当前模型'),
                ),
                ButtonSegment(
                  value: ChatBackgroundMode.latestAssistantReply,
                  icon: Icon(Lucide.MessageCircle, size: 18),
                  label: Text('最近回复'),
                ),
              ],
              selected: <ChatBackgroundMode>{appearance.backgroundMode},
              onSelectionChanged: (value) => context
                  .read<ChatAppearanceProvider>()
                  .setBackgroundMode(value.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              appearance.backgroundMode == ChatBackgroundMode.selectedModel
                  ? '切换准备发送的模型后，聊天背景立即切换。'
                  : '聊天背景跟随当前会话中最近一条助手回复。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          _SectionTitle('模型资料'),
          if (modelIds.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择模型后，这里会显示可自定义的模型资料。'),
            )
          else
            for (final modelId in modelIds) ...[
              _ModelAppearanceTile(modelId: modelId),
              const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class UserAppearanceEditPage extends StatefulWidget {
  const UserAppearanceEditPage({super.key});

  @override
  State<UserAppearanceEditPage> createState() => _UserAppearanceEditPageState();
}

class _UserAppearanceEditPageState extends State<UserAppearanceEditPage> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: context.read<UserProvider>().name,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    await context.read<UserProvider>().setName(_nameController.text);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickAvatar() async {
    final path = await _pickAndCropImage(context, square: true);
    if (path == null || !mounted) return;
    await context.read<UserProvider>().setAvatarFilePath(path);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的资料'),
        actions: [
          IconButton(icon: const Icon(Lucide.Check), onPressed: _saveName),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  _UserAvatar(user: user, size: 96),
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 16,
                      child: Icon(Lucide.Camera, size: 17),
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton.icon(
            onPressed: user.avatarValue == null
                ? null
                : () => context.read<UserProvider>().resetAvatar(),
            icon: const Icon(Lucide.RotateCcw, size: 18),
            label: const Text('恢复默认头像'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            maxLength: 24,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saveName(),
            decoration: const InputDecoration(
              labelText: '昵称',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class ModelAppearanceEditPage extends StatefulWidget {
  const ModelAppearanceEditPage({super.key, required this.modelId});

  final String modelId;

  @override
  State<ModelAppearanceEditPage> createState() =>
      _ModelAppearanceEditPageState();
}

class _ModelAppearanceEditPageState extends State<ModelAppearanceEditPage> {
  late final TextEditingController _nicknameController;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text:
          context
              .read<ChatAppearanceProvider>()
              .profileFor(widget.modelId)
              ?.nickname ??
          '',
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _saveNickname() async {
    await context.read<ChatAppearanceProvider>().setNickname(
      widget.modelId,
      _nicknameController.text,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickAvatar() async {
    final path = await _pickAndCropImage(context, square: true);
    if (path != null && mounted) {
      await context.read<ChatAppearanceProvider>().setAvatar(
        widget.modelId,
        path,
      );
    }
  }

  Future<void> _pickBackground() async {
    final path = await _pickAndCropImage(context, square: false);
    if (path != null && mounted) {
      await context.read<ChatAppearanceProvider>().setBackground(
        widget.modelId,
        path,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ChatAppearanceProvider>().profileFor(
      widget.modelId,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('模型资料'),
        actions: [
          IconButton(icon: const Icon(Lucide.Check), onPressed: _saveNickname),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: TextEditingController(text: widget.modelId),
            readOnly: true,
            enableInteractiveSelection: true,
            decoration: const InputDecoration(
              labelText: '模型 ID',
              helperText: '模型 ID 仅用于请求，不能修改。',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nicknameController,
            maxLength: 24,
            decoration: const InputDecoration(
              labelText: '显示昵称',
              hintText: '留空则显示原始模型名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          _AssetRow(
            title: '模型头像',
            subtitle: '会应用到该模型的全部历史回复',
            imagePath: profile?.avatarPath,
            circular: true,
            onPick: _pickAvatar,
            onClear: profile?.avatarPath == null
                ? null
                : () => context.read<ChatAppearanceProvider>().clearAvatar(
                    widget.modelId,
                  ),
          ),
          const SizedBox(height: 12),
          _AssetRow(
            title: '聊天背景',
            subtitle: '按已选择的背景规则显示',
            imagePath: profile?.backgroundPath,
            onPick: _pickBackground,
            onClear: profile?.backgroundPath == null
                ? null
                : () => context.read<ChatAppearanceProvider>().clearBackground(
                    widget.modelId,
                  ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: profile == null
                ? null
                : () async {
                    final navigator = Navigator.of(context);
                    await context.read<ChatAppearanceProvider>().resetProfile(
                      widget.modelId,
                    );
                    if (!mounted) return;
                    navigator.pop();
                  },
            icon: const Icon(Lucide.RotateCcw),
            label: const Text('恢复此模型默认外观'),
          ),
        ],
      ),
    );
  }
}

class _ModelAppearanceTile extends StatelessWidget {
  const _ModelAppearanceTile({required this.modelId});

  final String modelId;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ChatAppearanceProvider>().profileFor(modelId);
    final name = profile?.nickname?.trim();
    return ListTile(
      leading: _ModelAvatar(profile: profile, size: 42),
      title: Text(name == null || name.isEmpty ? modelId : name),
      subtitle: Text(modelId, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Lucide.ChevronRight),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ModelAppearanceEditPage(modelId: modelId),
        ),
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.onPick,
    this.onClear,
    this.circular = false,
  });

  final String title;
  final String subtitle;
  final String? imagePath;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final image = _localImage(imagePath);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: circular
          ? CircleAvatar(
              backgroundImage: image,
              child: image == null ? const Icon(Lucide.Bot) : null,
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 52,
                height: 40,
                child: image == null
                    ? const ColoredBox(
                        color: Color(0xFFE7EAF0),
                        child: Icon(Lucide.Image),
                      )
                    : Image(image: image, fit: BoxFit.cover),
              ),
            ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onClear != null)
            IconButton(
              tooltip: '清除',
              icon: const Icon(Lucide.X),
              onPressed: onClear,
            ),
          IconButton(
            tooltip: '从相册选择',
            icon: const Icon(Lucide.Upload),
            onPressed: onPick,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      text,
      style: TextStyle(
        fontWeight: AppFontWeights.emphasis,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user, required this.size});
  final UserProvider user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = user.avatarType == 'file'
        ? _localImage(user.avatarValue)
        : null;
    return CircleAvatar(
      radius: size / 2,
      backgroundImage: image,
      child: image == null
          ? Text(
              user.name.isEmpty
                  ? '?'
                  : user.name.characters.first.toUpperCase(),
              style: TextStyle(fontSize: size * 0.34),
            )
          : null,
    );
  }
}

class _ModelAvatar extends StatelessWidget {
  const _ModelAvatar({required this.profile, required this.size});
  final ModelChatAppearance? profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = _localImage(profile?.avatarPath);
    final name = profile?.nickname?.trim();
    return CircleAvatar(
      radius: size / 2,
      backgroundImage: image,
      child: image == null
          ? Text(
              name == null || name.isEmpty
                  ? 'AI'
                  : name.characters.first.toUpperCase(),
              style: TextStyle(fontSize: size * 0.27),
            )
          : null,
    );
  }
}

ImageProvider? _localImage(String? rawPath) {
  final path = (rawPath ?? '').trim();
  if (path.isEmpty) return null;
  final file = File(SandboxPathResolver.fix(path));
  return file.existsSync() ? FileImage(file) : null;
}

Future<String?> _pickAndCropImage(
  BuildContext context, {
  required bool square,
}) async {
  final colors = Theme.of(context).colorScheme;
  final selected = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2048,
    imageQuality: 92,
  );
  if (selected == null) return null;
  final cropped = await ImageCropper().cropImage(
    sourcePath: selected.path,
    aspectRatio: square ? const CropAspectRatio(ratioX: 1, ratioY: 1) : null,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: square ? '裁剪头像' : '裁剪聊天背景',
        toolbarColor: colors.surface,
        toolbarWidgetColor: colors.onSurface,
        activeControlsWidgetColor: colors.primary,
        lockAspectRatio: square,
      ),
      IOSUiSettings(title: square ? '裁剪头像' : '裁剪聊天背景'),
    ],
  );
  return cropped?.path ?? selected.path;
}
