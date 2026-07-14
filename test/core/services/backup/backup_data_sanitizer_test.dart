import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/backup/backup_data_sanitizer.dart';

void main() {
  group('BackupDataSanitizer assistants_v1', () {
    test('removes protected custom request data from legacy assistants', () {
      final sanitized =
          BackupDataSanitizer.sanitizePreferenceValue(
                'assistants_v1',
                jsonEncode(<Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'legacy-assistant',
                    'chatModelProvider': 'openai',
                    'apiKey': 'top-level-secret',
                    'nested': <String, Object?>{
                      'Authorization': 'nested-authorization-secret',
                      'safe': 'nested-safe',
                    },
                    'customHeaders': <Map<String, String>>[
                      <String, String>{
                        'name': 'Authorization',
                        'value': 'Bearer unsafe',
                      },
                      <String, String>{'name': 'X-Api-Key', 'value': 'unsafe'},
                      <String, String>{
                        'name': 'X-Access-Token',
                        'value': 'unsafe-token',
                      },
                      <String, String>{
                        'name': 'X-Custom-Authorization',
                        'value': 'nested-header-secret',
                      },
                      <String, String>{
                        'name': 'X-Trace-Id',
                        'value': 'trace-1',
                      },
                    ],
                    'customBody': <Map<String, String>>[
                      <String, String>{'key': 'model', 'value': 'unsafe-model'},
                      <String, String>{'key': 'apiKey', 'value': 'sk-unsafe'},
                      <String, String>{
                        'key': 'password',
                        'value': 'unsafe-password',
                      },
                      <String, String>{'key': 'max_tokens', 'value': '4096'},
                      <String, String>{
                        'key': 'metadata',
                        'value':
                            '{"request_id":"request-1","apiKey":"nested-body-secret"}',
                      },
                    ],
                  },
                ]),
              )
              as String;

      final assistants = jsonDecode(sanitized) as List<dynamic>;
      final assistant = assistants.single as Map<String, dynamic>;
      expect(assistant['chatModelProvider'], 'baizi');
      expect(assistant['customHeaders'], <dynamic>[
        <String, dynamic>{'name': 'X-Trace-Id', 'value': 'trace-1'},
      ]);
      expect(assistant['customBody'], <dynamic>[
        <String, dynamic>{'key': 'max_tokens', 'value': '4096'},
        <String, dynamic>{
          'key': 'metadata',
          'value': '{"request_id":"request-1"}',
        },
      ]);
      expect(assistant, isNot(contains('apiKey')));
      expect((assistant['nested'] as Map)['safe'], 'nested-safe');
      expect(assistant['nested'], isNot(contains('Authorization')));
      expect(sanitized, isNot(contains('unsafe')));
      expect(sanitized, isNot(contains('top-level-secret')));
      expect(sanitized, isNot(contains('nested-authorization-secret')));
      expect(sanitized, isNot(contains('nested-header-secret')));
      expect(sanitized, isNot(contains('nested-body-secret')));
    });

    test(
      'drops blank custom keys because their values cannot be classified',
      () {
        final sanitized =
            BackupDataSanitizer.sanitizePreferenceValue(
                  'assistants_v1',
                  jsonEncode(<Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': 'legacy-assistant',
                      'customHeaders': <Map<String, String>>[
                        <String, String>{
                          'name': ' ',
                          'value': 'possibly-secret',
                        },
                      ],
                      'customBody': <Map<String, String>>[
                        <String, String>{'key': '', 'value': 'possibly-secret'},
                      ],
                    },
                  ]),
                )
                as String;

        final assistant =
            (jsonDecode(sanitized) as List<dynamic>).single
                as Map<String, dynamic>;
        expect(assistant['customHeaders'], isEmpty);
        expect(assistant['customBody'], isEmpty);
        expect(sanitized, isNot(contains('possibly-secret')));
      },
    );

    test('fails closed when legacy assistant JSON is malformed', () {
      final sanitized = BackupDataSanitizer.sanitizePreferenceValue(
        'assistants_v1',
        '{"Authorization":"Bearer malformed-secret"',
      );

      expect(sanitized, '[]');
      expect(sanitized, isNot(contains('malformed-secret')));
    });
  });

  group('BackupDataSanitizer credential-bearing settings', () {
    test('removes nested credentials while preserving ordinary settings', () {
      final cases = <String, Object>{
        'search_services_v1': <Map<String, Object?>>[
          <String, Object?>{
            'type': 'tavily',
            'id': 'search-1',
            'apiKey': 'search-secret',
            'url': 'https://search.example',
            'limits': <String, Object?>{
              'tokenLimit': 4096,
              'private-key': 'nested-search-secret',
            },
          },
        ],
        'tts_services_v1': <Map<String, Object?>>[
          <String, Object?>{
            'kind': 'openai',
            'id': 'tts-1',
            'name': 'Narrator',
            'api_key': 'tts-secret',
            'clientKey': 'tts-client-secret',
            'voice': 'alloy',
          },
        ],
        'mcp_servers_v1': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'mcp-1',
            'name': 'Local tools',
            'transport': 'sse',
            'url': 'https://mcp.example/sse',
            'headers': <String, String>{
              'Authorization': 'Bearer mcp-secret',
              'X-API-Key': 'mcp-api-secret',
              'X-Client-Key': 'mcp-client-secret',
              'X-Trace-Id': 'trace-1',
              'Client-Keyboard': 'compact',
            },
            'env': <String, String>{
              'PATH': '/usr/bin',
              'NODE_ENV': 'production',
              'API_TOKEN': 'mcp-token-secret',
              'CLIENT_SECRET': 'mcp-env-secret',
              'PRIVATE_KEY': 'mcp-private-secret',
              'AWS_ACCESS_KEY_ID': 'mcp-aws-access-secret',
              'AWS_SECRET_ACCESS_KEY': 'mcp-aws-secret',
              'SECRETARY': 'Alice',
              'CLIENT_KEYBOARD': 'ansi',
            },
            'metadata': <String, Object?>{
              'credential': 'nested-mcp-secret',
              'retryCount': 3,
            },
          },
        ],
        'webdav_config_v1': <String, Object?>{
          'url': 'https://dav.example',
          'username': 'user',
          'password': 'dav-secret',
          'path': 'backups',
        },
        's3_config_v1': <String, Object?>{
          'endpoint': 'https://s3.example',
          'region': 'auto',
          'bucket': 'backups',
          'accessKeyId': 's3-access-secret',
          'secretAccessKey': 's3-secret',
          'session-token': 's3-session-secret',
          'prefix': 'baizi',
        },
      };

      final sanitized = <String, dynamic>{
        for (final entry in cases.entries)
          entry.key: jsonDecode(
            BackupDataSanitizer.sanitizePreferenceValue(
                  entry.key,
                  jsonEncode(entry.value),
                )
                as String,
          ),
      };
      final encoded = jsonEncode(sanitized);

      for (final secret in <String>[
        'search-secret',
        'nested-search-secret',
        'tts-secret',
        'tts-client-secret',
        'mcp-secret',
        'mcp-api-secret',
        'mcp-client-secret',
        'mcp-token-secret',
        'mcp-env-secret',
        'mcp-private-secret',
        'mcp-aws-access-secret',
        'mcp-aws-secret',
        'nested-mcp-secret',
        'dav-secret',
        's3-access-secret',
        's3-secret',
        's3-session-secret',
      ]) {
        expect(encoded, isNot(contains(secret)), reason: secret);
      }

      final search = (sanitized['search_services_v1'] as List).single as Map;
      expect(search['url'], 'https://search.example');
      expect((search['limits'] as Map)['tokenLimit'], 4096);

      final tts = (sanitized['tts_services_v1'] as List).single as Map;
      expect(tts['name'], 'Narrator');
      expect(tts['voice'], 'alloy');

      final mcp = (sanitized['mcp_servers_v1'] as List).single as Map;
      expect(mcp, isNot(contains('headers')));
      expect(mcp, isNot(contains('env')));
      expect((mcp['metadata'] as Map)['retryCount'], 3);

      expect((sanitized['webdav_config_v1'] as Map)['path'], 'backups');
      expect((sanitized['s3_config_v1'] as Map)['bucket'], 'backups');
      expect((sanitized['s3_config_v1'] as Map)['prefix'], 'baizi');
    });

    test('fails closed for malformed or wrong-shaped settings JSON', () {
      for (final key in <String>[
        'search_services_v1',
        'tts_services_v1',
        'mcp_servers_v1',
      ]) {
        expect(
          BackupDataSanitizer.sanitizePreferenceValue(key, '{broken'),
          '[]',
        );
        expect(BackupDataSanitizer.sanitizePreferenceValue(key, '{}'), '[]');
      }

      for (final key in <String>['webdav_config_v1', 's3_config_v1']) {
        expect(
          BackupDataSanitizer.sanitizePreferenceValue(key, '{broken'),
          '{}',
        );
        expect(BackupDataSanitizer.sanitizePreferenceValue(key, '[]'), '{}');
      }
    });

    test(
      'restore keeps local credentials only for matching service targets',
      () {
        final search =
            jsonDecode(
                  BackupDataSanitizer.mergePreferenceForRestore(
                        'search_services_v1',
                        jsonEncode(<Map<String, Object?>>[
                          <String, Object?>{
                            'id': 'search-shared',
                            'type': 'tavily',
                            'url': 'https://search.example',
                            'apiKey': '',
                            'label': 'Imported search',
                          },
                          <String, Object?>{
                            'id': 'search-moved',
                            'type': 'tavily',
                            'url': 'https://new-search.example',
                            'apiKey': '<redacted>',
                          },
                          <String, Object?>{
                            'id': 'search-new',
                            'type': 'exa',
                            'url': 'https://new.example',
                          },
                        ]),
                        jsonEncode(<Map<String, Object?>>[
                          <String, Object?>{
                            'id': 'search-shared',
                            'type': 'tavily',
                            'url': 'https://search.example',
                            'apiKey': 'local-search-secret',
                            'label': 'Local search',
                          },
                          <String, Object?>{
                            'id': 'search-moved',
                            'type': 'tavily',
                            'url': 'https://old-search.example',
                            'apiKey': 'must-not-forward-search',
                          },
                        ]),
                      )
                      as String,
                )
                as List<dynamic>;
        final searchById = <String, Map<String, dynamic>>{
          for (final item in search.cast<Map>())
            item['id'] as String: item.cast<String, dynamic>(),
        };
        expect(searchById['search-shared']!['apiKey'], 'local-search-secret');
        expect(searchById['search-shared']!['label'], 'Imported search');
        expect(searchById['search-moved']!['apiKey'], '');
        expect(searchById['search-new']!['apiKey'], '');

        final tts =
            jsonDecode(
                  BackupDataSanitizer.mergePreferenceForRestore(
                        'tts_services_v1',
                        jsonEncode(<Map<String, Object?>>[
                          <String, Object?>{
                            'id': 'tts-shared',
                            'kind': 'openai',
                            'baseUrl': 'https://tts.example/v1',
                            'voice': 'nova',
                            'apiKey': '',
                          },
                          <String, Object?>{
                            'id': 'tts-moved',
                            'kind': 'openai',
                            'baseUrl': 'https://new-tts.example/v1',
                            'apiKey': '',
                          },
                          <String, Object?>{
                            'id': 'tts-new',
                            'kind': 'gemini',
                            'baseUrl': 'https://new-gemini.example',
                          },
                        ]),
                        jsonEncode(<Map<String, Object?>>[
                          <String, Object?>{
                            'id': 'tts-shared',
                            'kind': 'openai',
                            'baseUrl': 'https://tts.example/v1',
                            'apiKey': 'local-tts-secret',
                            'voice': 'alloy',
                          },
                          <String, Object?>{
                            'id': 'tts-moved',
                            'kind': 'openai',
                            'baseUrl': 'https://old-tts.example/v1',
                            'apiKey': 'must-not-forward-tts',
                          },
                        ]),
                      )
                      as String,
                )
                as List<dynamic>;
        final ttsById = <String, Map<String, dynamic>>{
          for (final item in tts.cast<Map>())
            item['id'] as String: item.cast<String, dynamic>(),
        };
        expect(ttsById['tts-shared']!['apiKey'], 'local-tts-secret');
        expect(ttsById['tts-shared']!['voice'], 'nova');
        expect(ttsById['tts-moved'], isNot(contains('apiKey')));
        expect(ttsById['tts-new'], isNot(contains('apiKey')));

        final mcp =
            jsonDecode(
                  BackupDataSanitizer.mergePreferenceForRestore(
                        'mcp_servers_v1',
                        jsonEncode(<Map<String, Object?>>[
                          <String, Object?>{
                            'id': 'mcp-shared',
                            'transport': 'http',
                            'url': 'https://mcp.example',
                            'name': 'Imported MCP',
                            'headers': <String, String>{
                              'Authorization': '',
                              'X-Trace-Id': 'imported-trace',
                            },
                          },
                          <String, Object?>{
                            'id': 'mcp-moved',
                            'transport': 'http',
                            'url': 'https://new-mcp.example',
                          },
                          <String, Object?>{
                            'id': 'mcp-new',
                            'transport': 'stdio',
                            'command': 'new-tool',
                            'args': <String>['serve'],
                            'env': <String, String>{'API_TOKEN': '<redacted>'},
                          },
                          <String, Object?>{
                            'id': 'mcp-stdio-path-changed',
                            'transport': 'stdio',
                            'command': 'tool',
                            'args': <String>['serve'],
                            'workingDirectory': '/safe',
                            'env': <String, String>{
                              'PATH': '/attacker/bin',
                              'API_TOKEN': '',
                            },
                          },
                        ]),
                        jsonEncode(<Map<String, Object?>>[
                          <String, Object?>{
                            'id': 'mcp-shared',
                            'transport': 'http',
                            'url': 'https://mcp.example',
                            'name': 'Local MCP',
                            'headers': <String, String>{
                              'Authorization': 'Bearer local-mcp-secret',
                              'X-Trace-Id': 'local-trace',
                            },
                          },
                          <String, Object?>{
                            'id': 'mcp-moved',
                            'transport': 'http',
                            'url': 'https://old-mcp.example',
                            'headers': <String, String>{
                              'Authorization': 'Bearer must-not-forward-mcp',
                            },
                          },
                          <String, Object?>{
                            'id': 'mcp-stdio-path-changed',
                            'transport': 'stdio',
                            'command': 'tool',
                            'args': <String>['serve'],
                            'workingDirectory': '/safe',
                            'env': <String, String>{
                              'PATH': '/safe/bin',
                              'API_TOKEN': 'must-not-forward-stdio',
                            },
                          },
                        ]),
                      )
                      as String,
                )
                as List<dynamic>;
        final mcpById = <String, Map<String, dynamic>>{
          for (final item in mcp.cast<Map>())
            item['id'] as String: item.cast<String, dynamic>(),
        };
        expect(
          (mcpById['mcp-shared']!['headers'] as Map)['Authorization'],
          'Bearer local-mcp-secret',
        );
        expect(
          (mcpById['mcp-shared']!['headers'] as Map)['X-Trace-Id'],
          'imported-trace',
        );
        expect(mcpById['mcp-shared']!['name'], 'Imported MCP');
        expect(
          mcpById['mcp-moved']!['headers'] as Map? ?? const <String, Object?>{},
          isNot(contains('Authorization')),
        );
        expect(
          mcpById['mcp-new']!['env'] as Map? ?? const <String, Object?>{},
          isNot(contains('API_TOKEN')),
        );
        expect(
          mcpById['mcp-stdio-path-changed']!['env'] as Map? ??
              const <String, Object?>{},
          isNot(contains('API_TOKEN')),
        );
      },
    );

    test(
      'restore protects WebDAV and S3 credentials across target changes',
      () {
        final sameWebDav =
            jsonDecode(
                  BackupDataSanitizer.mergePreferenceForRestore(
                        'webdav_config_v1',
                        jsonEncode(<String, Object?>{
                          'url': 'https://dav.example',
                          'username': 'imported-user',
                          'password': '',
                          'path': 'imported-backups',
                        }),
                        jsonEncode(<String, Object?>{
                          'url': 'https://dav.example',
                          'username': 'local-user',
                          'password': 'local-dav-secret',
                          'path': 'local-backups',
                        }),
                      )
                      as String,
                )
                as Map<String, dynamic>;
        expect(sameWebDav['password'], 'local-dav-secret');
        expect(sameWebDav['username'], 'imported-user');
        expect(sameWebDav['path'], 'imported-backups');

        final movedWebDav =
            BackupDataSanitizer.mergePreferenceForRestore(
                  'webdav_config_v1',
                  jsonEncode(<String, Object?>{
                    'url': 'https://other-dav.example',
                    'password': '<redacted>',
                  }),
                  jsonEncode(<String, Object?>{
                    'url': 'https://dav.example',
                    'password': 'must-not-forward-dav',
                  }),
                )
                as String;
        expect(movedWebDav, isNot(contains('must-not-forward-dav')));

        final sameS3 =
            jsonDecode(
                  BackupDataSanitizer.mergePreferenceForRestore(
                        's3_config_v1',
                        jsonEncode(<String, Object?>{
                          'endpoint': 'https://s3.example',
                          'bucket': 'imported-bucket',
                          'accessKeyId': '',
                          'secretAccessKey': '<redacted>',
                        }),
                        jsonEncode(<String, Object?>{
                          'endpoint': 'https://s3.example',
                          'bucket': 'local-bucket',
                          'accessKeyId': 'local-access-key',
                          'secretAccessKey': 'local-s3-secret',
                          'sessionToken': 'local-session-secret',
                        }),
                      )
                      as String,
                )
                as Map<String, dynamic>;
        expect(sameS3['accessKeyId'], 'local-access-key');
        expect(sameS3['secretAccessKey'], 'local-s3-secret');
        expect(sameS3['sessionToken'], 'local-session-secret');
        expect(sameS3['bucket'], 'imported-bucket');

        final movedS3 =
            BackupDataSanitizer.mergePreferenceForRestore(
                  's3_config_v1',
                  jsonEncode(<String, Object?>{
                    'endpoint': 'https://other-s3.example',
                    'accessKeyId': '',
                    'secretAccessKey': '',
                  }),
                  jsonEncode(<String, Object?>{
                    'endpoint': 'https://s3.example',
                    'accessKeyId': 'must-not-forward-access',
                    'secretAccessKey': 'must-not-forward-s3',
                  }),
                )
                as String;
        expect(movedS3, isNot(contains('must-not-forward-access')));
        expect(movedS3, isNot(contains('must-not-forward-s3')));
      },
    );

    test('restore remains fail-closed for malformed credential JSON', () {
      final existing = <String, String>{
        'search_services_v1': jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'search-1',
            'type': 'tavily',
            'url': 'https://search.example',
            'apiKey': 'local-search-secret',
          },
        ]),
        'tts_services_v1': jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'tts-1',
            'kind': 'openai',
            'baseUrl': 'https://tts.example',
            'apiKey': 'local-tts-secret',
          },
        ]),
        'mcp_servers_v1': jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'mcp-1',
            'transport': 'http',
            'url': 'https://mcp.example',
            'headers': <String, String>{
              'Authorization': 'Bearer local-mcp-secret',
            },
          },
        ]),
        'webdav_config_v1': jsonEncode(<String, Object?>{
          'url': 'https://dav.example',
          'password': 'local-dav-secret',
        }),
        's3_config_v1': jsonEncode(<String, Object?>{
          'endpoint': 'https://s3.example',
          'secretAccessKey': 'local-s3-secret',
        }),
      };

      for (final key in <String>[
        'search_services_v1',
        'tts_services_v1',
        'mcp_servers_v1',
      ]) {
        expect(
          BackupDataSanitizer.mergePreferenceForRestore(
            key,
            '{broken',
            existing[key],
          ),
          '[]',
        );
      }
      for (final key in <String>['webdav_config_v1', 's3_config_v1']) {
        expect(
          BackupDataSanitizer.mergePreferenceForRestore(
            key,
            '{broken',
            existing[key],
          ),
          '{}',
        );
      }
    });
  });
}
