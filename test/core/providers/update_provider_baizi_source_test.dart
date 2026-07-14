import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:Kelivo/core/providers/update_provider.dart';

void main() {
  group('UpdateProvider Baizi release source isolation', () {
    test(
      'is explicitly disabled and performs no I/O without a source',
      () async {
        var requestCount = 0;
        var versionLoadCount = 0;
        final provider = UpdateProvider(
          client: MockClient((_) async {
            requestCount++;
            return http.Response('{}', 200);
          }),
          currentVersionLoader: () async {
            versionLoadCount++;
            return '1.0.0';
          },
        );

        expect(provider.isEnabled, isFalse);
        expect(provider.status, UpdateCheckStatus.disabled);

        await provider.checkForUpdates();

        expect(requestCount, 0);
        expect(versionLoadCount, 0);
        expect(provider.status, UpdateCheckStatus.disabled);
        expect(provider.available, isNull);
        expect(provider.error, isNull);
      },
    );

    test('checks a configured Baizi source with a Baizi cache key', () async {
      Uri? requestedUri;
      final provider = UpdateProvider(
        releaseManifestUrl: 'https://updates.baizi.example/update.json',
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response(
            jsonEncode({
              'app': 'baizi',
              'latest': {
                'version': '1.1.0',
                'downloads': {
                  'universal': 'https://downloads.baizi.example/baizi.apk',
                },
              },
            }),
            200,
          );
        }),
        currentVersionLoader: () async => '1.0.0',
      );

      await provider.checkForUpdates();

      expect(provider.isEnabled, isTrue);
      expect(provider.status, UpdateCheckStatus.updateAvailable);
      expect(provider.available?.version, '1.1.0');
      expect(requestedUri?.queryParameters.containsKey('baizi'), isTrue);
      expect(requestedUri?.queryParameters.containsKey('kelivo'), isFalse);
    });

    test(
      'reports up to date when the configured source is not newer',
      () async {
        final provider = UpdateProvider(
          releaseManifestUrl: 'https://updates.baizi.example/update.json',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'app': 'baizi',
                'latest': {
                  'version': '1.0.0',
                  'downloads': {
                    'universal': 'https://downloads.baizi.example/baizi.apk',
                  },
                },
              }),
              200,
            ),
          ),
          currentVersionLoader: () async => '1.0.0',
        );

        await provider.checkForUpdates();

        expect(provider.status, UpdateCheckStatus.upToDate);
        expect(provider.available, isNull);
        expect(provider.error, isNull);
      },
    );

    test('rejects a Kelivo manifest identity', () async {
      final provider = UpdateProvider(
        releaseManifestUrl: 'https://updates.baizi.example/update.json',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'app': 'Kelivo',
              'latest': {
                'version': '99.0.0',
                'downloads': {
                  'universal': 'https://downloads.baizi.example/baizi.apk',
                },
              },
            }),
            200,
          ),
        ),
        currentVersionLoader: () async => '1.0.0',
      );

      await provider.checkForUpdates();

      expect(provider.status, UpdateCheckStatus.failed);
      expect(provider.available, isNull);
      expect(provider.error, contains('manifest app'));
    });

    test('rejects the Kelivo release source before making a request', () async {
      var requestCount = 0;
      final provider = UpdateProvider(
        releaseManifestUrl: 'https://kelivo.psycheas.top/update.json',
        client: MockClient((_) async {
          requestCount++;
          return http.Response('{}', 200);
        }),
        currentVersionLoader: () async => '1.0.0',
      );

      await provider.checkForUpdates();

      expect(requestCount, 0);
      expect(provider.status, UpdateCheckStatus.failed);
      expect(provider.available, isNull);
      expect(provider.error, contains('Kelivo release manifest'));
    });

    test('rejects every manifest containing a Kelivo download URL', () async {
      final provider = UpdateProvider(
        releaseManifestUrl: 'https://updates.baizi.example/update.json',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'app': 'baizi',
              'latest': {
                'version': '99.0.0',
                'downloads': {
                  'universal':
                      'https://github.com/Chevey339/kelivo/releases/download/v99/kelivo.apk',
                },
              },
            }),
            200,
          ),
        ),
        currentVersionLoader: () async => '1.0.0',
      );

      await provider.checkForUpdates();

      expect(provider.status, UpdateCheckStatus.failed);
      expect(provider.available, isNull);
      expect(provider.error, contains('Kelivo download'));
    });
  });
}
