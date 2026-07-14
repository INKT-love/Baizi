import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/model_catalog_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_primary_button.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../model/widgets/baizi_model_select_sheet.dart';

class BaiziSetupPage extends StatefulWidget {
  const BaiziSetupPage({
    super.key,
    this.allowBack = false,
    this.forceKeyEntry = false,
  });

  final bool allowBack;
  final bool forceKeyEntry;

  @override
  State<BaiziSetupPage> createState() => _BaiziSetupPageState();
}

class _BaiziSetupPageState extends State<BaiziSetupPage> {
  final TextEditingController _keyController = TextEditingController();
  bool _obscureKey = true;
  bool _submitting = false;
  bool _refreshing = false;
  bool _showKeyEntry = true;
  ModelCatalogFailureType? _catalogError;
  bool _storageError = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _showKeyEntry = widget.forceKeyEntry || !settings.hasBaiziApiKey;
    if (!_showKeyEntry && settings.baiziModels.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshModels());
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _pasteKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final value = data?.text?.trim() ?? '';
    if (value.isEmpty || !mounted) return;
    _keyController.text = value;
    _keyController.selection = TextSelection.collapsed(offset: value.length);
    setState(() {
      _catalogError = null;
      _storageError = false;
    });
  }

  Future<void> _configureKey() async {
    final candidate = _keyController.text.trim();
    if (candidate.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _catalogError = null;
      _storageError = false;
    });
    try {
      await context.read<SettingsProvider>().configureBaiziApiKey(candidate);
      _keyController.clear();
      if (!mounted) return;
      setState(() => _showKeyEntry = false);
    } on ModelCatalogException catch (error) {
      if (mounted) setState(() => _catalogError = error.type);
    } catch (_) {
      if (mounted) setState(() => _storageError = true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _refreshModels() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _catalogError = null;
    });
    try {
      await context.read<SettingsProvider>().refreshBaiziModels();
    } on ModelCatalogException catch (error) {
      if (mounted) setState(() => _catalogError = error.type);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _selectModel(String modelId) async {
    await context.read<SettingsProvider>().setCurrentModel('baizi', modelId);
    if (widget.allowBack && mounted) Navigator.of(context).pop();
  }

  String? _errorText(AppLocalizations l10n) {
    if (_storageError) return l10n.baiziSecureStorageError;
    return switch (_catalogError) {
      ModelCatalogFailureType.unauthorized => l10n.baiziInvalidKey,
      ModelCatalogFailureType.forbidden => l10n.baiziForbiddenKey,
      ModelCatalogFailureType.network => l10n.baiziNetworkError,
      ModelCatalogFailureType.server => l10n.baiziServerError,
      ModelCatalogFailureType.invalidResponse => l10n.baiziInvalidResponse,
      ModelCatalogFailureType.empty => l10n.baiziEmptyModels,
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final error = _errorText(l10n);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.allowBack
            ? Tooltip(
                message: l10n.settingsPageBackButton,
                child: IosIconButton(
                  icon: Lucide.ArrowLeft,
                  size: 22,
                  minSize: 44,
                  semanticLabel: l10n.settingsPageBackButton,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              )
            : null,
        title: Text(l10n.baiziAppName),
      ),
      body: SafeArea(
        top: false,
        child: _showKeyEntry
            ? _buildKeyStep(context, l10n, error)
            : _buildModelStep(context, l10n, settings, error),
      ),
    );
  }

  Widget _buildKeyStep(
    BuildContext context,
    AppLocalizations l10n,
    String? error,
  ) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Lucide.MessageCircle, size: 42, color: cs.primary),
                const SizedBox(height: 20),
                Text(
                  l10n.baiziConnectTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _keyController,
                  obscureText: _obscureKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _configureKey(),
                  onChanged: (_) => setState(() {
                    _catalogError = null;
                    _storageError = false;
                  }),
                  decoration: InputDecoration(
                    labelText: l10n.baiziApiKeyLabel,
                    prefixIcon: const Icon(Lucide.KeyRound, size: 20),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: l10n.baiziPasteTooltip,
                          child: IosIconButton(
                            icon: Lucide.Clipboard,
                            size: 19,
                            minSize: 40,
                            semanticLabel: l10n.baiziPasteTooltip,
                            enabled: !_submitting,
                            onTap: _pasteKey,
                          ),
                        ),
                        Tooltip(
                          message: _obscureKey
                              ? l10n.baiziShowKeyTooltip
                              : l10n.baiziHideKeyTooltip,
                          child: IosIconButton(
                            icon: _obscureKey ? Lucide.Eye : Lucide.EyeOff,
                            size: 19,
                            minSize: 40,
                            semanticLabel: _obscureKey
                                ? l10n.baiziShowKeyTooltip
                                : l10n.baiziHideKeyTooltip,
                            enabled: !_submitting,
                            onTap: () =>
                                setState(() => _obscureKey = !_obscureKey),
                          ),
                        ),
                        Tooltip(
                          message: l10n.baiziSetupClearTooltip,
                          child: IosIconButton(
                            icon: Lucide.X,
                            size: 19,
                            minSize: 40,
                            semanticLabel: l10n.baiziSetupClearTooltip,
                            enabled: !_submitting,
                            onTap: () {
                              _keyController.clear();
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                    errorText: error,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                IosPrimaryButton(
                  label: _submitting
                      ? l10n.baiziVerifyingKey
                      : l10n.baiziVerifyKey,
                  icon: Lucide.ArrowRight,
                  loading: _submitting,
                  onTap: _submitting || _keyController.text.trim().isEmpty
                      ? null
                      : _configureKey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModelStep(
    BuildContext context,
    AppLocalizations l10n,
    SettingsProvider settings,
    String? error,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.baiziChooseModelTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        error,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: cs.error),
                      ),
                    ],
                  ],
                ),
              ),
              Tooltip(
                message: l10n.baiziRefreshModels,
                child: IosIconButton(
                  size: 20,
                  minSize: 44,
                  semanticLabel: l10n.baiziRefreshModels,
                  enabled: !_refreshing,
                  onTap: _refreshModels,
                  builder: (color) => _refreshing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Lucide.RefreshCw, size: 20, color: color),
                ),
              ),
              Tooltip(
                message: l10n.baiziChangeKey,
                child: IosIconButton(
                  icon: Lucide.KeyRound,
                  size: 20,
                  minSize: 44,
                  semanticLabel: l10n.baiziChangeKey,
                  onTap: () => setState(() => _showKeyEntry = true),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: BaiziModelBrowser(
            selectedModelId: settings.currentModelId,
            onSelected: _selectModel,
          ),
        ),
      ],
    );
  }
}
