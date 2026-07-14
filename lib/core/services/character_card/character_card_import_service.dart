import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../utils/app_directories.dart';
import '../../models/assistant.dart';
import '../../models/character_card.dart';
import '../../models/world_book.dart';
import '../../providers/assistant_provider.dart';
import '../../providers/world_book_provider.dart';
import '../world_book_store.dart';
import 'character_card_import_mapper.dart';
import 'character_card_parser.dart';

enum CharacterCardImportErrorCode {
  unsupportedFileType,
  fileReadFailed,
  storageFailed,
  overwriteTargetMissing,
}

class CharacterCardImportException implements Exception {
  const CharacterCardImportException(this.code, this.message);

  final CharacterCardImportErrorCode code;
  final String message;

  @override
  String toString() => 'CharacterCardImportException(${code.name}): $message';
}

class CharacterCardImportPreview {
  CharacterCardImportPreview({
    required this.sourceFileName,
    required this.isPng,
    required this.document,
    required Uint8List sourceBytes,
    this.imageWidth,
    this.imageHeight,
  }) : sourceBytes = Uint8List.fromList(sourceBytes);

  final String sourceFileName;
  final bool isPng;
  final CharacterCardDocument document;
  final Uint8List sourceBytes;
  final int? imageWidth;
  final int? imageHeight;

  int get greetingCount {
    var count = document.data.firstMes.trim().isEmpty ? 0 : 1;
    count += document.data.alternateGreetings
        .where((greeting) => greeting.trim().isNotEmpty)
        .length;
    return count;
  }

  int get worldBookEntryCount =>
      document.data.characterBook?.entries.length ?? 0;
}

class CharacterCardImportResult {
  const CharacterCardImportResult({
    required this.assistantId,
    required this.assistantName,
    required this.overwritten,
  });

  final String assistantId;
  final String assistantName;
  final bool overwritten;
}

typedef CharacterCardDirectoryFactory = Future<Directory> Function();
typedef CharacterCardIdFactory = String Function();

class CharacterCardImportService {
  // The default pixel cap bounds a decoded RGBA frame to roughly 64 MiB;
  // the per-edge cap also rejects pathological row dimensions early.
  CharacterCardImportService({
    CharacterCardParser? parser,
    CharacterCardImportMapper? mapper,
    CharacterCardDirectoryFactory? characterCardsDirectory,
    CharacterCardDirectoryFactory? avatarsDirectory,
    CharacterCardIdFactory? idFactory,
    this.maxPngDimension = 8192,
    this.maxPngPixels = 16 * 1024 * 1024,
  }) : parser = parser ?? const CharacterCardParser(),
       mapper = mapper ?? const CharacterCardImportMapper(),
       characterCardsDirectory =
           characterCardsDirectory ?? AppDirectories.getCharacterCardsDirectory,
       avatarsDirectory =
           avatarsDirectory ?? AppDirectories.getAvatarsDirectory,
       idFactory = idFactory ?? const Uuid().v4;

  final CharacterCardParser parser;
  final CharacterCardImportMapper mapper;
  final CharacterCardDirectoryFactory characterCardsDirectory;
  final CharacterCardDirectoryFactory avatarsDirectory;
  final CharacterCardIdFactory idFactory;
  final int maxPngDimension;
  final int maxPngPixels;

  Future<CharacterCardImportPreview> prepareFile(String filePath) async {
    final file = File(filePath);
    try {
      final size = await file.length();
      if (size > parser.limits.maxFileBytes) {
        throw CharacterCardParseException(
          CharacterCardParseErrorCode.fileTooLarge,
          'Character card exceeds ${parser.limits.maxFileBytes} bytes.',
        );
      }
      final bytes = await file.readAsBytes();
      return prepareBytes(bytes, sourceFileName: p.basename(filePath));
    } on CharacterCardParseException {
      rethrow;
    } on FileSystemException {
      throw const CharacterCardImportException(
        CharacterCardImportErrorCode.fileReadFailed,
        'The selected character card could not be read.',
      );
    }
  }

  Future<CharacterCardImportPreview> prepareBytes(
    Uint8List bytes, {
    required String sourceFileName,
  }) async {
    if (bytes.length > parser.limits.maxFileBytes) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.fileTooLarge,
        'Character card exceeds ${parser.limits.maxFileBytes} bytes.',
      );
    }

    final extension = p.extension(sourceFileName).toLowerCase();
    if (extension == '.json') {
      return CharacterCardImportPreview(
        sourceFileName: p.basename(sourceFileName),
        isPng: false,
        document: parser.parseJsonBytes(bytes),
        sourceBytes: bytes,
      );
    }
    if (extension != '.png') {
      throw const CharacterCardImportException(
        CharacterCardImportErrorCode.unsupportedFileType,
        'Only PNG and JSON character cards are supported.',
      );
    }

    final dimensions = await _validatePngPixels(bytes);
    return CharacterCardImportPreview(
      sourceFileName: p.basename(sourceFileName),
      isPng: true,
      document: parser.parsePngBytes(bytes),
      sourceBytes: bytes,
      imageWidth: dimensions.$1,
      imageHeight: dimensions.$2,
    );
  }

  Future<CharacterCardImportResult> commit({
    required CharacterCardImportPreview preview,
    required AssistantProvider assistantProvider,
    WorldBookProvider? worldBookProvider,
    String? overwriteAssistantId,
    required String copySuffix,
  }) async {
    final existing = overwriteAssistantId == null
        ? null
        : assistantProvider.getById(overwriteAssistantId);
    if (overwriteAssistantId != null && existing == null) {
      throw const CharacterCardImportException(
        CharacterCardImportErrorCode.overwriteTargetMissing,
        'The assistant selected for overwrite no longer exists.',
      );
    }

    final assistantId = existing?.id ?? idFactory();
    final operationId = idFactory();
    final sourceBaseName = _safeSourceBaseName(preview.sourceFileName);
    final sourceRelativePath = p.posix.join(
      _safePathSegment(assistantId),
      _safePathSegment(operationId),
      sourceBaseName,
    );
    final cardsDirectory = await characterCardsDirectory();
    final sourceFile = File(
      p.joinAll(<String>[
        cardsDirectory.path,
        ...sourceRelativePath.split('/'),
      ]),
    );

    File? avatarFile;
    if (preview.isPng) {
      final directory = await avatarsDirectory();
      avatarFile = File(
        p.join(
          directory.path,
          'character_${_safePathSegment(assistantId)}_'
          '${_safePathSegment(operationId)}.png',
        ),
      );
    }

    final oldWorldBooks = await WorldBookStore.getAll();
    final oldActiveIds = await WorldBookStore.getActiveIdsByAssistant();
    final oldCollapsed = await WorldBookStore.getCollapsedBooksMap();
    final oldCardWorldBookId = existing?.characterData?.cardWorldBookId;
    final worldBookId = oldCardWorldBookId ?? idFactory();

    final mapping = mapper.map(
      preview.document,
      sourceFileName: sourceRelativePath,
      isPng: preview.isPng,
      worldBookId: worldBookId,
      entryIdFactory: (_, __) => idFactory(),
    );
    final mappedName = mapping.name.trim();
    if (mappedName.isEmpty) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidCard,
        'Character card name cannot be empty.',
      );
    }
    final name = existing == null
        ? _uniqueName(
            mappedName,
            assistantProvider.assistants.map((assistant) => assistant.name),
            copySuffix,
          )
        : mappedName;
    final imported = existing == null
        ? Assistant(
            id: assistantId,
            name: name,
            avatar: avatarFile?.path,
            useAssistantAvatar: preview.isPng,
            useAssistantName: true,
            chatModelProvider: 'baizi',
            temperature: 0.6,
            topP: null,
            streamOutput: true,
            characterData: mapping.characterData,
          )
        : existing.copyWith(
            name: name,
            avatar: avatarFile?.path,
            clearAvatar: !preview.isPng,
            useAssistantAvatar: preview.isPng,
            useAssistantName: true,
            chatModelProvider: 'baizi',
            characterData: mapping.characterData,
          );

    var filesStaged = false;
    var worldBooksChanged = false;
    try {
      filesStaged = true;
      await sourceFile.parent.create(recursive: true);
      await sourceFile.writeAsBytes(preview.sourceBytes, flush: true);
      if (avatarFile != null) {
        await avatarFile.parent.create(recursive: true);
        await avatarFile.writeAsBytes(preview.sourceBytes, flush: true);
      }

      final nextBooks = List<WorldBook>.from(oldWorldBooks)
        ..removeWhere(
          (book) =>
              book.id == oldCardWorldBookId || book.id == mapping.worldBook?.id,
        );
      if (mapping.worldBook != null) nextBooks.add(mapping.worldBook!);
      worldBooksChanged = true;
      await WorldBookStore.save(nextBooks);

      final nextActiveIds = <String, List<String>>{
        for (final entry in oldActiveIds.entries)
          entry.key: List<String>.from(entry.value),
      };
      for (final entry in nextActiveIds.entries) {
        entry.value.removeWhere((id) => id == oldCardWorldBookId);
      }
      if (mapping.worldBook != null) {
        final assistantKey = WorldBookStore.assistantKey(assistantId);
        final active = nextActiveIds.putIfAbsent(
          assistantKey,
          () => List<String>.from(
            oldActiveIds[WorldBookStore.assistantKey(null)] ?? const <String>[],
          ),
        );
        if (!active.contains(mapping.worldBook!.id)) {
          active.add(mapping.worldBook!.id);
        }
      }
      await WorldBookStore.setActiveIdsMap(nextActiveIds);
      if (oldCardWorldBookId != null && mapping.worldBook == null) {
        final nextCollapsed = Map<String, bool>.from(oldCollapsed)
          ..remove(oldCardWorldBookId);
        await WorldBookStore.setCollapsedMap(nextCollapsed);
      }
      await assistantProvider.commitImportedAssistant(
        imported,
        replaceAssistantId: existing?.id,
      );
    } catch (error) {
      if (worldBooksChanged) {
        await _restoreWorldBooks(oldWorldBooks, oldActiveIds, oldCollapsed);
      }
      if (filesStaged) {
        await _deleteFileQuietly(sourceFile);
        await _deleteFileQuietly(avatarFile);
      }
      if (error is CharacterCardImportException ||
          error is CharacterCardParseException) {
        rethrow;
      }
      throw const CharacterCardImportException(
        CharacterCardImportErrorCode.storageFailed,
        'The character card could not be saved.',
      );
    }

    await _deletePreviousFiles(existing, sourceFile, avatarFile);
    await worldBookProvider?.loadAll();
    return CharacterCardImportResult(
      assistantId: assistantId,
      assistantName: name,
      overwritten: existing != null,
    );
  }

  Future<(int, int)> _validatePngPixels(Uint8List bytes) async {
    if (bytes.length < 33 ||
        bytes[0] != 0x89 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x4e ||
        bytes[3] != 0x47 ||
        bytes[4] != 0x0d ||
        bytes[5] != 0x0a ||
        bytes[6] != 0x1a ||
        bytes[7] != 0x0a ||
        bytes[8] != 0x00 ||
        bytes[9] != 0x00 ||
        bytes[10] != 0x00 ||
        bytes[11] != 0x0d ||
        bytes[12] != 0x49 ||
        bytes[13] != 0x48 ||
        bytes[14] != 0x44 ||
        bytes[15] != 0x52) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidPngPixels,
        'PNG is missing a valid IHDR image header.',
      );
    }
    final data = ByteData.sublistView(bytes);
    final width = data.getUint32(16);
    final height = data.getUint32(20);
    final pixels = width * height;
    if (width < 1 ||
        height < 1 ||
        width > maxPngDimension ||
        height > maxPngDimension ||
        pixels > maxPngPixels) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.pngDimensionsTooLarge,
        'PNG dimensions exceed the safe decoding limit.',
      );
    }

    List<int>? decodedDimensions;
    try {
      decodedDimensions = await Isolate.run<List<int>?>(() {
        final decoded = image.decodePng(bytes);
        return decoded == null ? null : <int>[decoded.width, decoded.height];
      });
    } catch (_) {
      decodedDimensions = null;
    }
    if (decodedDimensions == null ||
        decodedDimensions.length != 2 ||
        decodedDimensions[0] != width ||
        decodedDimensions[1] != height) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidPngPixels,
        'PNG pixel data could not be decoded safely.',
      );
    }
    return (width, height);
  }

  Future<void> _restoreWorldBooks(
    List<WorldBook> books,
    Map<String, List<String>> activeIds,
    Map<String, bool> collapsed,
  ) async {
    try {
      await WorldBookStore.save(books);
      await WorldBookStore.setActiveIdsMap(activeIds);
      await WorldBookStore.setCollapsedMap(collapsed);
    } catch (error, stackTrace) {
      debugPrint(
        'Character card WorldBook rollback failed: '
        '${error.runtimeType}\n$stackTrace',
      );
    }
  }

  Future<void> _deletePreviousFiles(
    Assistant? existing,
    File sourceFile,
    File? avatarFile,
  ) async {
    if (existing == null) return;
    final oldSource = existing.characterData?.sourceFileName;
    if (oldSource != null) {
      try {
        final directory = await characterCardsDirectory();
        final candidate = File(
          p.joinAll(<String>[directory.path, ...oldSource.split('/')]),
        );
        if (_isWithin(directory, candidate) &&
            !p.equals(candidate.path, sourceFile.path)) {
          await _deleteFileQuietly(candidate);
        }
      } catch (_) {}
    }

    final oldAvatar = existing.avatar?.trim();
    if (oldAvatar == null || oldAvatar.isEmpty) return;
    try {
      final directory = await avatarsDirectory();
      final candidate = File(oldAvatar);
      if (_isWithin(directory, candidate) &&
          (avatarFile == null || !p.equals(candidate.path, avatarFile.path))) {
        await _deleteFileQuietly(candidate);
      }
    } catch (_) {}
  }
}

Future<void> _deleteFileQuietly(File? file) async {
  if (file == null) return;
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

bool _isWithin(Directory directory, File file) {
  final root = p.normalize(directory.absolute.path);
  final candidate = p.normalize(file.absolute.path);
  return p.isWithin(root, candidate);
}

String _safeSourceBaseName(String sourceFileName) {
  final extension = p.extension(sourceFileName).toLowerCase();
  var stem = p
      .basenameWithoutExtension(sourceFileName)
      .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001F]+'), '_');
  stem = stem.replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
  if (stem.isEmpty) stem = 'character_card';
  if (stem.length > 80) stem = stem.substring(0, 80);
  return '$stem${extension == '.png' ? '.png' : '.json'}';
}

String _safePathSegment(String value) {
  final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  return safe.isEmpty ? 'item' : safe;
}

String _uniqueName(
  String requested,
  Iterable<String> existingNames,
  String copySuffix,
) {
  final base = requested.trim();
  if (base.isEmpty) {
    throw ArgumentError.value(requested, 'requested', 'Name cannot be empty');
  }
  final names = existingNames.toSet();
  if (!names.contains(base)) return base;

  final suffix = copySuffix.trim();
  var index = suffix.isEmpty ? 2 : 1;
  var candidate = suffix.isEmpty ? '$base $index' : '$base $suffix';
  while (names.contains(candidate)) {
    index++;
    candidate = suffix.isEmpty ? '$base $index' : '$base $suffix $index';
  }
  return candidate;
}
