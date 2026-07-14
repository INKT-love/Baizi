import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/secure_api_key_store.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';

const _fixtureFontPath =
    'dependencies/gpt_markdown/lib/fonts/JetBrainsMono-Regular.ttf';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';

  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

Future<SettingsProvider> _buildSettings() async {
  final settings = SettingsProvider(
    apiKeyStore: SecureApiKeyStore(backend: _MemorySecureApiKeyBackend()),
  );
  await settings.initialization;
  return settings;
}

Future<File> _fixtureFontFile() async {
  final file = File(_fixtureFontPath);
  if (!await file.exists()) {
    fail('Missing test font fixture: $_fixtureFontPath');
  }
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider local font persistence', () {
    late PathProviderPlatform previousPathProvider;
    late Directory tempDir;

    setUp(() async {
      previousPathProvider = PathProviderPlatform.instance;
      tempDir = await Directory.systemTemp.createTemp('kelivo_font_test_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    });

    tearDown(() async {
      PathProviderPlatform.instance = previousPathProvider;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('local font import stores managed copy path', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await _buildSettings();

      final sourceFile = await _fixtureFontFile();

      await settings.setAppFontFromLocal(path: sourceFile.path);

      final prefs = await SharedPreferences.getInstance();
      final storedPath = prefs.getString('display_app_font_local_path_v1');
      expect(storedPath, isNotNull);
      final normalizedStoredPath = p.normalize(p.absolute(storedPath!));
      final managedFontsDirectory = p.normalize(
        p.absolute(p.join(tempDir.path, 'fonts')),
      );
      expect(p.isWithin(managedFontsDirectory, normalizedStoredPath), isTrue);
      expect(await File(normalizedStoredPath).exists(), isTrue);
      expect(
        normalizedStoredPath,
        isNot(p.normalize(p.absolute(sourceFile.path))),
      );
      expect(prefs.getString('display_app_font_local_alias_v1'), isNotEmpty);
    });

    test('replacing local font removes previous managed copy', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await _buildSettings();
      final sourceFile = await _fixtureFontFile();

      await settings.setAppFontFromLocal(path: sourceFile.path);
      final prefs = await SharedPreferences.getInstance();
      final firstPath = prefs.getString('display_app_font_local_path_v1');
      expect(firstPath, isNotNull);
      expect(await File(firstPath!).exists(), isTrue);

      await settings.setAppFontFromLocal(path: sourceFile.path);
      final secondPath = prefs.getString('display_app_font_local_path_v1');
      expect(secondPath, isNotNull);
      expect(secondPath, isNot(firstPath));
      expect(await File(secondPath!).exists(), isTrue);
      expect(await File(firstPath).exists(), isFalse);
    });

    test(
      'clearing one font keeps managed copy still referenced by code font',
      () async {
        SharedPreferences.setMockInitialValues({});
        final settings = await _buildSettings();
        final sourceFile = await _fixtureFontFile();

        await settings.setAppFontFromLocal(path: sourceFile.path);
        final prefs = await SharedPreferences.getInstance();
        final appPath = prefs.getString('display_app_font_local_path_v1');
        expect(appPath, isNotNull);
        final sharedPath = appPath!;
        final appFamily = prefs.getString('display_app_font_family_v1')!;
        final appAlias = prefs.getString('display_app_font_local_alias_v1')!;

        SharedPreferences.setMockInitialValues({
          'display_app_font_family_v1': appFamily,
          'display_app_font_is_google_v1': false,
          'display_app_font_local_path_v1': sharedPath,
          'display_app_font_local_alias_v1': appAlias,
          'display_code_font_family_v1': 'kelivo_local_code_123',
          'display_code_font_is_google_v1': false,
          'display_code_font_local_path_v1': sharedPath,
          'display_code_font_local_alias_v1': 'kelivo_local_code_123',
        });
        final sharedSettings = await _buildSettings();

        await sharedSettings.clearAppFont();

        expect(await File(sharedPath).exists(), isTrue);
      },
    );

    test('failed local font registration removes imported copy', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await _buildSettings();
      final invalidFont = File('${tempDir.path}/invalid.ttf');
      await invalidFont.writeAsString('not a font');

      await settings.setAppFontFromLocal(path: invalidFont.path);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('display_app_font_local_path_v1'), isNull);
      final fontsDir = Directory('${tempDir.path}/fonts');
      final entries = await fontsDir.exists()
          ? await fontsDir.list().toList()
          : const <FileSystemEntity>[];
      expect(entries, isEmpty);
    });

    test('invalid persisted local font does not expose stale alias', () async {
      SharedPreferences.setMockInitialValues({
        'display_app_font_family_v1': 'kelivo_local_app_123',
        'display_app_font_is_google_v1': false,
        'display_app_font_local_path_v1':
            '/var/mobile/Containers/Data/Application/OLD/Documents/fonts/missing.ttf',
        'display_app_font_local_alias_v1': 'kelivo_local_app_123',
      });

      final settings = await _buildSettings();

      expect(settings.appFontLocalAlias, isNull);
      expect(settings.appFontFamily, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('display_app_font_local_alias_v1'), isNull);
      expect(prefs.getString('display_app_font_local_path_v1'), isNull);
    });

    test('persisted iOS sandbox font path is remapped on reload', () async {
      final sourceFile = await _fixtureFontFile();

      final fontsDir = Directory('${tempDir.path}/fonts');
      await fontsDir.create(recursive: true);
      final currentFont = File('${fontsDir.path}/SFNS.ttf');
      await currentFont.writeAsBytes(await sourceFile.readAsBytes());
      await SandboxPathResolver.init();

      SharedPreferences.setMockInitialValues({
        'display_app_font_family_v1': 'kelivo_local_app_123',
        'display_app_font_is_google_v1': false,
        'display_app_font_local_path_v1':
            '/var/mobile/Containers/Data/Application/OLD/Documents/fonts/SFNS.ttf',
        'display_app_font_local_alias_v1': 'kelivo_local_app_123',
      });

      final settings = await _buildSettings();

      expect(settings.appFontLocalAlias, isNotEmpty);
      expect(settings.appFontFamily, settings.appFontLocalAlias);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('display_app_font_local_path_v1'),
        currentFont.path,
      );
    });
  });
}

final class _MemorySecureApiKeyBackend implements SecureApiKeyBackend {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
