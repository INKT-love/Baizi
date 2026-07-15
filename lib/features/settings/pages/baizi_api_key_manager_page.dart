import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/model_catalog_service.dart';
import '../../../core/services/secure_api_key_store.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_primary_button.dart';
import '../../../shared/widgets/ios_tactile.dart';

class BaiziApiKeyManagerPage extends StatefulWidget {
  const BaiziApiKeyManagerPage({super.key});

  @override
  State<BaiziApiKeyManagerPage> createState() => _BaiziApiKeyManagerPageState();
}

class _BaiziApiKeyManagerPageState extends State<BaiziApiKeyManagerPage> {
  String? _busyProfileId;
  bool _adding = false;
  ModelCatalogFailureType? _catalogError;
  bool _storageError = false;

  bool get _isBusy => _adding || _busyProfileId != null;

  Future<void> _addProfile() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await _showEditorDialog(
      title: l10n.baiziKeyManagerAddTitle,
      includeKey: true,
    );
    if (result == null || !mounted) return;

    setState(() {
      _adding = true;
      _catalogError = null;
      _storageError = false;
    });
    try {
      await context.read<SettingsProvider>().addBaiziApiKeyProfile(
        result.label,
        result.key!,
      );
    } on ModelCatalogException catch (error) {
      if (mounted) setState(() => _catalogError = error.type);
    } catch (_) {
      if (mounted) setState(() => _storageError = true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _selectProfile(BaiziApiKeyProfile profile) async {
    if (_isBusy) return;
    setState(() {
      _busyProfileId = profile.id;
      _catalogError = null;
      _storageError = false;
    });
    try {
      await context.read<SettingsProvider>().selectBaiziApiKeyProfile(
        profile.id,
      );
    } on ModelCatalogException catch (error) {
      if (mounted) setState(() => _catalogError = error.type);
    } catch (_) {
      if (mounted) setState(() => _storageError = true);
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _renameProfile(BaiziApiKeyProfile profile) async {
    if (_isBusy) return;
    final l10n = AppLocalizations.of(context)!;
    final result = await _showEditorDialog(
      title: l10n.baiziKeyManagerRenameTitle,
      initialLabel: profile.label,
    );
    if (result == null || !mounted) return;

    setState(() {
      _busyProfileId = profile.id;
      _storageError = false;
    });
    try {
      await context.read<SettingsProvider>().renameBaiziApiKeyProfile(
        profile.id,
        result.label,
      );
    } catch (_) {
      if (mounted) setState(() => _storageError = true);
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _deleteProfile(BaiziApiKeyProfile profile) async {
    if (_isBusy) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.baiziKeyManagerDeleteTitle),
        content: Text(l10n.baiziKeyManagerDeleteMessage(profile.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.multiKeyPageCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.multiKeyPageDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busyProfileId = profile.id;
      _catalogError = null;
      _storageError = false;
    });
    try {
      await context.read<SettingsProvider>().deleteBaiziApiKeyProfile(
        profile.id,
      );
    } on ModelCatalogException catch (error) {
      if (mounted) setState(() => _catalogError = error.type);
    } catch (_) {
      if (mounted) setState(() => _storageError = true);
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<_BaiziKeyEditorResult?> _showEditorDialog({
    required String title,
    String? initialLabel,
    bool includeKey = false,
  }) async {
    final labelController = TextEditingController(text: initialLabel ?? '');
    final keyController = TextEditingController();
    var obscureKey = true;
    final result = await showDialog<_BaiziKeyEditorResult>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: labelController,
                    autofocus: true,
                    textInputAction: includeKey
                        ? TextInputAction.next
                        : TextInputAction.done,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: l10n.baiziKeyManagerNameLabel,
                    ),
                  ),
                  if (includeKey) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: keyController,
                      obscureText: obscureKey,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: l10n.baiziApiKeyLabel,
                        suffixIcon: Tooltip(
                          message: obscureKey
                              ? l10n.baiziShowKeyTooltip
                              : l10n.baiziHideKeyTooltip,
                          child: IosIconButton(
                            icon: obscureKey ? Lucide.Eye : Lucide.EyeOff,
                            size: 18,
                            minSize: 40,
                            semanticLabel: obscureKey
                                ? l10n.baiziShowKeyTooltip
                                : l10n.baiziHideKeyTooltip,
                            onTap: () =>
                                setDialogState(() => obscureKey = !obscureKey),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.multiKeyPageCancel),
              ),
              TextButton(
                onPressed:
                    labelController.text.trim().isEmpty ||
                        (includeKey && keyController.text.trim().isEmpty)
                    ? null
                    : () => Navigator.of(dialogContext).pop(
                        _BaiziKeyEditorResult(
                          label: labelController.text.trim(),
                          key: includeKey ? keyController.text.trim() : null,
                        ),
                      ),
                child: Text(l10n.multiKeyPageSave),
              ),
            ],
          ),
        );
      },
    );
    labelController.dispose();
    keyController.dispose();
    return result;
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
    final profiles = settings.baiziApiKeyProfiles;
    final error = _errorText(l10n);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.settingsPageBackButton,
            enabled: !_isBusy,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.baiziKeyManagerTitle),
        actions: [
          Tooltip(
            message: l10n.baiziKeyManagerAdd,
            child: IosIconButton(
              icon: Lucide.Plus,
              size: 21,
              minSize: 44,
              semanticLabel: l10n.baiziKeyManagerAdd,
              enabled: !_isBusy,
              onTap: _addProfile,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: profiles.isEmpty
                ? _EmptyKeyList(onAdd: _isBusy ? null : _addProfile)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: profiles.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 56),
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      final isActive =
                          profile.id == settings.activeBaiziApiKeyProfileId;
                      final isSwitching = _busyProfileId == profile.id;
                      return IosCardPress(
                        borderRadius: BorderRadius.zero,
                        baseColor: Colors.transparent,
                        onTap: isActive || _isBusy
                            ? null
                            : () => _selectProfile(profile),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 62),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const Icon(Lucide.KeyRound, size: 21),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        profile.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (isActive)
                                        Text(
                                          l10n.baiziKeyManagerActive,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                    ],
                                  ),
                                ),
                                if (isSwitching)
                                  SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  )
                                else ...[
                                  Tooltip(
                                    message: l10n.baiziKeyManagerRenameTooltip,
                                    child: IosIconButton(
                                      icon: Lucide.Pencil,
                                      size: 18,
                                      minSize: 40,
                                      semanticLabel:
                                          l10n.baiziKeyManagerRenameTooltip,
                                      enabled: !_isBusy,
                                      onTap: () => _renameProfile(profile),
                                    ),
                                  ),
                                  Tooltip(
                                    message: l10n.baiziKeyManagerDeleteTooltip,
                                    child: IosIconButton(
                                      icon: Lucide.Trash2,
                                      size: 18,
                                      minSize: 40,
                                      semanticLabel:
                                          l10n.baiziKeyManagerDeleteTooltip,
                                      enabled: !_isBusy,
                                      onTap: () => _deleteProfile(profile),
                                    ),
                                  ),
                                  if (!isActive)
                                    const Icon(Lucide.ChevronRight, size: 18),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyKeyList extends StatelessWidget {
  const _EmptyKeyList({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Lucide.KeyRound, size: 36),
              const SizedBox(height: 16),
              Text(
                l10n.baiziKeyManagerNoKeys,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: IosPrimaryButton(
                  label: l10n.baiziKeyManagerAdd,
                  icon: Lucide.Plus,
                  onTap: onAdd,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BaiziKeyEditorResult {
  const _BaiziKeyEditorResult({required this.label, this.key});

  final String label;
  final String? key;
}
