import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/providers/settings_provider.dart';
import '../../home/services/tool_approval_service.dart';

class PhoneControlService {
  PhoneControlService._();

  static const _channel = MethodChannel('baizi.phone_control');
  static const _events = EventChannel('baizi.phone_control.events');
  static const toolName = 'phone_control';

  static bool get isSupported => Platform.isAndroid;

  static List<Map<String, dynamic>> buildToolDefinitions({
    required bool enabled,
    required bool supportsTools,
  }) {
    if (!enabled || !supportsTools || !isSupported) return const [];
    return const [
      {
        'type': 'function',
        'function': {
          'name': toolName,
          'description':
              'Control the user\'s Android phone after they explicitly enable phone control. '
              'Use get_status before privileged actions. Actions: get_status, get_ui_tree, tap, long_press, input_text, scroll, back, home, open_notifications, launch_app, list_apps, stop_app, set_volume, set_brightness, run_shell, file_operation. '
              'For tap/long_press use text or x/y. For file_operation use operation=list/read/delete/mkdir/move/copy/zip/unzip plus path and optional destination. '
              'Do not claim an action succeeded until this tool returns success.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': [
                  'get_status',
                  'get_ui_tree',
                  'tap',
                  'long_press',
                  'input_text',
                  'scroll',
                  'back',
                  'home',
                  'open_notifications',
                  'launch_app',
                  'list_apps',
                  'stop_app',
                  'set_volume',
                  'set_brightness',
                  'run_shell',
                  'file_operation',
                ],
              },
              'text': {'type': 'string'},
              'x': {'type': 'integer'},
              'y': {'type': 'integer'},
              'direction': {
                'type': 'string',
                'enum': ['forward', 'backward'],
              },
              'packageName': {'type': 'string'},
              'level': {'type': 'integer'},
              'command': {'type': 'string'},
              'operation': {'type': 'string'},
              'path': {'type': 'string'},
              'destination': {'type': 'string'},
            },
            'required': ['action'],
          },
        },
      },
    ];
  }

  static Future<String> execute({
    required Map<String, dynamic> arguments,
    required SettingsProvider settings,
    ToolApprovalService? approvalService,
  }) async {
    if (!isSupported) {
      return _error(
        'unsupported_platform',
        'Phone control is only available on Android.',
      );
    }
    if (!settings.phoneControlEnabled) {
      return _error(
        'phone_control_disabled',
        'Phone control is disabled in Advanced features.',
      );
    }
    final action = arguments['action']?.toString() ?? '';
    if (_needsApproval(action, settings.phoneControlConfirmationMode)) {
      if (approvalService == null) {
        return _error(
          'approval_unavailable',
          'User confirmation is unavailable for this phone action.',
        );
      }
      final id = '${toolName}_${DateTime.now().microsecondsSinceEpoch}';
      final decision = await approvalService.requestApproval(
        toolCallId: id,
        toolName: toolName,
        arguments: arguments,
      );
      if (!decision.approved) {
        return _error(
          'approval_denied',
          decision.denyReason ?? 'User denied the phone action.',
        );
      }
    }
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>(
            'execute',
            arguments,
          ) ??
          const <String, dynamic>{};
      return jsonEncode(result);
    } on PlatformException catch (error) {
      return _error(error.code, error.message ?? 'Phone control failed.');
    }
  }

  static Future<Map<String, dynamic>> getStatus() async {
    if (!isSupported) return const {'supported': false};
    final result = await _channel.invokeMapMethod<String, dynamic>('getStatus');
    return {'supported': true, ...?result};
  }

  static Stream<Map<String, dynamic>> get statusEvents => _events
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));

  static Future<Map<String, dynamic>> requestShizuku() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'requestShizuku',
    );
    return Map<String, dynamic>.from(result ?? const <String, dynamic>{});
  }

  static Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod('openAccessibilitySettings');

  static bool _needsApproval(String action, PhoneControlConfirmationMode mode) {
    if (mode == PhoneControlConfirmationMode.allowAll) {
      return false;
    }
    const observation = {
      'get_status',
      'get_ui_tree',
      'list_apps',
      'back',
      'home',
      'open_notifications',
    };
    if (mode == PhoneControlConfirmationMode.confirmAll) {
      return !observation.contains(action);
    }
    const highRisk = {
      'run_shell',
      'file_operation',
      'stop_app',
      'set_volume',
      'set_brightness',
      'input_text',
      'tap',
      'long_press',
      'launch_app',
    };
    return highRisk.contains(action);
  }

  static String _error(String code, String message) =>
      jsonEncode({'status': 'error', 'error': code, 'summary': message});
}
