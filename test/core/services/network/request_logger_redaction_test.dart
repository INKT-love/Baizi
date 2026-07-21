import 'package:flutter_test/flutter_test.dart';

import 'package:Baizi/core/services/network/request_logger.dart';

void main() {
  group('RequestLogger redaction', () {
    test('redacts sensitive headers recursively', () {
      final encoded = RequestLogger.encodeObject(<String, Object?>{
        'Authorization': 'Bearer secret-one',
        'x-api-key': 'secret-two',
        'nested': <String, String>{
          'api_key': 'secret-three',
          'safe': 'visible',
        },
      });

      expect(encoded, isNot(contains('secret-one')));
      expect(encoded, isNot(contains('secret-two')));
      expect(encoded, isNot(contains('secret-three')));
      expect(encoded, contains(RequestLogger.redactedValue));
      expect(encoded, contains('visible'));
    });

    test('redacts JSON body credentials and bearer text', () {
      final body = RequestLogger.redactBody(
        '{"apiKey":"body-secret","prompt":"Bearer inline-secret"}',
      );

      expect(body, isNot(contains('body-secret')));
      expect(body, isNot(contains('inline-secret')));
      expect(body, contains(RequestLogger.redactedValue));
    });

    test('redacts credentials embedded in SSE and exception text', () {
      final text = RequestLogger.redactText(
        'data: {"x-api-key":"response-secret",'
        '"password":"password-secret"}\n'
        'DioException: Authorization=Bearer exception-secret',
      );

      expect(text, isNot(contains('response-secret')));
      expect(text, isNot(contains('password-secret')));
      expect(text, isNot(contains('exception-secret')));
      expect(text, contains(RequestLogger.redactedValue));
    });

    test('redacts token secret key and credential field variants', () {
      final encoded = RequestLogger.encodeObject(<String, Object?>{
        'token': 'token-secret',
        'SECRET': 'generic-secret',
        'privateKey': 'private-secret',
        'private-key': 'hyphen-private-secret',
        'credential': 'credential-secret',
        'clientKey': 'client-secret',
        'client_key': 'underscore-client-secret',
        'AWS_SECRET_ACCESS_KEY': 'aws-secret-access-key',
        'nested': <String, Object?>{
          'session-token': 'session-secret',
          'apiToken': 'api-token-secret',
        },
      });

      for (final secret in <String>[
        'token-secret',
        'generic-secret',
        'private-secret',
        'hyphen-private-secret',
        'credential-secret',
        'client-secret',
        'underscore-client-secret',
        'aws-secret-access-key',
        'session-secret',
        'api-token-secret',
      ]) {
        expect(encoded, isNot(contains(secret)), reason: secret);
      }
      expect(encoded, contains(RequestLogger.redactedValue));
    });

    test('redacts credential variants in JSON SSE URLs and exceptions', () {
      final text = RequestLogger.redactText(
        'data: {"ToKeN":"sse-token","private-key":"sse-private"}\n'
        'DioException: client_key=exception-client-secret '
        'credential: exception-credential-secret '
        'https://example.invalid?secret=query-secret&safe=visible',
      );

      for (final secret in <String>[
        'sse-token',
        'sse-private',
        'exception-client-secret',
        'exception-credential-secret',
        'query-secret',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      expect(text, contains('safe=visible'));
    });

    test('does not redact ordinary words that merely share prefixes', () {
      const ordinary =
          'tokenization secretary credentialed clientKeyboard '
          '{"tokenLimit":4096,"secretary":"Alice",'
          '"credentialLabel":"work","clientKeyboard":"ansi"}';

      expect(RequestLogger.redactText(ordinary), ordinary);
      expect(RequestLogger.redactBody(ordinary), ordinary);
    });

    test('redacts credentials carried in URLs and unquoted maps', () {
      final text = RequestLogger.redactText(
        'https://example.invalid?api_key=query-secret '
        '{client_secret: map-secret, cookie: session-secret}',
      );

      expect(text, isNot(contains('query-secret')));
      expect(text, isNot(contains('map-secret')));
      expect(text, isNot(contains('session-secret')));
      expect(text, contains(RequestLogger.redactedValue));
    });

    test('redacts dotted credential key variants', () {
      final encoded = RequestLogger.encodeObject(<String, Object?>{
        'X.Api.Key': 'dotted-api-secret',
        'private.key': 'dotted-private-secret',
      });
      final text = RequestLogger.redactText(
        'client.key=dotted-client-secret X.Api.Key: dotted-text-secret',
      );

      for (final secret in <String>[
        'dotted-api-secret',
        'dotted-private-secret',
        'dotted-client-secret',
        'dotted-text-secret',
      ]) {
        expect(encoded + text, isNot(contains(secret)), reason: secret);
      }
      expect(encoded + text, contains(RequestLogger.redactedValue));
    });

    test('buffers split SSE credentials until a complete event', () {
      final buffer = RedactingResponseLogBuffer(eventStream: true);

      expect(buffer.add('data: {"apiKey":"split-res'), isEmpty);
      final output = buffer.add('ponse-secret"}\n\n');

      expect(output, hasLength(1));
      expect(output.single, isNot(contains('split-response-secret')));
      expect(output.single, contains(RequestLogger.redactedValue));
      expect(buffer.close(), isEmpty);
    });

    test('buffers split SSE token variants before redaction', () {
      final buffer = RedactingResponseLogBuffer(eventStream: true);

      expect(buffer.add('data: {"private-key":"split-pri'), isEmpty);
      final output = buffer.add('vate","token":"split-token"}\n\n');

      expect(output, hasLength(1));
      expect(output.single, isNot(contains('split-private')));
      expect(output.single, isNot(contains('split-token')));
      expect(output.single, contains(RequestLogger.redactedValue));
    });

    test('buffers a regular response and suppresses oversized bodies', () {
      final regular = RedactingResponseLogBuffer(eventStream: false);
      expect(regular.add('{"password":\n"regular-secret"}'), isEmpty);
      expect(regular.close().single, isNot(contains('regular-secret')));

      final oversized = RedactingResponseLogBuffer(
        eventStream: false,
        maxPendingCharacters: 4,
      );
      final output = oversized.add('sensitive payload');
      expect(output.single, contains('omitted'));
      expect(output.single, isNot(contains('sensitive payload')));
      expect(oversized.close(), isEmpty);
    });

    test('keeps ordinary request data readable', () {
      final encoded = RequestLogger.encodeObject(<String, Object?>{
        'model': 'gpt-5',
        'stream': true,
      });

      expect(encoded, contains('gpt-5'));
      expect(encoded, contains('true'));
    });
  });
}
