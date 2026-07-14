import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../models/character_card.dart';

const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
const _characterCardKeywords = <String>{'chara', 'ccv3'};
const _textChunkTypes = <String>{'tEXt', 'zTXt', 'iTXt'};
const _decompressionInputChunkSize = 64 * 1024;

enum PngCharacterCardChunkType { text, compressedText, internationalText }

class PngCharacterCardPayload {
  const PngCharacterCardPayload({
    required this.keyword,
    required this.chunkType,
    required this.jsonText,
  });

  final String keyword;
  final PngCharacterCardChunkType chunkType;
  final String jsonText;
}

class PngCharacterCardReader {
  const PngCharacterCardReader({this.limits = CharacterCardLimits.defaults});

  final CharacterCardLimits limits;

  PngCharacterCardPayload read(Uint8List bytes) {
    if (bytes.length > limits.maxFileBytes) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.fileTooLarge,
        'Character card PNG exceeds ${limits.maxFileBytes} bytes.',
      );
    }
    if (!_hasPngSignature(bytes)) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidPngSignature,
        'Character card does not have a valid PNG signature.',
      );
    }

    final candidates = <String, _MetadataCandidate>{};
    var offset = _pngSignature.length;
    var chunkIndex = 0;
    var sawHeader = false;
    var sawImageData = false;
    var imageDataEnded = false;
    var sawEnd = false;

    while (offset < bytes.length) {
      if (bytes.length - offset < 12) {
        throw const CharacterCardParseException(
          CharacterCardParseErrorCode.truncatedPng,
          'Character card PNG ends inside a chunk.',
        );
      }

      final dataLength = _readUint32(bytes, offset);
      final typeStart = offset + 4;
      final dataStart = typeStart + 4;
      final remainingAfterType = bytes.length - dataStart;
      if (dataLength > remainingAfterType - 4) {
        throw const CharacterCardParseException(
          CharacterCardParseErrorCode.truncatedPng,
          'Character card PNG contains a truncated chunk.',
        );
      }

      final typeBytes = Uint8List.sublistView(bytes, typeStart, dataStart);
      final type = _decodeChunkType(typeBytes);
      if (chunkIndex == 0 && type != 'IHDR') {
        throw const CharacterCardParseException(
          CharacterCardParseErrorCode.invalidPngStructure,
          'PNG IHDR must be the first chunk.',
        );
      }
      if (_textChunkTypes.contains(type) &&
          dataLength > limits.maxMetadataChunkBytes) {
        throw CharacterCardParseException(
          CharacterCardParseErrorCode.pngMetadataTooLarge,
          'PNG metadata chunk exceeds ${limits.maxMetadataChunkBytes} bytes.',
        );
      }

      final dataEnd = dataStart + dataLength;
      final crcEnd = dataEnd + 4;
      final data = Uint8List.sublistView(bytes, dataStart, dataEnd);
      final expectedCrc = _readUint32(bytes, dataEnd);
      var actualCrc = getCrc32(typeBytes);
      actualCrc = getCrc32(data, actualCrc);
      if (actualCrc != expectedCrc) {
        throw CharacterCardParseException(
          CharacterCardParseErrorCode.invalidPngCrc,
          'PNG chunk $type has an invalid CRC.',
        );
      }

      if (sawImageData && type != 'IDAT') imageDataEnded = true;

      switch (type) {
        case 'IHDR':
          if (sawHeader || chunkIndex != 0) {
            throw const CharacterCardParseException(
              CharacterCardParseErrorCode.invalidPngStructure,
              'PNG must contain exactly one leading IHDR chunk.',
            );
          }
          _validateHeader(data);
          sawHeader = true;
          break;
        case 'IDAT':
          if (!sawHeader || imageDataEnded) {
            throw const CharacterCardParseException(
              CharacterCardParseErrorCode.invalidPngStructure,
              'PNG IDAT chunks must be consecutive and follow IHDR.',
            );
          }
          sawImageData = true;
          break;
        case 'IEND':
          if (!sawHeader || !sawImageData || data.isNotEmpty) {
            throw const CharacterCardParseException(
              CharacterCardParseErrorCode.invalidPngStructure,
              'PNG IEND must be empty and follow image data.',
            );
          }
          if (crcEnd != bytes.length) {
            throw const CharacterCardParseException(
              CharacterCardParseErrorCode.invalidPngStructure,
              'PNG contains data after IEND.',
            );
          }
          sawEnd = true;
          break;
        case 'tEXt':
        case 'zTXt':
        case 'iTXt':
          final candidate = _readMetadata(type, data);
          if (candidate != null) {
            final existing = candidates[candidate.keyword];
            if (existing != null &&
                existing.encodedJson != candidate.encodedJson) {
              throw CharacterCardParseException(
                CharacterCardParseErrorCode.conflictingPngMetadata,
                'PNG contains conflicting ${candidate.keyword} metadata.',
              );
            }
            candidates[candidate.keyword] ??= candidate;
          }
          break;
        default:
          break;
      }

      offset = crcEnd;
      chunkIndex++;
      if (sawEnd) break;
    }

    if (!sawEnd) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.truncatedPng,
        'Character card PNG is missing IEND.',
      );
    }

    final selected = candidates['ccv3'] ?? candidates['chara'];
    if (selected == null) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.missingPngMetadata,
        'PNG does not contain chara or ccv3 character card metadata.',
      );
    }

    final jsonBytes = _decodeBase64(selected.encodedJson);
    String jsonText;
    try {
      jsonText = utf8.decode(jsonBytes, allowMalformed: false);
    } on FormatException catch (error) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.invalidUtf8,
        'PNG character card metadata is not valid UTF-8: ${error.message}',
      );
    }

    return PngCharacterCardPayload(
      keyword: selected.keyword,
      chunkType: selected.chunkType,
      jsonText: jsonText,
    );
  }

  _MetadataCandidate? _readMetadata(String type, Uint8List data) {
    final keywordEnd = data.indexOf(0);
    if (keywordEnd < 1 || keywordEnd > 79) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidPngStructure,
        'PNG text metadata has an invalid keyword.',
      );
    }

    final keywordBytes = Uint8List.sublistView(data, 0, keywordEnd);
    _validateKeyword(keywordBytes);
    final keyword = latin1.decode(keywordBytes);

    return switch (type) {
      'tEXt' => _readTextMetadata(keyword, data, keywordEnd + 1),
      'zTXt' => _readCompressedTextMetadata(keyword, data, keywordEnd + 1),
      'iTXt' => _readInternationalTextMetadata(keyword, data, keywordEnd + 1),
      _ => null,
    };
  }

  _MetadataCandidate? _readTextMetadata(
    String keyword,
    Uint8List data,
    int textStart,
  ) {
    if (!_characterCardKeywords.contains(keyword)) return null;
    final text = latin1.decode(Uint8List.sublistView(data, textStart));
    return _MetadataCandidate(
      keyword: keyword,
      chunkType: PngCharacterCardChunkType.text,
      encodedJson: _normalizeEncodedJson(text),
    );
  }

  _MetadataCandidate? _readCompressedTextMetadata(
    String keyword,
    Uint8List data,
    int methodOffset,
  ) {
    if (methodOffset >= data.length || data[methodOffset] != 0) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidPngStructure,
        'PNG zTXt metadata has an invalid compression method.',
      );
    }
    if (!_characterCardKeywords.contains(keyword)) return null;

    final compressed = Uint8List.sublistView(data, methodOffset + 1);
    final textBytes = _decompressZlib(compressed);
    final text = latin1.decode(textBytes);
    return _MetadataCandidate(
      keyword: keyword,
      chunkType: PngCharacterCardChunkType.compressedText,
      encodedJson: _normalizeEncodedJson(text),
    );
  }

  _MetadataCandidate? _readInternationalTextMetadata(
    String keyword,
    Uint8List data,
    int flagOffset,
  ) {
    if (data.length - flagOffset < 4) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidPngStructure,
        'PNG iTXt metadata is incomplete.',
      );
    }

    final compressionFlag = data[flagOffset];
    final compressionMethod = data[flagOffset + 1];
    if ((compressionFlag != 0 && compressionFlag != 1) ||
        compressionMethod != 0) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidPngStructure,
        'PNG iTXt metadata has invalid compression fields.',
      );
    }

    final languageStart = flagOffset + 2;
    final languageEnd = data.indexOf(0, languageStart);
    if (languageEnd < 0) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidPngStructure,
        'PNG iTXt metadata is missing its language separator.',
      );
    }
    for (var index = languageStart; index < languageEnd; index++) {
      if (data[index] > 0x7f) {
        throw const CharacterCardParseException(
          CharacterCardParseErrorCode.invalidPngStructure,
          'PNG iTXt language tag must be ASCII.',
        );
      }
    }

    final translatedStart = languageEnd + 1;
    final translatedEnd = data.indexOf(0, translatedStart);
    if (translatedEnd < 0) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidPngStructure,
        'PNG iTXt metadata is missing its translated keyword separator.',
      );
    }
    try {
      utf8.decode(
        Uint8List.sublistView(data, translatedStart, translatedEnd),
        allowMalformed: false,
      );
    } on FormatException catch (error) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.invalidUtf8,
        'PNG iTXt translated keyword is not valid UTF-8: ${error.message}',
      );
    }

    if (!_characterCardKeywords.contains(keyword)) return null;
    final storedText = Uint8List.sublistView(data, translatedEnd + 1);
    final textBytes = compressionFlag == 1
        ? _decompressZlib(storedText)
        : storedText;
    String text;
    try {
      text = utf8.decode(textBytes, allowMalformed: false);
    } on FormatException catch (error) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.invalidUtf8,
        'PNG iTXt value is not valid UTF-8: ${error.message}',
      );
    }

    return _MetadataCandidate(
      keyword: keyword,
      chunkType: PngCharacterCardChunkType.internationalText,
      encodedJson: _normalizeEncodedJson(text),
    );
  }

  Uint8List _decompressZlib(Uint8List compressed) {
    final output = _LimitedByteSink(limits.maxBase64Bytes);
    final decoder = ZLibCodec().decoder.startChunkedConversion(output);

    try {
      for (
        var offset = 0;
        offset < compressed.length;
        offset += _decompressionInputChunkSize
      ) {
        final proposedEnd = offset + _decompressionInputChunkSize;
        final end = proposedEnd < compressed.length
            ? proposedEnd
            : compressed.length;
        decoder.add(Uint8List.sublistView(compressed, offset, end));
      }
      decoder.close();
    } on _DecompressedDataTooLarge {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.decompressedDataTooLarge,
        'Decompressed PNG metadata exceeds ${limits.maxBase64Bytes} bytes.',
      );
    } on Object catch (error) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.invalidPngStructure,
        'PNG metadata contains invalid zlib data: $error',
      );
    }

    return output.takeBytes();
  }

  Uint8List _decodeBase64(String encoded) {
    if (encoded.isEmpty ||
        encoded.length % 4 != 0 ||
        encoded.length > limits.maxBase64Bytes) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidBase64,
        'PNG character card metadata is not strict Base64.',
      );
    }

    var padding = 0;
    if (encoded.endsWith('=')) padding++;
    if (encoded.endsWith('==')) padding++;
    for (var index = 0; index < encoded.length - padding; index++) {
      if (_base64Value(encoded.codeUnitAt(index)) < 0) {
        throw const CharacterCardParseException(
          CharacterCardParseErrorCode.invalidBase64,
          'PNG character card metadata is not strict Base64.',
        );
      }
    }
    for (
      var index = encoded.length - padding;
      index < encoded.length;
      index++
    ) {
      if (encoded.codeUnitAt(index) != 0x3d) {
        throw const CharacterCardParseException(
          CharacterCardParseErrorCode.invalidBase64,
          'PNG character card metadata is not strict Base64.',
        );
      }
    }
    if (padding > 2 ||
        (padding == 2 &&
            (_base64Value(encoded.codeUnitAt(encoded.length - 3)) & 0x0f) !=
                0) ||
        (padding == 1 &&
            (_base64Value(encoded.codeUnitAt(encoded.length - 2)) & 0x03) !=
                0)) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidBase64,
        'PNG character card metadata is not canonical Base64.',
      );
    }

    final decodedLength = (encoded.length ~/ 4) * 3 - padding;
    if (decodedLength > limits.maxJsonBytes) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.jsonTooLarge,
        'Decoded character card JSON exceeds ${limits.maxJsonBytes} bytes.',
      );
    }

    try {
      return base64Decode(encoded);
    } on FormatException catch (error) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.invalidBase64,
        'PNG character card metadata is not valid Base64: ${error.message}',
      );
    }
  }
}

class _MetadataCandidate {
  const _MetadataCandidate({
    required this.keyword,
    required this.chunkType,
    required this.encodedJson,
  });

  final String keyword;
  final PngCharacterCardChunkType chunkType;
  final String encodedJson;
}

class _LimitedByteSink extends ByteConversionSinkBase {
  _LimitedByteSink(this.maxBytes);

  final int maxBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  var _length = 0;

  @override
  void add(List<int> chunk) {
    if (chunk.length > maxBytes - _length) {
      throw const _DecompressedDataTooLarge();
    }
    _builder.add(chunk);
    _length += chunk.length;
  }

  @override
  void close() {}

  Uint8List takeBytes() => _builder.takeBytes();
}

class _DecompressedDataTooLarge implements Exception {
  const _DecompressedDataTooLarge();
}

bool _hasPngSignature(Uint8List bytes) {
  if (bytes.length < _pngSignature.length) return false;
  for (var index = 0; index < _pngSignature.length; index++) {
    if (bytes[index] != _pngSignature[index]) return false;
  }
  return true;
}

int _readUint32(Uint8List bytes, int offset) {
  return ByteData.sublistView(
    bytes,
    offset,
    offset + 4,
  ).getUint32(0, Endian.big);
}

String _decodeChunkType(Uint8List bytes) {
  for (final value in bytes) {
    final isUppercase = value >= 0x41 && value <= 0x5a;
    final isLowercase = value >= 0x61 && value <= 0x7a;
    if (!isUppercase && !isLowercase) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidPngStructure,
        'PNG chunk type must contain four ASCII letters.',
      );
    }
  }
  return String.fromCharCodes(bytes);
}

void _validateHeader(Uint8List data) {
  if (data.length != 13) {
    throw const CharacterCardParseException(
      CharacterCardParseErrorCode.invalidPngStructure,
      'PNG IHDR must contain 13 bytes.',
    );
  }

  final header = ByteData.sublistView(data);
  final width = header.getUint32(0, Endian.big);
  final height = header.getUint32(4, Endian.big);
  final bitDepth = data[8];
  final colorType = data[9];
  final compressionMethod = data[10];
  final filterMethod = data[11];
  final interlaceMethod = data[12];
  final validBitDepth = switch (colorType) {
    0 => const <int>{1, 2, 4, 8, 16}.contains(bitDepth),
    2 => const <int>{8, 16}.contains(bitDepth),
    3 => const <int>{1, 2, 4, 8}.contains(bitDepth),
    4 || 6 => const <int>{8, 16}.contains(bitDepth),
    _ => false,
  };

  if (width == 0 ||
      height == 0 ||
      !validBitDepth ||
      compressionMethod != 0 ||
      filterMethod != 0 ||
      (interlaceMethod != 0 && interlaceMethod != 1)) {
    throw const CharacterCardParseException(
      CharacterCardParseErrorCode.invalidPngStructure,
      'PNG IHDR contains unsupported or invalid values.',
    );
  }
}

void _validateKeyword(Uint8List keyword) {
  var previousWasSpace = false;
  for (var index = 0; index < keyword.length; index++) {
    final value = keyword[index];
    final isAllowed = (value >= 0x20 && value <= 0x7e) || value >= 0xa1;
    final isSpace = value == 0x20;
    if (!isAllowed ||
        (isSpace && (index == 0 || index == keyword.length - 1)) ||
        (isSpace && previousWasSpace)) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidPngStructure,
        'PNG text metadata has an invalid keyword.',
      );
    }
    previousWasSpace = isSpace;
  }
}

String _normalizeEncodedJson(String value) {
  var start = 0;
  var end = value.length;
  while (start < end && _isAsciiWhitespace(value.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isAsciiWhitespace(value.codeUnitAt(end - 1))) {
    end--;
  }
  return value.substring(start, end);
}

bool _isAsciiWhitespace(int value) {
  return value == 0x20 || (value >= 0x09 && value <= 0x0d);
}

int _base64Value(int value) {
  if (value >= 0x41 && value <= 0x5a) return value - 0x41;
  if (value >= 0x61 && value <= 0x7a) return value - 0x61 + 26;
  if (value >= 0x30 && value <= 0x39) return value - 0x30 + 52;
  if (value == 0x2b) return 62;
  if (value == 0x2f) return 63;
  return -1;
}
