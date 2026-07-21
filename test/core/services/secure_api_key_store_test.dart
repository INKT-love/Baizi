import 'package:flutter_test/flutter_test.dart';

import 'package:Baizi/core/services/secure_api_key_store.dart';

final class _MemoryBackend implements SecureApiKeyBackend {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  group('SecureApiKeyStore', () {
    test('normalizes a key and creates an active Key 1 profile', () async {
      final backend = _MemoryBackend();
      final store = SecureApiKeyStore(backend: backend);

      await store.write('  sk-test-value  ');

      final vault = await store.readVault();
      expect(vault.profiles, hasLength(1));
      expect(vault.activeProfile?.label, 'Key 1');
      expect(await store.read(), 'sk-test-value');
      expect(backend.values[SecureApiKeyStore.storageKey], isNull);
    });

    test('migrates the legacy single key into a named profile', () async {
      final backend = _MemoryBackend()
        ..values[SecureApiKeyStore.storageKey] = 'legacy-secret';
      final store = SecureApiKeyStore(backend: backend);

      final vault = await store.readVault();

      expect(vault.activeProfile?.label, 'Key 1');
      expect(await store.read(), 'legacy-secret');
      expect(backend.values[SecureApiKeyStore.storageKey], isNull);
    });

    test('adds, renames, switches, and deletes key profiles', () async {
      final store = SecureApiKeyStore(backend: _MemoryBackend());
      await store.addProfile(
        id: 'primary',
        label: 'Primary',
        key: 'primary-secret',
      );
      await store.addProfile(
        id: 'backup',
        label: 'Backup',
        key: 'backup-secret',
        activate: false,
      );

      await store.selectProfile('backup');
      await store.renameProfile('backup', 'Spare');
      final vault = await store.deleteProfile('backup');

      expect(vault.profiles.map((profile) => profile.label), <String>[
        'Primary',
      ]);
      expect(vault.activeProfileId, 'primary');
      expect(await store.read(), 'primary-secret');
    });

    test('empty input removes every stored key profile', () async {
      final backend = _MemoryBackend();
      final store = SecureApiKeyStore(backend: backend);
      await store.write('sk-test-value');

      await store.write('   ');

      expect(await store.read(), isNull);
      expect((await store.readVault()).isEmpty, isTrue);
      expect(backend.values, isEmpty);
    });

    test('blank persisted legacy values are treated as missing', () async {
      final backend = _MemoryBackend()
        ..values[SecureApiKeyStore.storageKey] = '   ';

      expect(await SecureApiKeyStore(backend: backend).read(), isNull);
    });

    test('backend failures remain visible to the caller', () async {
      final store = SecureApiKeyStore(backend: _FailingBackend());

      await expectLater(store.read(), throwsA(isA<StateError>()));
      await expectLater(
        store.write('sk-test-value'),
        throwsA(isA<StateError>()),
      );
      await expectLater(store.clear(), throwsA(isA<StateError>()));
    });
  });
}

final class _FailingBackend implements SecureApiKeyBackend {
  Never _fail() => throw StateError('secure storage unavailable');

  @override
  Future<void> delete(String key) async => _fail();

  @override
  Future<String?> read(String key) async => _fail();

  @override
  Future<void> write(String key, String value) async => _fail();
}
