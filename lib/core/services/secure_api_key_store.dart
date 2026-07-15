import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecureApiKeyBackend {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

final class FlutterSecureApiKeyBackend implements SecureApiKeyBackend {
  FlutterSecureApiKeyBackend({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'baizi_credentials',
              resetOnError: false,
              migrateWithBackup: true,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

final class BaiziApiKeyProfile {
  const BaiziApiKeyProfile({required this.id, required this.label});

  final String id;
  final String label;

  Map<String, String> toJson() => <String, String>{'id': id, 'label': label};

  factory BaiziApiKeyProfile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final label = json['label'];
    if (id is! String || label is! String) {
      throw const FormatException('Invalid Baizi API key profile');
    }
    return BaiziApiKeyProfile(id: id, label: label);
  }
}

final class BaiziApiKeyVault {
  BaiziApiKeyVault({
    required List<BaiziApiKeyProfile> profiles,
    required this.activeProfileId,
  }) : profiles = List<BaiziApiKeyProfile>.unmodifiable(profiles);

  final List<BaiziApiKeyProfile> profiles;
  final String? activeProfileId;

  bool get isEmpty => profiles.isEmpty;

  BaiziApiKeyProfile? get activeProfile {
    final activeProfileId = this.activeProfileId;
    if (activeProfileId == null) return null;
    for (final profile in profiles) {
      if (profile.id == activeProfileId) return profile;
    }
    return null;
  }

  BaiziApiKeyVault copyWith({
    List<BaiziApiKeyProfile>? profiles,
    String? activeProfileId,
    bool clearActiveProfileId = false,
  }) {
    return BaiziApiKeyVault(
      profiles: profiles ?? this.profiles,
      activeProfileId: clearActiveProfileId
          ? null
          : activeProfileId ?? this.activeProfileId,
    );
  }
}

final class SecureApiKeyStore {
  SecureApiKeyStore({SecureApiKeyBackend? backend})
    : _backend = backend ?? FlutterSecureApiKeyBackend();

  /// The single-key location used by previous Baizi builds.
  static const String storageKey = 'baizi_api_key_v1';
  static const String _vaultStorageKey = 'baizi_api_key_vault_v2';
  static const String _profileKeyPrefix = 'baizi_api_key_profile_v2_';
  static final RegExp _validProfileId = RegExp(r'^[a-zA-Z0-9_-]+$');

  final SecureApiKeyBackend _backend;

  Future<String?> read() async {
    final vault = await readVault();
    final activeProfileId = vault.activeProfileId;
    if (activeProfileId == null) return null;
    return readProfileKey(activeProfileId);
  }

  Future<BaiziApiKeyVault> readVault() async {
    final encoded = (await _backend.read(_vaultStorageKey))?.trim();
    if (encoded == null || encoded.isEmpty) return _migrateLegacyKey();

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException('Invalid Baizi API key vault');
      }
      final profilesValue = decoded['profiles'];
      final activeProfileId = decoded['activeProfileId'];
      if (profilesValue is! List ||
          (activeProfileId != null && activeProfileId is! String)) {
        throw const FormatException('Invalid Baizi API key vault');
      }

      final profiles = profilesValue
          .map((item) {
            if (item is! Map) {
              throw const FormatException('Invalid Baizi API key profile');
            }
            return BaiziApiKeyProfile.fromJson(Map<String, dynamic>.from(item));
          })
          .toList(growable: false);
      _validateProfiles(profiles);

      final resolvedActiveProfileId =
          profiles.any((profile) => profile.id == activeProfileId)
          ? activeProfileId
          : (profiles.isEmpty ? null : profiles.first.id);
      return BaiziApiKeyVault(
        profiles: profiles,
        activeProfileId: resolvedActiveProfileId,
      );
    } on FormatException catch (error) {
      throw StateError('Stored Baizi API key metadata is invalid: $error');
    }
  }

  Future<String?> readProfileKey(String profileId) async {
    _validateProfileId(profileId);
    final value = (await _backend.read(_profileStorageKey(profileId)))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> write(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await clear();
      return;
    }

    final vault = await readVault();
    final activeProfile = vault.activeProfile;
    if (activeProfile == null) {
      await addProfile(
        id: 'key-1',
        label: 'Key 1',
        key: normalized,
        activate: true,
      );
      return;
    }
    await _backend.write(_profileStorageKey(activeProfile.id), normalized);
  }

  Future<BaiziApiKeyVault> addProfile({
    required String id,
    required String label,
    required String key,
    bool activate = true,
  }) async {
    _validateProfileId(id);
    final normalizedLabel = _normalizeLabel(label);
    final normalizedKey = _normalizeKey(key);
    final vault = await readVault();
    if (vault.profiles.any((profile) => profile.id == id)) {
      throw StateError('A Baizi API key profile already uses id "$id"');
    }

    final profile = BaiziApiKeyProfile(id: id, label: normalizedLabel);
    await _backend.write(_profileStorageKey(id), normalizedKey);
    final nextVault = BaiziApiKeyVault(
      profiles: <BaiziApiKeyProfile>[...vault.profiles, profile],
      activeProfileId: activate ? id : vault.activeProfileId,
    );
    await _writeVault(nextVault);
    return nextVault;
  }

  Future<BaiziApiKeyVault> renameProfile(String id, String label) async {
    _validateProfileId(id);
    final normalizedLabel = _normalizeLabel(label);
    final vault = await readVault();
    if (!vault.profiles.any((profile) => profile.id == id)) {
      throw StateError('Unknown Baizi API key profile "$id"');
    }
    final nextVault = BaiziApiKeyVault(
      profiles: vault.profiles
          .map(
            (profile) => profile.id == id
                ? BaiziApiKeyProfile(id: id, label: normalizedLabel)
                : profile,
          )
          .toList(growable: false),
      activeProfileId: vault.activeProfileId,
    );
    await _writeVault(nextVault);
    return nextVault;
  }

  Future<BaiziApiKeyVault> selectProfile(String id) async {
    _validateProfileId(id);
    final vault = await readVault();
    if (!vault.profiles.any((profile) => profile.id == id)) {
      throw StateError('Unknown Baizi API key profile "$id"');
    }
    final nextVault = vault.copyWith(activeProfileId: id);
    await _writeVault(nextVault);
    return nextVault;
  }

  Future<BaiziApiKeyVault> deleteProfile(String id) async {
    _validateProfileId(id);
    final vault = await readVault();
    if (!vault.profiles.any((profile) => profile.id == id)) {
      throw StateError('Unknown Baizi API key profile "$id"');
    }

    final profiles = vault.profiles
        .where((profile) => profile.id != id)
        .toList(growable: false);
    final activeProfileId = vault.activeProfileId == id
        ? (profiles.isEmpty ? null : profiles.first.id)
        : vault.activeProfileId;
    final nextVault = BaiziApiKeyVault(
      profiles: profiles,
      activeProfileId: activeProfileId,
    );
    await _writeVault(nextVault);
    await _backend.delete(_profileStorageKey(id));
    return nextVault;
  }

  Future<void> clear() async {
    final vault = await readVault();
    await _backend.delete(_vaultStorageKey);
    for (final profile in vault.profiles) {
      await _backend.delete(_profileStorageKey(profile.id));
    }
    await _backend.delete(storageKey);
  }

  Future<BaiziApiKeyVault> _migrateLegacyKey() async {
    final legacyKey = (await _backend.read(storageKey))?.trim();
    if (legacyKey == null || legacyKey.isEmpty) {
      return BaiziApiKeyVault(
        profiles: <BaiziApiKeyProfile>[],
        activeProfileId: null,
      );
    }

    const profile = BaiziApiKeyProfile(id: 'key-1', label: 'Key 1');
    final vault = BaiziApiKeyVault(
      profiles: <BaiziApiKeyProfile>[profile],
      activeProfileId: profile.id,
    );
    await _backend.write(_profileStorageKey(profile.id), legacyKey);
    await _writeVault(vault);
    await _backend.delete(storageKey);
    return vault;
  }

  Future<void> _writeVault(BaiziApiKeyVault vault) async {
    _validateProfiles(vault.profiles);
    final activeProfileId = vault.activeProfileId;
    if (activeProfileId != null &&
        !vault.profiles.any((profile) => profile.id == activeProfileId)) {
      throw StateError('The active Baizi API key profile does not exist');
    }
    if (vault.isEmpty) {
      await _backend.delete(_vaultStorageKey);
      return;
    }
    await _backend.write(
      _vaultStorageKey,
      jsonEncode(<String, dynamic>{
        'profiles': vault.profiles.map((profile) => profile.toJson()).toList(),
        'activeProfileId': activeProfileId,
      }),
    );
  }

  void _validateProfiles(List<BaiziApiKeyProfile> profiles) {
    final ids = <String>{};
    for (final profile in profiles) {
      _validateProfileId(profile.id);
      _normalizeLabel(profile.label);
      if (!ids.add(profile.id)) {
        throw StateError('Duplicate Baizi API key profile id "${profile.id}"');
      }
    }
  }

  void _validateProfileId(String id) {
    if (!_validProfileId.hasMatch(id)) {
      throw StateError('Invalid Baizi API key profile id');
    }
  }

  String _normalizeLabel(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw StateError('A Baizi API key profile needs a name');
    }
    return normalized;
  }

  String _normalizeKey(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw StateError('A Baizi API key cannot be empty');
    }
    return normalized;
  }

  String _profileStorageKey(String id) => '$_profileKeyPrefix$id';
}
