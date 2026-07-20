import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/menstrual_care_provider.dart';
import '../../../core/models/menstrual_care.dart';
import '../../../l10n/app_localizations.dart';

class MenstrualCarePage extends StatefulWidget {
  const MenstrualCarePage({super.key});
  @override
  State<MenstrualCarePage> createState() => _MenstrualCarePageState();
}

class _MenstrualCarePageState extends State<MenstrualCarePage> {
  late final TextEditingController _cycle = TextEditingController(text: '28');
  late final TextEditingController _period = TextEditingController(text: '5');
  DateTime _start = DateTime.now();
  @override
  void dispose() {
    _cycle.dispose();
    _period.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (value != null) setState(() => _start = value);
  }

  Future<void> _save() async {
    final cycle = int.tryParse(_cycle.text);
    final period = int.tryParse(_period.text);
    if (cycle == null || period == null) return;
    try {
      await context.read<MenstrualCareProvider>().configure(
        lastStartDate: _start,
        cycleDays: cycle,
        periodDays: period,
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入 21-45 天周期与 1-14 天经期。')),
        );
    }
  }

  Future<void> _recordStart() async {
    try {
      await context.read<MenstrualCareProvider>().recordStart(DateTime.now());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已记录今天为经期开始日。')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('记录失败，请稍后重试。')));
      }
    }
  }

  Future<void> _recordEnd() async {
    try {
      final recorded = await context.read<MenstrualCareProvider>().recordEnd(
        DateTime.now(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(recorded ? '已记录今天为经期结束日。' : '还没有可结束的经期记录。')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('记录失败，请稍后重试。')));
      }
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重置经期关怀？'),
        content: const Text('这会清除本机的周期记录和提醒设置，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<MenstrualCareProvider>().clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('经期关怀已重置。')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('重置失败，请稍后重试。')));
      }
    }
  }

  String _phase(MenstrualPhase phase) => switch (phase) {
    MenstrualPhase.period => '经期中',
    MenstrualPhase.postPeriod => '经期后',
    MenstrualPhase.ovulationWindow => '排卵期附近（估算）',
    MenstrualPhase.prePeriod => '经期前',
    MenstrualPhase.expectedStart => '预计今天开始',
    MenstrualPhase.delayed => '可能延迟',
    MenstrualPhase.unknown => '等待记录',
  };
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final care = context.watch<MenstrualCareProvider>();
    final profile = care.profile;
    final status = care.status;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.menstrualCareTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (profile == null) ...[
            Text(
              l10n.menstrualCareSubtitle,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.menstrualCareLastStart),
              subtitle: Text(
                '${_start.year}-${_start.month.toString().padLeft(2, '0')}-${_start.day.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.calendar_month),
              onTap: _pickDate,
            ),
            TextField(
              controller: _cycle,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.menstrualCareCycleDays,
              ),
            ),
            TextField(
              controller: _period,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.menstrualCarePeriodDays,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: Text(l10n.menstrualCareSetup),
            ),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status == null ? '' : _phase(status.phase),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      status == null
                          ? ''
                          : '预计下次开始：${status.expectedStartDate.year}-${status.expectedStartDate.month}-${status.expectedStartDate.day}',
                    ),
                    if (status?.irregular == true)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('最近周期可能不规律，持续明显异常或不适时建议咨询医生。'),
                      ),
                  ],
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.menstrualCareContext),
              value: profile.contextEnabled,
              onChanged: (v) => care.updateSettings(contextEnabled: v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.menstrualCareAutoRecord),
              value: profile.autoRecordEnabled,
              onChanged: (v) => care.updateSettings(autoRecordEnabled: v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('本地提醒'),
              subtitle: const Text('仅显示私密提示，不会后台调用 AI'),
              value: profile.remindersEnabled,
              onChanged: (v) => care.updateSettings(remindersEnabled: v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _recordStart,
                    child: const Text('今天开始'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _recordEnd,
                    child: const Text('今天结束'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _reset, child: const Text('重置经期关怀')),
            ),
            Text(
              l10n.menstrualCarePrivacy,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
