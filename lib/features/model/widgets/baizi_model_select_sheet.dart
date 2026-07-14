import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/model_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../utils/brand_assets.dart';
import '../../../utils/model_grouping.dart';

Future<String?> showBaiziModelSelector(
  BuildContext context, {
  String? initialModelId,
}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * 0.86,
      child: SafeArea(
        top: false,
        child: _BaiziModelSheet(initialModelId: initialModelId),
      ),
    ),
  );
}

class BaiziModelBrowser extends StatefulWidget {
  const BaiziModelBrowser({
    super.key,
    required this.onSelected,
    this.selectedModelId,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16),
  });

  final ValueChanged<String> onSelected;
  final String? selectedModelId;
  final EdgeInsets padding;

  @override
  State<BaiziModelBrowser> createState() => _BaiziModelBrowserState();
}

class _BaiziModelBrowserState extends State<BaiziModelBrowser> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final query = _searchController.text.trim().toLowerCase();
    final models = settings.baiziModels
        .where((model) => query.isEmpty || model.toLowerCase().contains(query))
        .toList(growable: false);

    final sections = <_ModelSection>[];
    final featured = <String>{};
    if (query.isEmpty) {
      final favorites = models
          .where((model) => settings.isModelPinned('baizi', model))
          .toList(growable: false);
      if (favorites.isNotEmpty) {
        featured.addAll(favorites);
        sections.add(
          _ModelSection(l10n.modelSelectSheetFavoritesSection, favorites),
        );
      }
      final recent = settings.recentBaiziModels
          .where((model) => models.contains(model) && !featured.contains(model))
          .toList(growable: false);
      if (recent.isNotEmpty) {
        featured.addAll(recent);
        sections.add(_ModelSection(l10n.baiziModelRecent, recent));
      }
    }

    final grouped = <String, List<String>>{};
    for (final model in models.where((model) => !featured.contains(model))) {
      final info = ModelRegistry.infer(
        ModelInfo(id: model, displayName: model),
      );
      final group = ModelGrouping.groupFor(
        info,
        embeddingsLabel: l10n.providerDetailPageEmbeddingsGroupTitle,
        otherLabel: l10n.providerDetailPageOtherModelsGroupTitle,
      );
      grouped.putIfAbsent(group, () => <String>[]).add(model);
    }
    for (final entry in grouped.entries) {
      sections.add(_ModelSection(entry.key, entry.value));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.baiziModelSearchHint,
              prefixIcon: const Icon(Lucide.Search, size: 19),
              suffixIcon: query.isEmpty
                  ? null
                  : Tooltip(
                      message: l10n.baiziSetupClearTooltip,
                      child: IosIconButton(
                        icon: Lucide.X,
                        size: 18,
                        minSize: 40,
                        semanticLabel: l10n.baiziSetupClearTooltip,
                        onTap: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
                    ),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: sections.isEmpty
              ? _EmptyModels(hasQuery: query.isNotEmpty)
              : ListView.builder(
                  padding: widget.padding,
                  itemCount: sections.length,
                  itemBuilder: (context, sectionIndex) {
                    final section = sections[sectionIndex];
                    return _ModelSectionView(
                      section: section,
                      selectedModelId: widget.selectedModelId,
                      onSelected: widget.onSelected,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _BaiziModelSheet extends StatefulWidget {
  const _BaiziModelSheet({this.initialModelId});

  final String? initialModelId;

  @override
  State<_BaiziModelSheet> createState() => _BaiziModelSheetState();
}

class _BaiziModelSheetState extends State<_BaiziModelSheet> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await context.read<SettingsProvider>().refreshBaiziModels();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.baiziModelsLoadFailed),
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.baiziChooseModelTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Tooltip(
                message: l10n.baiziRefreshModels,
                child: IosIconButton(
                  size: 20,
                  minSize: 44,
                  semanticLabel: l10n.baiziRefreshModels,
                  enabled: !_refreshing,
                  onTap: _refresh,
                  builder: (color) => _refreshing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Lucide.RefreshCw, size: 20, color: color),
                ),
              ),
              Tooltip(
                message: MaterialLocalizations.of(context).closeButtonTooltip,
                child: IosIconButton(
                  icon: Lucide.X,
                  size: 20,
                  minSize: 44,
                  semanticLabel: MaterialLocalizations.of(
                    context,
                  ).closeButtonTooltip,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: BaiziModelBrowser(
            selectedModelId: widget.initialModelId,
            onSelected: (modelId) => Navigator.of(context).pop(modelId),
          ),
        ),
      ],
    );
  }
}

class _ModelSection {
  const _ModelSection(this.title, this.models);

  final String title;
  final List<String> models;
}

class _ModelSectionView extends StatelessWidget {
  const _ModelSectionView({
    required this.section,
    required this.selectedModelId,
    required this.onSelected,
  });

  final _ModelSection section;
  final String? selectedModelId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(
              section.title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.68),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (var index = 0; index < section.models.length; index++) ...[
                  _ModelRow(
                    modelId: section.models[index],
                    selected: section.models[index] == selectedModelId,
                    onSelected: onSelected,
                  ),
                  if (index != section.models.length - 1)
                    const Divider(height: 1, indent: 56),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.modelId,
    required this.selected,
    required this.onSelected,
  });

  final String modelId;
  final bool selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final pinned = settings.isModelPinned('baizi', modelId);
    final asset = BrandAssets.assetForName(modelId);
    final cs = Theme.of(context).colorScheme;
    return IosCardPress(
      onTap: () => onSelected(modelId),
      haptics: true,
      borderRadius: BorderRadius.zero,
      baseColor: selected
          ? cs.primaryContainer.withValues(alpha: 0.28)
          : Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 32,
                child: asset == null
                    ? Icon(Lucide.Bot, size: 20, color: cs.primary)
                    : Padding(
                        padding: const EdgeInsets.all(5),
                        child: SvgPicture.asset(asset),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  modelId,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              if (selected) Icon(Lucide.Check, size: 18, color: cs.primary),
              Tooltip(
                message: AppLocalizations.of(
                  context,
                )!.modelSelectSheetFavoriteTooltip,
                child: IosIconButton(
                  size: 18,
                  minSize: 44,
                  semanticLabel: AppLocalizations.of(
                    context,
                  )!.modelSelectSheetFavoriteTooltip,
                  color: pinned
                      ? cs.tertiary
                      : cs.onSurface.withValues(alpha: 0.45),
                  onTap: () => settings.togglePinModel('baizi', modelId),
                  builder: (color) => Icon(
                    Lucide.Star,
                    size: 18,
                    color: color,
                    fill: pinned ? 1 : 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyModels extends StatelessWidget {
  const _EmptyModels({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Lucide.SearchX : Lucide.Database,
              size: 32,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 12),
            Text(
              hasQuery ? l10n.baiziModelNoResults : l10n.baiziModelNoModels,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
