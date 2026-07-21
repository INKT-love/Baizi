import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../services/phone_control_service.dart';

class PhoneControlPage extends StatefulWidget {
  const PhoneControlPage({super.key});

  @override
  State<PhoneControlPage> createState() => _PhoneControlPageState();
}

class _PhoneControlPageState extends State<PhoneControlPage>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _status;
  bool _checking = false;
  StreamSubscription<Map<String, dynamic>>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statusSubscription = PhoneControlService.statusEvents.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() => _checking = true);
    try {
      _status = await PhoneControlService.getStatus();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _setEnabled(bool value) async {
    final settings = context.read<SettingsProvider>();
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('启用手机控制'),
          content: const Text(
            '白子将根据你选择的授权方式操作手机。请先完成 Shizuku 或 Root 与无障碍服务配置。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('启用'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await settings.setPhoneControlEnabled(value);
  }

  Future<void> _setMode(PhoneControlConfirmationMode mode) async {
    final settings = context.read<SettingsProvider>();
    if (mode == PhoneControlConfirmationMode.allowAll) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('开启全部允许？'),
          content: const Text(
            '开启后，白子执行已注册的手机工具时不再逐项询问，包括删除文件、Shell 命令和系统设置修改。系统安全页面仍不会被绕过。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认开启'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await settings.setPhoneControlConfirmationMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (!Platform.isAndroid) {
      return const Scaffold(body: Center(child: Text('手机控制仅支持 Android。')));
    }
    final status = _status ?? const <String, dynamic>{};
    return Scaffold(
      appBar: AppBar(title: const Text('手机控制')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SwitchListTile.adaptive(
            secondary: const Icon(Lucide.Bot),
            title: const Text('启用手机控制'),
            subtitle: const Text('关闭后 AI 不会获得任何手机控制工具'),
            value: settings.phoneControlEnabled,
            onChanged: _setEnabled,
          ),
          const SizedBox(height: 16),
          _section('授权状态'),
          _card([
            _statusRow(
              'Shizuku（推荐）',
              status['shizukuGranted'] == true
                  ? '已授权'
                  : status['shizukuRunning'] == true
                  ? '等待授权'
                  : '未运行',
              status['shizukuGranted'] == true,
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('连接 Shizuku'),
              subtitle: const Text('优先使用，适合大多数系统操作'),
              trailing: const Icon(Lucide.ChevronRight),
              onTap: () async {
                final result = await PhoneControlService.requestShizuku();
                if (mounted) setState(() => _status = result);
              },
            ),
            const Divider(height: 1),
            _statusRow(
              'Root',
              status['rootAvailable'] == true ? '可用' : '不可用',
              status['rootAvailable'] == true,
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('无障碍服务'),
              subtitle: Text(
                status['accessibilityEnabled'] == true
                    ? '已开启，可读取和操作界面'
                    : '未开启，界面自动化不可用',
              ),
              trailing: const Icon(Lucide.ChevronRight),
              onTap: () async {
                await PhoneControlService.openAccessibilitySettings();
                await _refresh();
              },
            ),
            if (_checking) const LinearProgressIndicator(),
            ListTile(
              leading: const Icon(Lucide.RefreshCw),
              title: const Text('重新检查授权'),
              onTap: _refresh,
            ),
          ]),
          const SizedBox(height: 16),
          _section('确认方式'),
          _card(
            PhoneControlConfirmationMode.values
                .map(
                  (mode) => RadioListTile<PhoneControlConfirmationMode>(
                    value: mode,
                    groupValue: settings.phoneControlConfirmationMode,
                    onChanged: (value) {
                      if (value != null) _setMode(value);
                    },
                    title: Text(switch (mode) {
                      PhoneControlConfirmationMode.riskBased => '按风险确认',
                      PhoneControlConfirmationMode.confirmAll => '全部确认',
                      PhoneControlConfirmationMode.allowAll => '全部允许',
                    }),
                    subtitle: Text(switch (mode) {
                      PhoneControlConfirmationMode.riskBased =>
                        '观察和安全导航直接执行，高风险动作询问',
                      PhoneControlConfirmationMode.confirmAll => '每次改变手机状态前都询问',
                      PhoneControlConfirmationMode.allowAll =>
                        '开启时确认一次，之后不再逐项询问',
                    }),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          _section('说明'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '白子会优先使用 Shizuku，Root 作为补充；无障碍服务用于读取当前界面、点击、输入和滚动。锁屏、支付验证和系统保护页会暂停等待你接手。',
            ),
          ),
          if (status['shizukuAuthorizationState'] == 'pending')
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('正在等待 Shizuku 授权，请在弹窗中允许。'),
            ),
          if (status['shizukuAuthorizationState'] == 'denied' ||
              status['shizukuAuthorizationState'] == 'request_failed')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                status['shizukuAuthorizationState'] == 'denied'
                    ? 'Shizuku 授权被拒绝，请重新连接。'
                    : '无法发起 Shizuku 授权：${status['shizukuAuthorizationMessage'] ?? '请确认 Shizuku 已运行'}',
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(String value) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
  Widget _card(List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
  Widget _statusRow(String title, String status, bool ok) => ListTile(
    title: Text(title),
    trailing: Text(
      status,
      style: TextStyle(
        color: ok
            ? Colors.green
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
