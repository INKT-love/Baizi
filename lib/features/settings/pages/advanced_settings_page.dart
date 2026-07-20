import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../instruction_injection/pages/instruction_injection_page.dart';
import '../../mcp/pages/mcp_page.dart';
import '../../model/pages/default_model_page.dart';
import '../../quick_phrase/pages/quick_phrases_page.dart';
import '../../search/pages/search_services_page.dart';
import '../../world_book/pages/world_book_page.dart';
import 'log_viewer_page.dart';
import 'network_proxy_page.dart';
import 'storage_space_page.dart';
import 'tts_services_page.dart';
import 'menstrual_care_page.dart';
import '../../phone_control/pages/phone_control_page.dart';

class AdvancedSettingsPage extends StatelessWidget {
  const AdvancedSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final destinations = <_AdvancedDestination>[
      _AdvancedDestination(
        icon: Lucide.Bot,
        label: '手机控制',
        page: const PhoneControlPage(),
      ),
      _AdvancedDestination(
        icon: Lucide.Calendar,
        label: l10n.menstrualCareTitle,
        page: const MenstrualCarePage(),
      ),
      _AdvancedDestination(
        icon: Lucide.SlidersHorizontal,
        label: l10n.settingsPageDefaultModel,
        page: const DefaultModelPage(),
      ),
      _AdvancedDestination(
        icon: Lucide.Earth,
        label: l10n.settingsPageSearch,
        page: const SearchServicesPage(),
      ),
      _AdvancedDestination(
        icon: Lucide.Volume2,
        label: l10n.settingsPageTts,
        page: const TtsServicesPage(),
      ),
      _AdvancedDestination(
        icon: Lucide.Terminal,
        label: l10n.settingsPageMcp,
        page: const McpPage(),
      ),
      _AdvancedDestination(
        icon: Lucide.BookOpen,
        label: l10n.settingsPageWorldBook,
        page: const WorldBookPage(),
      ),
      _AdvancedDestination(
        icon: Lucide.Zap,
        label: l10n.settingsPageQuickPhrase,
        page: const QuickPhrasesPage(),
      ),
      _AdvancedDestination(
        icon: Lucide.Layers,
        label: l10n.settingsPageInstructionInjection,
        page: const InstructionInjectionPage(),
      ),
      _AdvancedDestination(
        icon: Lucide.EthernetPort,
        label: l10n.settingsPageNetworkProxy,
        page: const NetworkProxyPage(),
      ),
      _AdvancedDestination(
        icon: Lucide.HardDrive,
        label: l10n.settingsPageChatStorage,
        page: const StorageSpacePage(),
      ),
      _AdvancedDestination(
        icon: Lucide.FileText,
        label: l10n.settingsPageLogs,
        page: const LogViewerPage(),
      ),
    ];

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
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.settingsPageAdvancedFeatures),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: destinations.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
        itemBuilder: (context, index) {
          final item = destinations[index];
          return IosCardPress(
            borderRadius: BorderRadius.zero,
            baseColor: Colors.transparent,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => item.page)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 54),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(item.icon, size: 21),
                    const SizedBox(width: 20),
                    Expanded(child: Text(item.label)),
                    const Icon(Lucide.ChevronRight, size: 18),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AdvancedDestination {
  const _AdvancedDestination({
    required this.icon,
    required this.label,
    required this.page,
  });

  final IconData icon;
  final String label;
  final Widget page;
}
