import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/character_card.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/world_book_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../core/services/character_card/character_card_import_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../../utils/avatar_cache.dart';
import '../../../utils/sandbox_path_resolver.dart';
import 'assistant_settings_edit_page.dart';

class AssistantSettingsPage extends StatelessWidget {
  const AssistantSettingsPage({super.key, this.characterCardImportService});

  final CharacterCardImportService? characterCardImportService;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    final assistants = context.watch<AssistantProvider>().assistants;

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.assistantSettingsPageTitle),
        actions: [
          Tooltip(
            message: l10n.characterCardImportTooltip,
            child: IosIconButton(
              key: const ValueKey('assistant-import-character-card'),
              icon: Lucide.Upload,
              color: cs.onSurface,
              size: 21,
              minSize: 44,
              semanticLabel: l10n.characterCardImportTooltip,
              onTap: () => _importCharacterCard(
                context,
                characterCardImportService ?? CharacterCardImportService(),
              ),
            ),
          ),
          Tooltip(
            message: l10n.assistantSettingsAddSheetSave,
            child: _TactileIconButton(
              icon: Lucide.Plus,
              color: cs.onSurface,
              size: 22,
              onTap: () async {
                final assistantProvider = context.read<AssistantProvider>();
                final name = await _showAddAssistantSheet(context);
                if (!context.mounted || name == null) return;
                final id = await assistantProvider.addAssistant(
                  name: name.trim(),
                  context: context,
                );
                if (!context.mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AssistantSettingsEditPage(assistantId: id),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        itemCount: assistants.length,
        onReorderItem: (oldIndex, newIndex) async {
          // Immediately update UI for smooth experience
          final assistantProvider = context.read<AssistantProvider>();
          await assistantProvider.reorderAssistants(oldIndex, newIndex);
        },
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = Curves.easeOutBack.transform(animation.value);
              return Transform.scale(
                scale: 0.98 + 0.02 * t,
                child: Material(
                  elevation: 0, // remove drag shadow
                  shadowColor: Colors.transparent,
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: child,
                ),
              );
            },
          );
        },
        itemBuilder: (context, index) {
          final item = assistants[index];
          return KeyedSubtree(
            key: ValueKey('reorder-assistant-${item.id}'),
            child: ReorderableDelayedDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AssistantCard(item: item),
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _CharacterCardConflictMode { createCopy, overwrite }

class _CharacterCardImportDecision {
  const _CharacterCardImportDecision({
    required this.mode,
    this.overwriteAssistantId,
  });

  final _CharacterCardConflictMode mode;
  final String? overwriteAssistantId;
}

Future<void> _importCharacterCard(
  BuildContext context,
  CharacterCardImportService service,
) async {
  final l10n = AppLocalizations.of(context)!;
  FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const <String>['png', 'json'],
      withData: false,
    );
  } catch (_) {
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: l10n.characterCardImportErrorReadFailed,
      type: NotificationType.error,
    );
    return;
  }
  if (!context.mounted || picked == null || picked.files.isEmpty) return;

  final selected = picked.files.single;
  CharacterCardImportPreview preview;
  try {
    final path = selected.path;
    if (path != null && path.trim().isNotEmpty) {
      preview = await service.prepareFile(path);
    } else if (selected.bytes != null) {
      preview = await service.prepareBytes(
        selected.bytes!,
        sourceFileName: selected.name,
      );
    } else {
      throw const CharacterCardImportException(
        CharacterCardImportErrorCode.fileReadFailed,
        'Selected file has no readable path or bytes.',
      );
    }
  } catch (error) {
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: _characterCardImportErrorMessage(l10n, error),
      type: NotificationType.error,
    );
    return;
  }
  if (!context.mounted) return;

  final assistantProvider = context.read<AssistantProvider>();
  final worldBookProvider = context.read<WorldBookProvider>();
  final targetName = preview.document.data.name.trim();
  final matches = assistantProvider.assistants
      .where((assistant) => assistant.name.trim() == targetName)
      .toList(growable: false);

  final result = await showModalBottomSheet<CharacterCardImportResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => _CharacterCardImportPreviewSheet(
      preview: preview,
      matchingAssistants: matches,
      onImport: (decision) => service.commit(
        preview: preview,
        assistantProvider: assistantProvider,
        worldBookProvider: worldBookProvider,
        overwriteAssistantId:
            decision.mode == _CharacterCardConflictMode.overwrite
            ? decision.overwriteAssistantId
            : null,
        copySuffix: l10n.assistantSettingsCopySuffix,
      ),
    ),
  );
  if (!context.mounted || result == null) return;
  showAppSnackBar(
    context,
    message: l10n.characterCardImportSuccess(result.assistantName),
    type: NotificationType.success,
  );
}

class _CharacterCardImportPreviewSheet extends StatefulWidget {
  const _CharacterCardImportPreviewSheet({
    required this.preview,
    required this.matchingAssistants,
    required this.onImport,
  });

  final CharacterCardImportPreview preview;
  final List<Assistant> matchingAssistants;
  final Future<CharacterCardImportResult> Function(
    _CharacterCardImportDecision decision,
  )
  onImport;

  @override
  State<_CharacterCardImportPreviewSheet> createState() =>
      _CharacterCardImportPreviewSheetState();
}

class _CharacterCardImportPreviewSheetState
    extends State<_CharacterCardImportPreviewSheet> {
  _CharacterCardConflictMode _mode = _CharacterCardConflictMode.createCopy;
  String? _overwriteAssistantId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _overwriteAssistantId = widget.matchingAssistants.isEmpty
        ? null
        : widget.matchingAssistants.first.id;
  }

  Future<void> _commit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = await widget.onImport(
        _CharacterCardImportDecision(
          mode: _mode,
          overwriteAssistantId: _mode == _CharacterCardConflictMode.overwrite
              ? _overwriteAssistantId
              : null,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnackBar(
        context,
        message: _characterCardImportErrorMessage(
          AppLocalizations.of(context)!,
          error,
        ),
        type: NotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final data = widget.preview.document.data;
    final summary = <String>[data.description, data.personality, data.scenario]
        .map((value) => value.trim())
        .firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => l10n.characterCardImportNoSummary,
        );
    final format = widget.preview.isPng
        ? l10n.characterCardImportFormatPng
        : l10n.characterCardImportFormatJson;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            key: const ValueKey('character-card-import-preview'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.characterCardImportPreviewTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: AppFontWeights.semibold,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _CharacterCardPreviewAvatar(preview: widget.preview),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.name.trim().isEmpty
                              ? l10n.assistantProviderNewAssistantName
                              : data.name.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: AppFontWeights.semibold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          l10n.characterCardImportFormatVersion(
                            format,
                            widget.preview.document.specVersion,
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                l10n.characterCardImportSummaryLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(summary, style: const TextStyle(fontSize: 14, height: 1.45)),
              const SizedBox(height: 18),
              _CharacterCardMetricRow(
                icon: Lucide.MessagesSquare,
                label: l10n.characterCardImportGreetingCount(
                  widget.preview.greetingCount,
                ),
              ),
              const SizedBox(height: 10),
              _CharacterCardMetricRow(
                icon: Lucide.BookOpen,
                label: l10n.characterCardImportWorldBookCount(
                  widget.preview.worldBookEntryCount,
                ),
              ),
              if (widget.matchingAssistants.isNotEmpty) ...[
                const SizedBox(height: 22),
                IgnorePointer(
                  ignoring: _saving,
                  child:
                      CupertinoSlidingSegmentedControl<
                        _CharacterCardConflictMode
                      >(
                        key: const ValueKey('character-card-conflict-mode'),
                        groupValue: _mode,
                        children: <_CharacterCardConflictMode, Widget>{
                          _CharacterCardConflictMode.createCopy: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(l10n.characterCardImportCreateCopy),
                          ),
                          _CharacterCardConflictMode.overwrite: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(l10n.characterCardImportOverwrite),
                          ),
                        },
                        onValueChanged: (mode) {
                          if (mode != null) setState(() => _mode = mode);
                        },
                      ),
                ),
                if (_mode == _CharacterCardConflictMode.overwrite) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.characterCardImportOverwriteHint,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (widget.matchingAssistants.length > 1) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('character-card-overwrite-target'),
                      initialValue: _overwriteAssistantId,
                      borderRadius: BorderRadius.circular(8),
                      decoration: InputDecoration(
                        labelText: l10n.characterCardImportOverwriteTarget,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: [
                        for (
                          var index = 0;
                          index < widget.matchingAssistants.length;
                          index++
                        )
                          DropdownMenuItem<String>(
                            value: widget.matchingAssistants[index].id,
                            child: Text(
                              l10n.characterCardImportOverwriteTargetOption(
                                widget.matchingAssistants[index].name,
                                index + 1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) =>
                                setState(() => _overwriteAssistantId = value),
                    ),
                  ],
                ],
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: IosTileButton(
                      label: l10n.characterCardImportCancel,
                      icon: Lucide.X,
                      enabled: !_saving,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: IosTileButton(
                      key: const ValueKey('character-card-import-confirm'),
                      label: _saving
                          ? l10n.characterCardImportSaving
                          : l10n.characterCardImportConfirm,
                      icon: _saving ? Lucide.RefreshCw : Lucide.Upload,
                      enabled:
                          !_saving &&
                          (_mode == _CharacterCardConflictMode.createCopy ||
                              _overwriteAssistantId != null),
                      backgroundColor: cs.primary,
                      onTap: _commit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterCardPreviewAvatar extends StatelessWidget {
  const _CharacterCardPreviewAvatar({required this.preview});

  final CharacterCardImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = preview.document.data.name.trim();
    final fallback = Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first,
        style: TextStyle(
          fontSize: 26,
          fontWeight: AppFontWeights.semibold,
          color: cs.onPrimaryContainer,
        ),
      ),
    );
    if (!preview.isPng) return fallback;
    return ClipOval(
      child: Image.memory(
        preview.sourceBytes,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _CharacterCardMetricRow extends StatelessWidget {
  const _CharacterCardMetricRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
      ],
    );
  }
}

String _characterCardImportErrorMessage(AppLocalizations l10n, Object error) {
  if (error is CharacterCardImportException) {
    return switch (error.code) {
      CharacterCardImportErrorCode.unsupportedFileType =>
        l10n.characterCardImportErrorUnsupportedFile,
      CharacterCardImportErrorCode.fileReadFailed =>
        l10n.characterCardImportErrorReadFailed,
      CharacterCardImportErrorCode.storageFailed =>
        l10n.characterCardImportErrorStorageFailed,
      CharacterCardImportErrorCode.overwriteTargetMissing =>
        l10n.characterCardImportErrorTargetMissing,
    };
  }
  if (error is CharacterCardParseException) {
    return switch (error.code) {
      CharacterCardParseErrorCode.fileTooLarge ||
      CharacterCardParseErrorCode.jsonTooLarge ||
      CharacterCardParseErrorCode.pngMetadataTooLarge ||
      CharacterCardParseErrorCode.decompressedDataTooLarge =>
        l10n.characterCardImportErrorFileTooLarge,
      CharacterCardParseErrorCode.pngDimensionsTooLarge =>
        l10n.characterCardImportErrorImageTooLarge,
      CharacterCardParseErrorCode.invalidPngSignature ||
      CharacterCardParseErrorCode.invalidPngStructure ||
      CharacterCardParseErrorCode.truncatedPng ||
      CharacterCardParseErrorCode.invalidPngCrc ||
      CharacterCardParseErrorCode.invalidPngPixels =>
        l10n.characterCardImportErrorInvalidPng,
      CharacterCardParseErrorCode.missingPngMetadata =>
        l10n.characterCardImportErrorMissingMetadata,
      CharacterCardParseErrorCode.unsupportedSpec =>
        l10n.characterCardImportErrorUnsupportedVersion,
      CharacterCardParseErrorCode.jsonTooDeep ||
      CharacterCardParseErrorCode.jsonTooManyNodes ||
      CharacterCardParseErrorCode.invalidJson ||
      CharacterCardParseErrorCode.invalidUtf8 ||
      CharacterCardParseErrorCode.invalidCard ||
      CharacterCardParseErrorCode.invalidField ||
      CharacterCardParseErrorCode.conflictingPngMetadata ||
      CharacterCardParseErrorCode.invalidBase64 =>
        l10n.characterCardImportErrorInvalidCard,
    };
  }
  return l10n.characterCardImportErrorStorageFailed;
}

class _AssistantCard extends StatelessWidget {
  const _AssistantCard({required this.item});
  final Assistant item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseBg = isDark
        ? Colors.white10
        : Colors.white.withValues(alpha: 0.96);
    final content = _TactileCard(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AssistantSettingsEditPage(assistantId: item.id),
          ),
        );
      },
      builder: (pressed, overlay) {
        return Container(
          decoration: BoxDecoration(
            color: Color.alphaBlend(overlay, baseBg),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant.withValues(
                alpha: isDark ? 0.12 : 0.08,
              ),
              width: 0.8,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AssistantAvatar(item: item, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: AppFontWeights.emphasis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (item.systemPrompt.trim().isEmpty
                                ? l10n.assistantSettingsNoPromptPlaceholder
                                : item.systemPrompt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withValues(alpha: 0.7),
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return Slidable(
      key: ValueKey('slidable-assistant-${item.id}'),
      endActionPane: ActionPane(
        motion: const StretchMotion(),
        extentRatio: 0.6,
        children: [
          CustomSlidableAction(
            autoClose: true,
            backgroundColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            onPressed: (_) async {
              final assistantProvider = context.read<AssistantProvider>();
              final newId = await assistantProvider.duplicateAssistant(
                item.id,
                l10n: l10n,
              );
              if (!context.mounted) return;
              if (newId != null) {
                showAppSnackBar(
                  context,
                  message: l10n.assistantSettingsCopySuccess,
                  type: NotificationType.success,
                );
              }
            },
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isDark
                    ? cs.primary.withValues(alpha: 0.16)
                    : cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SizedBox.expand(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Lucide.Copy, color: cs.primary, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          l10n.assistantSettingsCopyButton,
                          style: TextStyle(
                            color: cs.primary,
                            fontWeight: AppFontWeights.emphasis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          CustomSlidableAction(
            autoClose: true,
            backgroundColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            onPressed: (_) async {
              final assistantProvider = context.read<AssistantProvider>();
              final count = assistantProvider.assistants.length;
              if (count <= 1) {
                showAppSnackBar(
                  context,
                  message: l10n.assistantSettingsAtLeastOneAssistantRequired,
                  type: NotificationType.warning,
                );
                return;
              }
              final ok = await _confirmDelete(context, l10n);
              if (!context.mounted || ok != true) return;
              final success = await assistantProvider.deleteAssistant(item.id);
              if (!context.mounted) return;
              if (success != true) {
                showAppSnackBar(
                  context,
                  message: l10n.assistantSettingsAtLeastOneAssistantRequired,
                  type: NotificationType.warning,
                );
              }
            },
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isDark
                    ? cs.error.withValues(alpha: 0.22)
                    : cs.error.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.error.withValues(alpha: 0.35)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SizedBox.expand(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Lucide.Trash2, color: cs.error, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          l10n.assistantSettingsDeleteButton,
                          style: TextStyle(
                            color: cs.error,
                            fontWeight: AppFontWeights.emphasis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      child: content,
    );
  }
}

// --- iOS-style tactile helpers ---

class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 22,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;
  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final pressColor = base.withValues(alpha: 0.7);
    final icon = Icon(
      widget.icon,
      size: widget.size,
      color: _pressed ? pressColor : base,
    );
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          Haptics.light();
          widget.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: icon,
        ),
      ),
    );
  }
}

class _TactileCard extends StatefulWidget {
  const _TactileCard({required this.builder, this.onTap});
  final Widget Function(bool pressed, Color overlay) builder;
  final VoidCallback? onTap;
  @override
  State<_TactileCard> createState() => _TactileCardState();
}

class _TactileCardState extends State<_TactileCard> {
  bool _pressed = false;
  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlay = _pressed
        ? (isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04))
        : Colors.transparent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: widget.onTap == null ? null : () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (context.read<SettingsProvider>().hapticsOnCardTap) {
                Haptics.soft();
              }
              widget.onTap!.call();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: widget.builder(_pressed, overlay),
        ),
      ),
    );
  }
}

Future<String?> _showAddAssistantSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  String? result;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: bottomInset + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  l10n.assistantSettingsAddSheetTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.assistantSettingsAddSheetHint,
                  filled: true,
                  fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                onSubmitted: (_) =>
                    Navigator.of(ctx).pop(controller.text.trim()),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _IosOutlineButton(
                      label: l10n.assistantSettingsAddSheetCancel,
                      onTap: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _IosFilledButton(
                      label: l10n.assistantSettingsAddSheetSave,
                      onTap: () =>
                          Navigator.of(ctx).pop(controller.text.trim()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  ).then((val) => result = val as String?);
  final trimmed = (result ?? '').trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

Future<bool?> _confirmDelete(
  BuildContext context,
  AppLocalizations l10n,
) async {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(l10n.assistantSettingsDeleteDialogTitle),
        content: Text(l10n.assistantSettingsDeleteDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.assistantSettingsDeleteDialogCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.assistantSettingsDeleteDialogConfirm,
              style: TextStyle(color: cs.error),
            ),
          ),
        ],
      );
    },
  );
}

class _AssistantAvatar extends StatelessWidget {
  const _AssistantAvatar({required this.item, this.size = 40});
  final Assistant item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final av = (item.avatar ?? '').trim();
    if (av.isNotEmpty) {
      if (av.startsWith('http')) {
        return FutureBuilder<String?>(
          future: AvatarCache.getPath(av),
          builder: (ctx, snap) {
            final p = snap.data;
            if (p != null && File(p).existsSync()) {
              return ClipOval(
                child: Image(
                  image: FileImage(File(p)),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
              );
            }
            return ClipOval(
              child: Image.network(
                av,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => _initial(cs),
              ),
            );
          },
        );
      } else if (!kIsWeb && (av.startsWith('/') || av.contains(':'))) {
        final fixed = SandboxPathResolver.fix(av);
        final f = File(fixed);
        if (f.existsSync()) {
          return ClipOval(
            child: Image(
              image: FileImage(f),
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          );
        }
        return _initial(cs);
      } else {
        return _emoji(cs, av);
      }
    }
    return _initial(cs);
  }

  Widget _initial(ColorScheme cs) {
    final letter = item.name.isNotEmpty ? item.name.characters.first : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: cs.primary,
          fontWeight: AppFontWeights.emphasis,
          fontSize: size * 0.42,
        ),
      ),
    );
  }

  Widget _emoji(ColorScheme cs, String emoji) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        emoji.characters.take(1).toString(),
        style: TextStyle(fontSize: size * 0.5),
      ),
    );
  }
}

class _IosOutlineButton extends StatefulWidget {
  const _IosOutlineButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  State<_IosOutlineButton> createState() => _IosOutlineButtonState();
}

class _IosOutlineButtonState extends State<_IosOutlineButton> {
  bool _pressed = false;
  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) =>
          Future.delayed(const Duration(milliseconds: 80), () => _set(false)),
      onTapCancel: () => _set(false),
      onTap: () {
        Haptics.soft();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.primary.withValues(alpha: 0.5)),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: cs.primary,
              fontWeight: AppFontWeights.semibold,
            ),
          ),
        ),
      ),
    );
  }
}

class _IosFilledButton extends StatefulWidget {
  const _IosFilledButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  State<_IosFilledButton> createState() => _IosFilledButtonState();
}

class _IosFilledButtonState extends State<_IosFilledButton> {
  bool _pressed = false;
  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) =>
          Future.delayed(const Duration(milliseconds: 80), () => _set(false)),
      onTapCancel: () => _set(false),
      onTap: () {
        Haptics.soft();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: cs.onPrimary,
              fontWeight: AppFontWeights.semibold,
            ),
          ),
        ),
      ),
    );
  }
}
