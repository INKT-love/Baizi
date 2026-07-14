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

final class SecureApiKeyStore {
  SecureApiKeyStore({SecureApiKeyBackend? backend})
    : _backend = backend ?? FlutterSecureApiKeyBackend();

  static const String storageKey = 'baizi_api_key_v1';

  final SecureApiKeyBackend _backend;

  Future<String?> read() async {
    final value = (await _backend.read(storageKey))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> write(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await clear();
      return;
    }
    await _backend.write(storageKey, normalized);
  }

  Future<void> clear() => _backend.delete(storageKey);
}
