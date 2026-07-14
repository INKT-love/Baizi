import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/config/baizi_gateway.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/secure_api_key_store.dart';
import 'package:Kelivo/features/model/widgets/baizi_model_select_sheet.dart';
import 'package:Kelivo/features/model/widgets/model_select_sheet.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';

const _cachedModelsKey = 'baizi_models_cache_v1';
const _recentModelsKey = 'baizi_recent_models_v1';
const _pinnedModelsKey = 'pinned_models_v1';
const _selectedModelKey = 'selected_model_v1';

const _defaultModels = <String>[
  'gpt-4o-mini',
  'claude-3-5-sonnet',
  'gemini-2.0-flash',
];

Future<SettingsProvider> _settings({
  List<String> models = _defaultModels,
  String? selectedModelId,
  List<String> recentModels = const <String>[],
  List<String> pinnedModels = const <String>[],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _cachedModelsKey: models,
    _recentModelsKey: recentModels,
    _pinnedModelsKey: pinnedModels,
    if (selectedModelId != null)
      _selectedModelKey: '${BaiziGateway.providerId}::$selectedModelId',
  });
  final settings = SettingsProvider(
    apiKeyStore: SecureApiKeyStore(backend: _MemorySecureApiKeyBackend()),
  );
  await settings.initialization;
  return settings;
}

Future<void> _pumpModelSelector(
  WidgetTester tester, {
  required SettingsProvider settings,
  required Future<void> Function() verify,
  TargetPlatform platform = TargetPlatform.iOS,
  String? initialModelId,
  ValueChanged<ModelSelection?>? onResult,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  try {
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('open-model-selector'),
                onPressed: () async {
                  final result = await showModelSelector(
                    context,
                    initialModelId: initialModelId,
                  );
                  onResult?.call(result);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-model-selector')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await verify();
  } finally {
    try {
      await _dismissModelSelector(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  }
}

Future<void> _dismissModelSelector(WidgetTester tester) async {
  final bottomSheet = find.byType(BottomSheet);
  if (bottomSheet.evaluate().isEmpty) return;
  Navigator.of(tester.element(bottomSheet)).pop();
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

Finder _modelRow(String modelId) {
  return find.ancestor(
    of: find.text(modelId),
    matching: find.byType(IosCardPress),
  );
}

void _expectBaiziRouteWithInitialSelection() {
  expect(find.byType(BaiziModelBrowser), findsOneWidget);
  expect(find.text('Choose a model'), findsOneWidget);

  final initialRow = _modelRow('claude-3-5-sonnet');
  expect(initialRow, findsOneWidget);
  expect(
    find.descendant(of: initialRow, matching: find.byIcon(Lucide.Check)),
    findsOneWidget,
  );

  final globalRow = _modelRow('gpt-4o-mini');
  expect(globalRow, findsOneWidget);
  expect(
    find.descendant(of: globalRow, matching: find.byIcon(Lucide.Check)),
    findsNothing,
  );
  expect(
    find.byKey(const ValueKey('model-selector-provider-tab-baizi')),
    findsNothing,
  );
  expect(
    find.byKey(const ValueKey('model-selector-sticky-provider')),
    findsNothing,
  );
  expect(
    find.descendant(of: initialRow, matching: find.byType(InkWell)),
    findsNothing,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS showModelSelector opens Baizi selector and honors initial model',
    (tester) async {
      final settings = await _settings(selectedModelId: 'gpt-4o-mini');
      await _pumpModelSelector(
        tester,
        settings: settings,
        platform: TargetPlatform.iOS,
        initialModelId: 'claude-3-5-sonnet',
        verify: () async => _expectBaiziRouteWithInitialSelection(),
      );
    },
  );

  testWidgets(
    'Android showModelSelector opens Baizi selector and honors initial model',
    (tester) async {
      final settings = await _settings(selectedModelId: 'gpt-4o-mini');
      await _pumpModelSelector(
        tester,
        settings: settings,
        platform: TargetPlatform.android,
        initialModelId: 'claude-3-5-sonnet',
        verify: () async => _expectBaiziRouteWithInitialSelection(),
      );
    },
  );

  testWidgets('Baizi selector shows every cached model', (tester) async {
    final settings = await _settings();
    await _pumpModelSelector(
      tester,
      settings: settings,
      verify: () async {
        for (final model in _defaultModels) {
          expect(find.text(model), findsOneWidget);
        }
      },
    );
  });

  testWidgets('Baizi selector search is case-insensitive', (tester) async {
    final settings = await _settings();
    await _pumpModelSelector(
      tester,
      settings: settings,
      verify: () async {
        await tester.enterText(find.byType(TextField), 'GpT-4O');
        await tester.pump();

        expect(find.text('gpt-4o-mini'), findsOneWidget);
        expect(find.text('claude-3-5-sonnet'), findsNothing);
        expect(find.text('gemini-2.0-flash'), findsNothing);
      },
    );
  });

  testWidgets('Baizi selector shows a no-results state for search', (
    tester,
  ) async {
    final settings = await _settings();
    await _pumpModelSelector(
      tester,
      settings: settings,
      verify: () async {
        await tester.enterText(
          find.byType(TextField),
          'model-that-does-not-exist',
        );
        await tester.pump();

        expect(find.text('No matching models'), findsOneWidget);
        for (final model in _defaultModels) {
          expect(find.text(model), findsNothing);
        }
      },
    );
  });

  testWidgets(
    'Baizi selector separates favorites and recent without duplicates',
    (tester) async {
      final settings = await _settings(
        pinnedModels: const <String>['baizi::gpt-4o-mini'],
        recentModels: const <String>[
          'gpt-4o-mini',
          'claude-3-5-sonnet',
          'claude-3-5-sonnet',
        ],
      );
      await _pumpModelSelector(
        tester,
        settings: settings,
        verify: () async {
          expect(find.text('Favorites'), findsOneWidget);
          expect(find.text('Recent'), findsOneWidget);
          expect(find.text('gpt-4o-mini'), findsOneWidget);
          expect(find.text('claude-3-5-sonnet'), findsOneWidget);
          expect(find.text('gemini-2.0-flash'), findsOneWidget);
        },
      );
    },
  );

  testWidgets('Baizi selector returns the tapped model', (tester) async {
    ModelSelection? result;
    final settings = await _settings();
    await _pumpModelSelector(
      tester,
      settings: settings,
      onResult: (selection) => result = selection,
      verify: () async {
        await tester.tap(find.text('claude-3-5-sonnet'));
        await tester.pumpAndSettle();

        expect(result?.providerKey, BaiziGateway.providerId);
        expect(result?.modelId, 'claude-3-5-sonnet');
      },
    );
  });

  testWidgets('Baizi selector shows an empty state without cached models', (
    tester,
  ) async {
    final settings = await _settings(models: const <String>[]);
    await _pumpModelSelector(
      tester,
      settings: settings,
      verify: () async {
        expect(find.byType(BaiziModelBrowser), findsOneWidget);
        expect(find.text('No models available'), findsOneWidget);
      },
    );
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
