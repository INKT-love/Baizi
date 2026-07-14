import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/secure_api_key_store.dart';

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
    test('normalizes a key before secure persistence', () async {
      final backend = _MemoryBackend();
      final store = SecureApiKeyStore(backend: backend);

      await store.write('  sk-test-value  ');

      expect(backend.values, <String, String>{
        SecureApiKeyStore.storageKey: 'sk-test-value',
      });
      expect(await store.read(), 'sk-test-value');
    });

    test('empty input removes the secure value', () async {
      final backend = _MemoryBackend();
      final store = SecureApiKeyStore(backend: backend);
      await store.write('sk-test-value');

      await store.write('   ');

      expect(await store.read(), isNull);
      expect(backend.values, isEmpty);
    });

    test('blank persisted values are treated as missing', () async {
      final backend = _MemoryBackend();
      backend.values[SecureApiKeyStore.storageKey] = '   ';

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
