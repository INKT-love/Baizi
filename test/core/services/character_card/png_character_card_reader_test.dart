import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/character_card.dart';
import 'package:Kelivo/core/services/character_card/character_card_parser.dart';
import 'package:Kelivo/core/services/character_card/png_character_card_reader.dart';

const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

Map<String, dynamic> _v1Card(String name) => {
  'name': name,
  'description': '',
  'personality': '',
  'scenario': '',
  'first_mes': 'Hello',
  'mes_example': '',
};

Map<String, dynamic> _v3Card(String name) => {
  'spec': 'chara_card_v3',
  'spec_version': '3.0',
  'data': {
    'name': name,
    'description': '',
    'personality': '',
    'scenario': '',
    'first_mes': 'Hello',
    'mes_example': '',
    'creator_notes': '',
    'system_prompt': '',
    'post_history_instructions': '',
    'alternate_greetings': [],
    'tags': [],
    'creator': '',
    'character_version': '',
    'extensions': {},
    'group_only_greetings': [],
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
  return Uint8List.fromList([
    ..._uint32(data.length),
    ...typeBytes,
    ...data,
    ..._uint32(crc),
  ]);
}

Uint8List _ihdr() {
  final data = ByteData(13)
    ..setUint32(0, 1, Endian.big)
    ..setUint32(4, 1, Endian.big)
    ..setUint8(8, 8)
    ..setUint8(9, 6)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  return _chunk('IHDR', data.buffer.asUint8List());
}

Uint8List _png(List<Uint8List> metadataChunks) {
  final idat = ZLibCodec().encode(const [0, 0, 0, 0, 0]);
  return Uint8List.fromList([
    ..._pngSignature,
    ..._ihdr(),
    for (final chunk in metadataChunks) ...chunk,
    ..._chunk('IDAT', idat),
    ..._chunk('IEND', const []),
  ]);
}

String _encodedCard(Map<String, dynamic> card) =>
    base64Encode(utf8.encode(jsonEncode(card)));

Uint8List _textChunk(String keyword, String encoded) =>
    _chunk('tEXt', [...latin1.encode(keyword), 0, ...latin1.encode(encoded)]);

Uint8List _zTextChunk(String keyword, String encoded) => _chunk('zTXt', [
  ...latin1.encode(keyword),
  0,
  0,
  ...ZLibCodec().encode(latin1.encode(encoded)),
]);

Uint8List _iTextChunk(
  String keyword,
  String encoded, {
  required bool compressed,
}) {
  final text = utf8.encode(encoded);
  return _chunk('iTXt', [
    ...latin1.encode(keyword),
    0,
    compressed ? 1 : 0,
    0,
    ...ascii.encode('en'),
    0,
    ...utf8.encode('Character card'),
    0,
    ...(compressed ? ZLibCodec().encode(text) : text),
  ]);
}

void main() {
  group('PngCharacterCardReader', () {
    test('reads a V1 chara tEXt chunk', () {
      final png = _png([_textChunk('chara', _encodedCard(_v1Card('V1')))]);
      final payload = const PngCharacterCardReader().read(png);

      expect(payload.keyword, 'chara');
      expect(payload.chunkType, PngCharacterCardChunkType.text);
      expect(jsonDecode(payload.jsonText)['name'], 'V1');
      expect(const CharacterCardParser().parsePngBytes(png).data.name, 'V1');
    });

    test('prefers ccv3 over chara regardless of chunk order', () {
      final ccv3 = _textChunk('ccv3', _encodedCard(_v3Card('V3')));
      final chara = _textChunk('chara', _encodedCard(_v1Card('V1 fallback')));

      for (final chunks in <List<Uint8List>>[
        [ccv3, chara],
        [chara, ccv3],
      ]) {
        final png = _png(chunks);
        final payload = const PngCharacterCardReader().read(png);
        expect(payload.keyword, 'ccv3');
        expect(const CharacterCardParser().parsePngBytes(png).data.name, 'V3');
      }
    });

    test('rejects a non-V3 ccv3 payload instead of falling back to chara', () {
      final png = _png([
        _textChunk('ccv3', _encodedCard(_v1Card('Invalid ccv3'))),
        _textChunk('chara', _encodedCard(_v1Card('Valid fallback'))),
      ]);

      expect(
        () => const CharacterCardParser().parsePngBytes(png),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.invalidCard,
          ),
        ),
      );
    });

    test('reads zTXt and compressed or plain iTXt chunks', () {
      final cases = <(Uint8List, PngCharacterCardChunkType)>[
        (
          _zTextChunk('chara', _encodedCard(_v1Card('zTXt'))),
          PngCharacterCardChunkType.compressedText,
        ),
        (
          _iTextChunk(
            'chara',
            _encodedCard(_v1Card('plain iTXt')),
            compressed: false,
          ),
          PngCharacterCardChunkType.internationalText,
        ),
        (
          _iTextChunk(
            'chara',
            _encodedCard(_v1Card('compressed iTXt')),
            compressed: true,
          ),
          PngCharacterCardChunkType.internationalText,
        ),
      ];

      for (final (chunk, expectedType) in cases) {
        final payload = const PngCharacterCardReader().read(_png([chunk]));
        expect(payload.chunkType, expectedType);
        expect(jsonDecode(payload.jsonText)['name'], isNotEmpty);
      }
    });

    test('accepts duplicate metadata only when normalized values match', () {
      final encoded = _encodedCard(_v1Card('Same'));
      final matching = _png([
        _textChunk('chara', encoded),
        _textChunk('chara', '  $encoded\n'),
      ]);
      final conflicting = _png([
        _textChunk('chara', encoded),
        _textChunk('chara', _encodedCard(_v1Card('Different'))),
      ]);

      expect(const PngCharacterCardReader().read(matching).keyword, 'chara');
      expect(
        () => const PngCharacterCardReader().read(conflicting),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.conflictingPngMetadata,
          ),
        ),
      );
    });

    test('rejects an invalid PNG signature', () {
      expect(
        () => const PngCharacterCardReader().read(Uint8List.fromList([1, 2])),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.invalidPngSignature,
          ),
        ),
      );
    });

    test('rejects truncated chunks', () {
      final png = _png([_textChunk('chara', _encodedCard(_v1Card('V1')))]);
      final truncated = Uint8List.sublistView(png, 0, png.length - 3);

      expect(
        () => const PngCharacterCardReader().read(truncated),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.truncatedPng,
          ),
        ),
      );
    });

    test('rejects a CRC mismatch', () {
      final png = _png([_textChunk('chara', _encodedCard(_v1Card('V1')))]);
      final corrupted = Uint8List.fromList(png);
      final metadataDataStart = 8 + _ihdr().length + 8;
      corrupted[metadataDataStart + 7] ^= 1;

      expect(
        () => const PngCharacterCardReader().read(corrupted),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.invalidPngCrc,
          ),
        ),
      );
    });

    test('rejects missing character metadata', () {
      expect(
        () => const PngCharacterCardReader().read(_png(const [])),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.missingPngMetadata,
          ),
        ),
      );
    });

    test('rejects invalid Base64 and decoded invalid UTF-8', () {
      final invalidBase64 = _png([_textChunk('chara', '%%%')]);
      final invalidUtf8 = _png([
        _textChunk('chara', base64Encode(const [0xff, 0xfe])),
      ]);

      expect(
        () => const PngCharacterCardReader().read(invalidBase64),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.invalidBase64,
          ),
        ),
      );
      expect(
        () => const PngCharacterCardReader().read(invalidUtf8),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.invalidUtf8,
          ),
        ),
      );
    });

    test('rejects non-standard and non-canonical Base64', () {
      final invalidValues = <String>['-_==', 'AA=', 'A A=', 'AB=='];

      for (final value in invalidValues) {
        expect(
          () => const PngCharacterCardReader().read(
            _png([_textChunk('chara', value)]),
          ),
          throwsA(
            isA<CharacterCardParseException>().having(
              (error) => error.code,
              'code',
              CharacterCardParseErrorCode.invalidBase64,
            ),
          ),
        );
      }
    });

    test('rejects malformed compressed metadata', () {
      final invalidZlib = _chunk('zTXt', [
        ...latin1.encode('chara'),
        0,
        0,
        1,
        2,
        3,
      ]);

      expect(
        () => const PngCharacterCardReader().read(_png([invalidZlib])),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.invalidPngStructure,
          ),
        ),
      );
    });

    test('enforces file and metadata chunk size limits', () {
      final fileLimited = PngCharacterCardReader(
        limits: CharacterCardLimits.defaults.copyWith(maxFileBytes: 20),
      );
      final metadataLimited = PngCharacterCardReader(
        limits: CharacterCardLimits.defaults.copyWith(
          maxMetadataChunkBytes: 16,
        ),
      );
      final png = _png([_textChunk('chara', _encodedCard(_v1Card('V1')))]);

      expect(
        () => fileLimited.read(png),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.fileTooLarge,
          ),
        ),
      );
      expect(
        () => metadataLimited.read(png),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.pngMetadataTooLarge,
          ),
        ),
      );
    });

    test('bounds decompressed zTXt output before Base64 decoding', () {
      final reader = PngCharacterCardReader(
        limits: CharacterCardLimits.defaults.copyWith(maxJsonBytes: 24),
      );
      final oversizedEncodedText = 'A' * 256;
      final png = _png([_zTextChunk('chara', oversizedEncodedText)]);

      expect(
        () => reader.read(png),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.decompressedDataTooLarge,
          ),
        ),
      );
    });

    test('bounds decompressed iTXt output before Base64 decoding', () {
      final reader = PngCharacterCardReader(
        limits: CharacterCardLimits.defaults.copyWith(maxJsonBytes: 24),
      );
      final png = _png([_iTextChunk('chara', 'A' * 256, compressed: true)]);

      expect(
        () => reader.read(png),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.decompressedDataTooLarge,
          ),
        ),
      );
    });
  });
}
