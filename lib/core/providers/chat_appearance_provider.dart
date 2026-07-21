import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_directories.dart';
import '../../utils/sandbox_path_resolver.dart';
import '../models/chat_appearance.dart';

class ChatAppearanceProvider extends ChangeNotifier {
  static const _prefsKey = 'chat_appearance_profiles_v1';

  final Map<String, ModelChatAppearance> _profiles =
      <String, ModelChatAppearance>{};
  ChatBackgroundMode _backgroundMode = ChatBackgroundMode.selectedModel;
  late final Future<void> _ready;

  ChatAppearanceProvider() {
    _ready = _load();
  }

  ChatBackgroundMode get backgroundMode => _backgroundMode;
  Future<void> get ready => _ready;
  List<ModelChatAppearance> get profiles =>
      _profiles.values.toList(growable: false);

  ModelChatAppearance? profileFor(String? modelId) {
    final id = (modelId ?? '').trim();
    return id.isEmpty ? null : _profiles[id];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return;
      final mode = json['backgroundMode']?.toString();
      _backgroundMode = mode == ChatBackgroundMode.latestAssistantReply.name
          ? ChatBackgroundMode.latestAssistantReply
          : ChatBackgroundMode.selectedModel;
      final entries = json['profiles'];
      if (entries is Map) {
        for (final entry in entries.entries) {
          if (entry.value is! Map) continue;
          final profile = ModelChatAppearance.fromJson(
            entry.value.cast<String, dynamic>(),
          );
          if (profile.modelId.isEmpty) continue;
          _profiles[profile.modelId] = profile.copyWith(
            avatarPath: _fixLocalPath(profile.avatarPath),
            backgroundPath: _fixLocalPath(profile.backgroundPath),
          );
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  String? _fixLocalPath(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty ||
        value.startsWith('http') ||
        value.startsWith('data:')) {
      return raw;
    }
    return SandboxPathResolver.fix(value);
  }

  Future<void> setBackgroundMode(ChatBackgroundMode mode) async {
    await _ready;
    if (_backgroundMode == mode) return;
    _backgroundMode = mode;
    notifyListeners();
    await _persist();
  }

  Future<void> setNickname(String modelId, String? nickname) async {
    await _ready;
    final id = modelId.trim();
    if (id.isEmpty) return;
    final value = nickname?.trim();
    final previous = _profiles[id] ?? ModelChatAppearance(modelId: id);
    _store(
      previous.copyWith(
        nickname: value,
        clearNickname: value == null || value.isEmpty,
      ),
    );
    await _persist();
  }

  Future<void> setAvatar(String modelId, String sourcePath) async {
    await _replaceAsset(modelId, sourcePath, isAvatar: true);
  }

  Future<void> setBackground(String modelId, String sourcePath) async {
    await _replaceAsset(modelId, sourcePath, isAvatar: false);
  }

  Future<void> clearAvatar(String modelId) async {
    await _clearAsset(modelId, isAvatar: true);
  }

  Future<void> clearBackground(String modelId) async {
    await _clearAsset(modelId, isAvatar: false);
  }

  Future<void> resetProfile(String modelId) async {
    await _ready;
    final id = modelId.trim();
    final previous = _profiles.remove(id);
    if (previous == null) return;
    notifyListeners();
    await _persist();
    await _deleteManagedFile(previous.avatarPath, isAvatar: true);
    await _deleteManagedFile(previous.backgroundPath, isAvatar: false);
  }

  Future<void> _replaceAsset(
    String modelId,
    String sourcePath, {
    required bool isAvatar,
  }) async {
    await _ready;
    final id = modelId.trim();
    final source = sourcePath.trim();
    if (id.isEmpty || source.isEmpty) return;
    final copied = await _copyAsset(source, id: id, isAvatar: isAvatar);
    if (copied == null) return;
    final previous = _profiles[id] ?? ModelChatAppearance(modelId: id);
    final next = isAvatar
        ? previous.copyWith(avatarPath: copied)
        : previous.copyWith(backgroundPath: copied);
    _store(next);
    await _persist();
    await _deleteManagedFile(
      isAvatar ? previous.avatarPath : previous.backgroundPath,
      isAvatar: isAvatar,
      except: copied,
    );
  }

  Future<void> _clearAsset(String modelId, {required bool isAvatar}) async {
    await _ready;
    final id = modelId.trim();
    final previous = _profiles[id];
    if (previous == null) return;
    final next = isAvatar
        ? previous.copyWith(clearAvatar: true)
        : previous.copyWith(clearBackground: true);
    _store(next);
    await _persist();
    await _deleteManagedFile(
      isAvatar ? previous.avatarPath : previous.backgroundPath,
      isAvatar: isAvatar,
    );
  }

  void _store(ModelChatAppearance profile) {
    if (profile.isEmpty) {
      _profiles.remove(profile.modelId);
    } else {
      _profiles[profile.modelId] = profile;
    }
    notifyListeners();
  }

  Future<String?> _copyAsset(
    String rawPath, {
    required String id,
    required bool isAvatar,
  }) async {
    try {
      final source = File(SandboxPathResolver.fix(rawPath));
      if (!await source.exists()) return null;
      final directory = isAvatar
          ? await AppDirectories.getAvatarsDirectory()
          : await AppDirectories.getImagesDirectory();
      if (!await directory.exists()) await directory.create(recursive: true);
      var extension = p.extension(source.path).toLowerCase();
      if (extension.isEmpty || extension.length > 7) extension = '.jpg';
      final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final prefix = isAvatar ? 'model_avatar' : 'model_background';
      final target = File(
        p.join(
          directory.path,
          '${prefix}_${safeId}_${DateTime.now().millisecondsSinceEpoch}$extension',
        ),
      );
      await source.copy(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteManagedFile(
    String? rawPath, {
    required bool isAvatar,
    String? except,
  }) async {
    final path = (rawPath ?? '').trim();
    if (path.isEmpty) return;
    try {
      final directory = isAvatar
          ? await AppDirectories.getAvatarsDirectory()
          : await AppDirectories.getImagesDirectory();
      final root = p.normalize(directory.absolute.path);
      final target = p.normalize(File(path).absolute.path);
      if (!p.isWithin(root, target) ||
          (except != null && p.equals(target, p.normalize(except)))) {
        return;
      }
      final file = File(target);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(<String, dynamic>{
        'backgroundMode': _backgroundMode.name,
        'profiles': <String, dynamic>{
          for (final entry in _profiles.entries)
            entry.key: entry.value.toJson(),
        },
      }),
    );
  }
}
