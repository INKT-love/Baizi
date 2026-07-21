import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:Baizi/core/models/assistant.dart';
import 'package:Baizi/core/models/assistant_character_data.dart';
import 'package:Baizi/core/models/character_card.dart';
import 'package:Baizi/core/models/world_book.dart';
import 'package:Baizi/core/providers/assistant_provider.dart';
import 'package:Baizi/core/providers/world_book_provider.dart';
import 'package:Baizi/core/services/character_card/character_card_import_service.dart';
import 'package:Baizi/core/services/character_card/character_card_parser.dart';
import 'package:Baizi/core/services/world_book_store.dart';

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

class _PartialWriteFile implements File {
  _PartialWriteFile(this._delegate);

  final File _delegate;

  @override
  String get path => _delegate.path;

  @override
  Directory get parent => _delegate.parent;

  @override
  Future<bool> exists() => _delegate.exists();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _delegate.delete(recursive: recursive);

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    await _delegate.writeAsBytes(
      bytes.take(1).toList(growable: false),
      mode: mode,
      flush: flush,
    );
    throw FileSystemException('Injected partial write failure.', path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      _delegate.noSuchMethod(invocation);
}

final class _PartialWriteOverrides extends IOOverrides {
  _PartialWriteOverrides(this.targetPath);

  final String targetPath;
  bool didInjectFailure = false;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    if (!didInjectFailure && p.equals(path, targetPath)) {
      didInjectFailure = true;
      return _PartialWriteFile(file);
    }
    return file;
  }
}

enum _PreferenceFailureMode { returnFalse, throwException }

final class _FailingSharedPreferencesStore
    extends SharedPreferencesStorePlatform {
  _FailingSharedPreferencesStore(
    this._delegate,
    Map<String, List<_PreferenceFailureMode>> failures,
  ) : _failures = <String, List<_PreferenceFailureMode>>{
        for (final entry in failures.entries)
          entry.key: List<_PreferenceFailureMode>.from(entry.value),
      };

  final SharedPreferencesStorePlatform _delegate;
  final Map<String, List<_PreferenceFailureMode>> _failures;

  Future<Map<String, Object>> durableValues() => _delegate.getAll();

  @override
  Future<bool> clear() => _delegate.clear();

  @override
  Future<Map<String, Object>> getAll() => _delegate.getAll();

  @override
  Future<bool> remove(String key) => _delegate.remove(key);

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    final failures = _failures[key];
    if (failures != null && failures.isNotEmpty) {
      final failure = failures.removeAt(0);
      if (failure == _PreferenceFailureMode.returnFalse) {
        return Future<bool>.value(false);
      }
      throw StateError('Injected preference write failure for $key.');
    }
    return _delegate.setValue(valueType, key, value);
  }
}

Future<AssistantProvider> _loadProvider(List<Assistant> assistants) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'assistants_v1': Assistant.encodeList(assistants),
    if (assistants.isNotEmpty) 'current_assistant_id_v1': assistants.first.id,
  });
  await WorldBookStore.clear();
  final provider = AssistantProvider();
  for (var attempt = 0; attempt < 50; attempt++) {
    if (provider.assistants.length == assistants.length) return provider;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return provider;
}

Future<void> _seedWorldBookSnapshot(WorldBook book) async {
  await WorldBookStore.save(<WorldBook>[book]);
  await WorldBookStore.setActiveIdsMap(<String, List<String>>{
    'existing': <String>[book.id],
  });
  await WorldBookStore.setCollapsedMap(<String, bool>{book.id: true});
}

Future<void> _expectWorldBookSnapshot(
  WorldBook book,
  _FailingSharedPreferencesStore store,
) async {
  expect(
    (await WorldBookStore.getAll()).map((item) => item.toJson()).toList(),
    <Map<String, dynamic>>[book.toJson()],
  );
  expect(await WorldBookStore.getActiveIdsByAssistant(), <String, List<String>>{
    'existing': <String>[book.id],
  });
  expect(await WorldBookStore.getCollapsedBooksMap(), <String, bool>{
    book.id: true,
  });

  final durable = await store.durableValues();
  expect(
    jsonDecode(durable['flutter.world_books_v1']! as String),
    <Map<String, dynamic>>[book.toJson()],
  );
  expect(
    jsonDecode(
      durable['flutter.world_books_active_ids_by_assistant_v1']! as String,
    ),
    <String, dynamic>{
      'existing': <String>[book.id],
    },
  );
  expect(
    jsonDecode(durable['flutter.world_books_collapsed_v1']! as String),
    <String, dynamic>{book.id: true},
  );
}

Map<String, dynamic> _v3Card({
  String name = 'Luna',
  bool includeWorldBook = true,
}) => <String, dynamic>{
  'spec': 'chara_card_v3',
  'spec_version': '3.0',
  'data': <String, dynamic>{
    'name': name,
    'description': 'Moonlit guide',
    'personality': 'Calm',
    'scenario': 'A quiet observatory',
    'first_mes': 'Hello, {{user}}.',
    'mes_example': '<START>\n{{char}}: Welcome.',
    'creator_notes': '',
    'system_prompt': 'Stay in character.',
    'post_history_instructions': 'Remain concise.',
    'alternate_greetings': <String>['Good evening.'],
    'tags': <String>['guide'],
    'creator': 'tester',
    'character_version': '1.0',
    'extensions': <String, dynamic>{},
    'group_only_greetings': <String>[],
    if (includeWorldBook)
      'character_book': <String, dynamic>{
        'name': 'Luna lore',
        'entries': <Map<String, dynamic>>[
          <String, dynamic>{
            'keys': <String>['moon'],
            'content': 'The observatory opens at night.',
            'enabled': true,
            'insertion_order': 10,
          },
        ],
      },
  },
};

Uint8List _uint32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.big);
  return data.buffer.asUint8List();
}

Uint8List _chunk(String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  var crc = getCrc32(typeBytes);
  crc = getCrc32(data, crc);
  return Uint8List.fromList(<int>[
    ..._uint32(data.length),
    ...typeBytes,
    ...data,
    ..._uint32(crc),
  ]);
}

Uint8List _pngCard(Map<String, dynamic> card) {
  final base = image.encodePng(image.Image(width: 1, height: 1));
  final encoded = base64Encode(utf8.encode(jsonEncode(card)));
  final metadata = _chunk('tEXt', <int>[
    ...latin1.encode('ccv3'),
    0,
    ...latin1.encode(encoded),
  ]);
  final iendOffset = base.length - 12;
  return Uint8List.fromList(<int>[
    ...base.sublist(0, iendOffset),
    ...metadata,
    ...base.sublist(iendOffset),
  ]);
}

CharacterCardIdFactory _ids(List<String> values) {
  final remaining = List<String>.from(values);
  return () => remaining.removeAt(0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late Directory cardsDirectory;
  late Directory avatarsDirectory;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await WorldBookStore.clear();
    tempDirectory = await Directory.systemTemp.createTemp(
      'baizi_character_import_',
    );
    cardsDirectory = Directory('${tempDirectory.path}/character_cards');
    avatarsDirectory = Directory('${tempDirectory.path}/avatars');
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      tempDirectory.path,
    );
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await WorldBookStore.clear();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  group('CharacterCardImportService preview validation', () {
    test('previews JSON card counts and preserves source name', () async {
      final service = CharacterCardImportService(
        characterCardsDirectory: () async => cardsDirectory,
        avatarsDirectory: () async => avatarsDirectory,
      );
      final preview = await service.prepareBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(_v3Card()))),
        sourceFileName: '月光角色.json',
      );

      expect(preview.isPng, isFalse);
      expect(preview.sourceFileName, '月光角色.json');
      expect(preview.document.data.name, 'Luna');
      expect(preview.greetingCount, 2);
      expect(preview.worldBookEntryCount, 1);
    });

    test('fully decodes PNG pixels before accepting metadata', () async {
      final service = CharacterCardImportService(
        characterCardsDirectory: () async => cardsDirectory,
        avatarsDirectory: () async => avatarsDirectory,
      );
      final png = _pngCard(_v3Card());

      final preview = await service.prepareBytes(
        png,
        sourceFileName: 'luna.png',
      );

      expect(preview.isPng, isTrue);
      expect(preview.imageWidth, 1);
      expect(preview.imageHeight, 1);
      expect(preview.document.data.name, 'Luna');
    });

    test('rejects unsupported files and configured size boundary', () async {
      final service = CharacterCardImportService(
        parser: const CharacterCardParser(
          limits: CharacterCardLimits(maxFileBytes: 4),
        ),
        characterCardsDirectory: () async => cardsDirectory,
        avatarsDirectory: () async => avatarsDirectory,
      );

      expect(
        () => service.prepareBytes(
          Uint8List.fromList(<int>[1]),
          sourceFileName: 'card.txt',
        ),
        throwsA(isA<CharacterCardImportException>()),
      );
      expect(
        () => service.prepareBytes(
          Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
          sourceFileName: 'card.json',
        ),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.fileTooLarge,
          ),
        ),
      );
    });

    test('rejects oversized dimensions before pixel allocation', () async {
      final bytes = Uint8List(33);
      bytes.setAll(0, const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
      ByteData.sublistView(bytes).setUint32(8, 13);
      bytes.setAll(12, ascii.encode('IHDR'));
      ByteData.sublistView(bytes)
        ..setUint32(16, 8193)
        ..setUint32(20, 1);
      final service = CharacterCardImportService(
        characterCardsDirectory: () async => cardsDirectory,
        avatarsDirectory: () async => avatarsDirectory,
      );

      expect(
        () => service.prepareBytes(bytes, sourceFileName: 'huge.png'),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.pngDimensionsTooLarge,
          ),
        ),
      );
    });
  });

  group('CharacterCardImportService transaction', () {
    test('creates a copy, saves raw JSON, and binds its world book', () async {
      final provider = await _loadProvider(const <Assistant>[
        Assistant(id: 'existing', name: 'Luna'),
      ]);
      final worldBookProvider = WorldBookProvider();
      await worldBookProvider.initialize();
      final service = CharacterCardImportService(
        characterCardsDirectory: () async => cardsDirectory,
        avatarsDirectory: () async => avatarsDirectory,
        idFactory: _ids(<String>[
          'assistant-new',
          'operation-1',
          'book-1',
          'entry-1',
        ]),
      );
      final sourceBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(_v3Card())),
      );
      final preview = await service.prepareBytes(
        sourceBytes,
        sourceFileName: '月光角色.json',
      );

      final result = await service.commit(
        preview: preview,
        assistantProvider: provider,
        worldBookProvider: worldBookProvider,
        copySuffix: '副本',
      );

      expect(result.assistantId, 'assistant-new');
      expect(result.assistantName, 'Luna 副本');
      expect(result.overwritten, isFalse);
      final imported = provider.getById('assistant-new')!;
      expect(imported.chatModelProvider, 'baizi');
      expect(imported.streamOutput, isTrue);
      expect(imported.characterData?.cardWorldBookId, 'book-1');
      expect(imported.characterData?.sourceFileName, contains('月光角色.json'));
      final source = File(
        '${cardsDirectory.path}/assistant-new/operation-1/月光角色.json',
      );
      expect(await source.readAsBytes(), sourceBytes);
      expect(worldBookProvider.getById('book-1'), isNotNull);
      expect(
        worldBookProvider.activeBookIdsFor('assistant-new'),
        contains('book-1'),
      );
    });

    test(
      'overwrites in place and preserves advanced assistant settings',
      () async {
        await cardsDirectory.create(recursive: true);
        await avatarsDirectory.create(recursive: true);
        final oldSource = File('${cardsDirectory.path}/old/card.json');
        await oldSource.parent.create(recursive: true);
        await oldSource.writeAsString('{}');
        final oldAvatar = File('${avatarsDirectory.path}/old.png');
        await oldAvatar.writeAsBytes(<int>[1, 2, 3]);
        final provider = await _loadProvider(<Assistant>[
          Assistant(
            id: 'existing',
            name: 'Old Luna',
            avatar: oldAvatar.path,
            chatModelProvider: 'legacy',
            chatModelId: 'kept-model',
            temperature: 1.1,
            enableMemory: true,
            characterData: AssistantCharacterData(
              sourceFileName: 'old/card.json',
            ),
          ),
          const Assistant(id: 'keep', name: 'Keep'),
        ]);
        final service = CharacterCardImportService(
          characterCardsDirectory: () async => cardsDirectory,
          avatarsDirectory: () async => avatarsDirectory,
          idFactory: _ids(<String>['operation-2', 'book-unused']),
        );
        final preview = await service.prepareBytes(
          Uint8List.fromList(
            utf8.encode(
              jsonEncode(_v3Card(name: 'New Luna', includeWorldBook: false)),
            ),
          ),
          sourceFileName: 'new-card.json',
        );

        final result = await service.commit(
          preview: preview,
          assistantProvider: provider,
          overwriteAssistantId: 'existing',
          copySuffix: 'Copy',
        );

        expect(result.assistantId, 'existing');
        expect(result.overwritten, isTrue);
        final imported = provider.getById('existing')!;
        expect(imported.name, 'New Luna');
        expect(imported.chatModelProvider, 'baizi');
        expect(imported.chatModelId, 'kept-model');
        expect(imported.temperature, 1.1);
        expect(imported.enableMemory, isTrue);
        expect(imported.avatar, isNull);
        expect(await oldSource.exists(), isFalse);
        expect(await oldAvatar.exists(), isFalse);
      },
    );

    test('removes staged files when avatar storage fails', () async {
      final provider = await _loadProvider(const <Assistant>[
        Assistant(id: 'existing', name: 'Existing'),
      ]);
      final invalidAvatarDirectory = File('${tempDirectory.path}/not-a-dir');
      await invalidAvatarDirectory.writeAsString('blocked');
      final service = CharacterCardImportService(
        characterCardsDirectory: () async => cardsDirectory,
        avatarsDirectory: () async => Directory(invalidAvatarDirectory.path),
        idFactory: _ids(<String>[
          'assistant-new',
          'operation-3',
          'book-3',
          'entry-3',
        ]),
      );
      final preview = await service.prepareBytes(
        _pngCard(_v3Card()),
        sourceFileName: 'luna.png',
      );

      expect(
        () => service.commit(
          preview: preview,
          assistantProvider: provider,
          copySuffix: 'Copy',
        ),
        throwsA(
          isA<CharacterCardImportException>().having(
            (error) => error.code,
            'code',
            CharacterCardImportErrorCode.storageFailed,
          ),
        ),
      );
      expect(provider.getById('assistant-new'), isNull);
      final staged = cardsDirectory.existsSync()
          ? cardsDirectory.listSync(recursive: true).whereType<File>()
          : const <File>[];
      expect(staged, isEmpty);
      expect(await WorldBookStore.getAll(), isEmpty);
    });

    test('removes a partially written source when its write fails', () async {
      final provider = await _loadProvider(const <Assistant>[
        Assistant(id: 'existing', name: 'Existing'),
      ]);
      final service = CharacterCardImportService(
        characterCardsDirectory: () async => cardsDirectory,
        avatarsDirectory: () async => avatarsDirectory,
        idFactory: _ids(<String>[
          'assistant-new',
          'operation-partial',
          'book-partial',
          'entry-partial',
        ]),
      );
      final preview = await service.prepareBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(_v3Card()))),
        sourceFileName: 'partial.json',
      );
      final sourcePath = p.join(
        cardsDirectory.path,
        'assistant-new',
        'operation-partial',
        'partial.json',
      );
      final overrides = _PartialWriteOverrides(sourcePath);

      final commit = IOOverrides.runZoned(
        () => service.commit(
          preview: preview,
          assistantProvider: provider,
          copySuffix: 'Copy',
        ),
        createFile: overrides.createFile,
      );

      await expectLater(
        commit,
        throwsA(
          isA<CharacterCardImportException>().having(
            (error) => error.code,
            'code',
            CharacterCardImportErrorCode.storageFailed,
          ),
        ),
      );
      expect(overrides.didInjectFailure, isTrue);
      expect(await File(sourcePath).exists(), isFalse);
      expect(provider.getById('assistant-new'), isNull);
      expect(await WorldBookStore.getAll(), isEmpty);
    });

    test(
      'rejects a blank preview name before overwriting an assistant',
      () async {
        final provider = await _loadProvider(const <Assistant>[
          Assistant(id: 'existing', name: 'Original name'),
        ]);
        final service = CharacterCardImportService(
          characterCardsDirectory: () async => cardsDirectory,
          avatarsDirectory: () async => avatarsDirectory,
          idFactory: _ids(<String>['operation-blank', 'unused-book']),
        );
        final preview = CharacterCardImportPreview(
          sourceFileName: 'blank.json',
          isPng: false,
          document: CharacterCardDocument(
            spec: CharacterCardSpec.v3,
            specVersion: '3.0',
            data: CharacterCardData(name: ' \t\n'),
          ),
          sourceBytes: Uint8List.fromList(utf8.encode('{}')),
        );

        await expectLater(
          service.commit(
            preview: preview,
            assistantProvider: provider,
            overwriteAssistantId: 'existing',
            copySuffix: 'Copy',
          ),
          throwsA(
            isA<CharacterCardParseException>().having(
              (error) => error.code,
              'code',
              CharacterCardParseErrorCode.invalidCard,
            ),
          ),
        );
        expect(provider.getById('existing')?.name, 'Original name');
        expect(await WorldBookStore.getAll(), isEmpty);
        expect(await cardsDirectory.exists(), isFalse);
      },
    );

    test(
      'rolls back when active world books return persistence failure',
      () async {
        const oldBook = WorldBook(
          id: 'old-book',
          name: 'Old lore',
          entries: <WorldBookEntry>[
            WorldBookEntry(id: 'old-entry', content: 'Old content'),
          ],
        );
        final provider = await _loadProvider(const <Assistant>[
          Assistant(id: 'existing', name: 'Existing'),
        ]);
        await _seedWorldBookSnapshot(oldBook);
        final service = CharacterCardImportService(
          characterCardsDirectory: () async => cardsDirectory,
          avatarsDirectory: () async => avatarsDirectory,
          idFactory: _ids(<String>[
            'assistant-new',
            'operation-active',
            'new-book',
            'new-entry',
          ]),
        );
        final preview = await service.prepareBytes(
          Uint8List.fromList(utf8.encode(jsonEncode(_v3Card()))),
          sourceFileName: 'active-failure.json',
        );
        final failingStore = _FailingSharedPreferencesStore(
          SharedPreferencesStorePlatform.instance,
          <String, List<_PreferenceFailureMode>>{
            'flutter.world_books_active_ids_by_assistant_v1':
                <_PreferenceFailureMode>[_PreferenceFailureMode.returnFalse],
          },
        );
        SharedPreferencesStorePlatform.instance = failingStore;

        await expectLater(
          service.commit(
            preview: preview,
            assistantProvider: provider,
            copySuffix: 'Copy',
          ),
          throwsA(
            isA<CharacterCardImportException>().having(
              (error) => error.code,
              'code',
              CharacterCardImportErrorCode.storageFailed,
            ),
          ),
        );
        expect(provider.getById('assistant-new'), isNull);
        await _expectWorldBookSnapshot(oldBook, failingStore);
        expect(
          cardsDirectory.existsSync()
              ? cardsDirectory.listSync(recursive: true).whereType<File>()
              : const <File>[],
          isEmpty,
        );
      },
    );

    test(
      'rolls back when collapsed world books throw during persistence',
      () async {
        const oldBook = WorldBook(
          id: 'old-book',
          name: 'Old lore',
          entries: <WorldBookEntry>[
            WorldBookEntry(id: 'old-entry', content: 'Old content'),
          ],
        );
        final provider = await _loadProvider(<Assistant>[
          Assistant(
            id: 'existing',
            name: 'Original name',
            characterData: AssistantCharacterData(cardWorldBookId: 'old-book'),
          ),
        ]);
        await _seedWorldBookSnapshot(oldBook);
        final service = CharacterCardImportService(
          characterCardsDirectory: () async => cardsDirectory,
          avatarsDirectory: () async => avatarsDirectory,
          idFactory: _ids(<String>['operation-collapsed']),
        );
        final preview = await service.prepareBytes(
          Uint8List.fromList(
            utf8.encode(
              jsonEncode(_v3Card(name: 'Replacement', includeWorldBook: false)),
            ),
          ),
          sourceFileName: 'collapsed-failure.json',
        );
        final failingStore = _FailingSharedPreferencesStore(
          SharedPreferencesStorePlatform.instance,
          <String, List<_PreferenceFailureMode>>{
            'flutter.world_books_collapsed_v1': <_PreferenceFailureMode>[
              _PreferenceFailureMode.throwException,
            ],
          },
        );
        SharedPreferencesStorePlatform.instance = failingStore;

        await expectLater(
          service.commit(
            preview: preview,
            assistantProvider: provider,
            overwriteAssistantId: 'existing',
            copySuffix: 'Copy',
          ),
          throwsA(
            isA<CharacterCardImportException>().having(
              (error) => error.code,
              'code',
              CharacterCardImportErrorCode.storageFailed,
            ),
          ),
        );
        expect(provider.getById('existing')?.name, 'Original name');
        await _expectWorldBookSnapshot(oldBook, failingStore);
        expect(
          cardsDirectory.existsSync()
              ? cardsDirectory.listSync(recursive: true).whereType<File>()
              : const <File>[],
          isEmpty,
        );
      },
    );

    test('fully rolls back when the assistant commit fails', () async {
      const oldBook = WorldBook(
        id: 'old-book',
        name: 'Old lore',
        entries: <WorldBookEntry>[
          WorldBookEntry(id: 'old-entry', content: 'Old content'),
        ],
      );
      final provider = await _loadProvider(const <Assistant>[
        Assistant(id: 'existing', name: 'Existing'),
      ]);
      await _seedWorldBookSnapshot(oldBook);
      final service = CharacterCardImportService(
        characterCardsDirectory: () async => cardsDirectory,
        avatarsDirectory: () async => avatarsDirectory,
        idFactory: _ids(<String>[
          'assistant-new',
          'operation-assistant',
          'new-book',
          'new-entry',
        ]),
      );
      final preview = await service.prepareBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(_v3Card()))),
        sourceFileName: 'assistant-failure.json',
      );
      final failingStore = _FailingSharedPreferencesStore(
        SharedPreferencesStorePlatform.instance,
        <String, List<_PreferenceFailureMode>>{
          'flutter.assistants_v1': <_PreferenceFailureMode>[
            _PreferenceFailureMode.throwException,
          ],
        },
      );
      SharedPreferencesStorePlatform.instance = failingStore;

      await expectLater(
        service.commit(
          preview: preview,
          assistantProvider: provider,
          copySuffix: 'Copy',
        ),
        throwsA(
          isA<CharacterCardImportException>().having(
            (error) => error.code,
            'code',
            CharacterCardImportErrorCode.storageFailed,
          ),
        ),
      );
      expect(provider.assistants.map((assistant) => assistant.id), <String>[
        'existing',
      ]);
      await _expectWorldBookSnapshot(oldBook, failingStore);
      expect(
        cardsDirectory.existsSync()
            ? cardsDirectory.listSync(recursive: true).whereType<File>()
            : const <File>[],
        isEmpty,
      );
    });

    test(
      'deleting an imported PNG removes source, avatar, and world book',
      () async {
        final provider = await _loadProvider(const <Assistant>[
          Assistant(id: 'existing', name: 'Existing'),
        ]);
        final worldBookProvider = WorldBookProvider();
        await worldBookProvider.initialize();
        final service = CharacterCardImportService(
          characterCardsDirectory: () async => cardsDirectory,
          avatarsDirectory: () async => avatarsDirectory,
          idFactory: _ids(<String>[
            'assistant-new',
            'operation-4',
            'book-4',
            'entry-4',
          ]),
        );
        final preview = await service.prepareBytes(
          _pngCard(_v3Card()),
          sourceFileName: 'luna.png',
        );
        await service.commit(
          preview: preview,
          assistantProvider: provider,
          worldBookProvider: worldBookProvider,
          copySuffix: 'Copy',
        );
        final imported = provider.getById('assistant-new')!;
        final sourcePath = imported.characterData!.sourceFileName!;
        final source = File(
          '${cardsDirectory.path}/${sourcePath.replaceAll('/', Platform.pathSeparator)}',
        );
        final avatar = File(imported.avatar!);
        expect(await source.exists(), isTrue);
        expect(await avatar.exists(), isTrue);

        final deletingProvider = AssistantProvider(
          worldBookProvider: worldBookProvider,
        );
        for (var attempt = 0; attempt < 50; attempt++) {
          if (deletingProvider.assistants.length == 2) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(await deletingProvider.deleteAssistant('assistant-new'), isTrue);
        expect(await source.exists(), isFalse);
        expect(await avatar.exists(), isFalse);
        expect(await WorldBookStore.getAll(), isEmpty);
        expect(worldBookProvider.getById('book-4'), isNull);
      },
    );
  });

  group('WorldBookProvider persistence ordering', () {
    test(
      'does not publish active or collapsed state after write failure',
      () async {
        const book = WorldBook(id: 'book-1', name: 'Lore');
        await WorldBookStore.save(const <WorldBook>[book]);
        await WorldBookStore.setActiveIds(const <String>[
          'book-1',
        ], assistantId: 'existing');
        await WorldBookStore.setCollapsed('book-1', true);
        final provider = WorldBookProvider();
        await provider.initialize();
        final failingStore = _FailingSharedPreferencesStore(
          SharedPreferencesStorePlatform.instance,
          <String, List<_PreferenceFailureMode>>{
            'flutter.world_books_active_ids_by_assistant_v1':
                <_PreferenceFailureMode>[_PreferenceFailureMode.returnFalse],
            'flutter.world_books_collapsed_v1': <_PreferenceFailureMode>[
              _PreferenceFailureMode.throwException,
            ],
          },
        );
        SharedPreferencesStorePlatform.instance = failingStore;

        await expectLater(
          provider.setActiveBookIds(const <String>[], assistantId: 'existing'),
          throwsStateError,
        );
        await expectLater(
          provider.setBookCollapsed('book-1', false),
          throwsStateError,
        );

        expect(provider.activeBookIdsFor('existing'), <String>['book-1']);
        expect(provider.isBookCollapsed('book-1'), isTrue);
        expect(
          await WorldBookStore.getActiveIds(assistantId: 'existing'),
          <String>['book-1'],
        );
        expect((await WorldBookStore.getCollapsedBooksMap())['book-1'], isTrue);
      },
    );
  });
}
