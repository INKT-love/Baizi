import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:Kelivo/core/config/baizi_brand.dart';
import 'package:Kelivo/core/providers/update_provider.dart';

void main() {
  group('UpdateProvider Baizi release source isolation', () {
    test(
      'is explicitly disabled and performs no I/O without a source',
      () async {
        var requestCount = 0;
        var versionLoadCount = 0;
        final provider = UpdateProvider(
          releaseManifestUrl: null,
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

    test(
      'reads the official GitHub release redirect and opens its release page',
      () async {
        Uri? requestedUri;
        final provider = UpdateProvider(
          releaseManifestUrl: BaiziBrand.githubLatestReleaseUrl,
          client: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(
              '',
              302,
              headers: {
                'location':
                    'https://github.com/INKT-love/Baizi/releases/tag/v1.2.0',
              },
            );
          }),
          currentVersionLoader: () async => '1.1.24',
        );

        await provider.checkForUpdates();

        expect(requestedUri?.host, 'github.com');
        expect(requestedUri?.path, '/INKT-love/Baizi/releases/latest');
        expect(provider.status, UpdateCheckStatus.updateAvailable);
        expect(provider.available?.version, 'v1.2.0');
        expect(
          provider.available?.bestDownloadUrl(),
          'https://github.com/INKT-love/Baizi/releases/tag/v1.2.0',
        );
      },
    );

    test('checks the OpenList mirror manifest before GitHub', () async {
      final requested = <String>[];
      final provider = UpdateProvider(
        client: MockClient((request) async {
          requested.add('${request.method} ${request.url}');
          if (request.method == 'POST' &&
              request.url.toString() ==
                  'https://list.inktandwkx.top:50000/api/fs/get') {
            expect(
              jsonDecode(request.body) as Map<String, dynamic>,
              containsPair('path', '/Baizi/manifest.json'),
            );
            return http.Response(
              jsonEncode({
                'code': 200,
                'message': 'success',
                'data': {
                  'raw_url':
                      'https://list.inktandwkx.top/d/Baizi/manifest.json?sign=abc',
                },
              }),
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/d/Baizi/manifest.json') {
            expect(request.url.port, 50000);
            return http.Response(
              jsonEncode({
                'app': 'baizi',
                'latest': {
                  'version': '1.2.0',
                  'downloads': {
                    'android':
                        'https://list.inktandwkx.top/p/server/files/Baizi/Baizi-v1.2.0.apk?sign=abc=:0',
                    'androidArm64': 'Baizi-v1.2.0-arm64-v8a.apk',
                    'universal':
                        'https://list.inktandwkx.top:50000/server/files/Baizi',
                  },
                },
              }),
              200,
            );
          }
          fail('Unexpected request: ${request.method} ${request.url}');
        }),
        currentVersionLoader: () async => '1.1.24',
      );

      await provider.checkForUpdates();

      expect(provider.status, UpdateCheckStatus.updateAvailable);
      expect(provider.available?.version, '1.2.0');
      expect(
        provider.available?.downloads['android'],
        'https://list.inktandwkx.top:50000/p/server/files/Baizi/Baizi-v1.2.0.apk?sign=abc=:0',
      );
      expect(
        provider.available?.downloads['androidArm64'],
        'https://list.inktandwkx.top:50000/d/Baizi/Baizi-v1.2.0-arm64-v8a.apk',
      );
      expect(requested, hasLength(2));
      expect(requested.first, startsWith('POST https://list.inktandwkx.top'));
    });

    test(
      'falls back to GitHub when the OpenList manifest is unavailable',
      () async {
        final requested = <Uri>[];
        final provider = UpdateProvider(
          client: MockClient((request) async {
            requested.add(request.url);
            if (request.url.host == 'list.inktandwkx.top') {
              return http.Response(
                jsonEncode({
                  'code': 500,
                  'message': 'failed to get obj: object not found',
                  'data': null,
                }),
                200,
              );
            }
            if (request.url.host == 'github.com') {
              return http.Response(
                '',
                302,
                headers: {
                  'location':
                      'https://github.com/INKT-love/Baizi/releases/tag/v1.2.0',
                },
              );
            }
            fail('Unexpected request: ${request.url}');
          }),
          currentVersionLoader: () async => '1.1.24',
        );

        await provider.checkForUpdates();

        expect(requested.map((uri) => uri.host), [
          'list.inktandwkx.top',
          'github.com',
        ]);
        expect(provider.status, UpdateCheckStatus.updateAvailable);
        expect(
          provider.available?.bestDownloadUrl(),
          'https://github.com/INKT-love/Baizi/releases/tag/v1.2.0',
        );
      },
    );

    test(
      'accepts a leading v when comparing GitHub release versions',
      () async {
        final provider = UpdateProvider(
          releaseManifestUrl: BaiziBrand.githubLatestReleaseUrl,
          client: MockClient(
            (_) async => http.Response(
              '',
              302,
              headers: {
                'location':
                    'https://github.com/INKT-love/Baizi/releases/tag/v1.1.24',
              },
            ),
          ),
          currentVersionLoader: () async => '1.1.24',
        );

        await provider.checkForUpdates();

        expect(provider.status, UpdateCheckStatus.upToDate);
        expect(provider.available, isNull);
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
