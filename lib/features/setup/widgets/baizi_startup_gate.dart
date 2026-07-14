import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_primary_button.dart';
import '../pages/baizi_setup_page.dart';

class BaiziStartupGate extends StatelessWidget {
  const BaiziStartupGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (!settings.isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (settings.initializationError != null ||
        settings.apiKeyStorageError != null) {
      return const _StartupErrorPage();
    }
    if (!settings.hasCompleteBaiziSetup) {
      return const BaiziSetupPage();
    }
    return child;
  }
}

class _StartupErrorPage extends StatefulWidget {
  const _StartupErrorPage();

  @override
  State<_StartupErrorPage> createState() => _StartupErrorPageState();
}

class _StartupErrorPageState extends State<_StartupErrorPage> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await context.read<SettingsProvider>().retryInitialization();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Lucide.ShieldAlert, size: 38, color: cs.error),
                  const SizedBox(height: 18),
                  Text(
                    l10n.baiziStartupErrorTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.baiziStartupErrorMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.68),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  IosPrimaryButton(
                    label: l10n.baiziRetry,
                    icon: Lucide.RefreshCw,
                    loading: _retrying,
                    onTap: _retrying ? null : _retry,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
