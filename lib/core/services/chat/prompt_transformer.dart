import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../../models/assistant.dart';

class PromptTransformer {
  static String replaceCharacterCardPlaceholders(
    String text, {
    required String characterName,
    required String userNickname,
  }) {
    return text
        .replaceAll(
          RegExp(r'\{\{\s*char\s*\}\}', caseSensitive: false),
          characterName,
        )
        .replaceAll(
          RegExp(r'\{\{\s*user\s*\}\}', caseSensitive: false),
          userNickname,
        );
  }

  static String buildCharacterCardSystemPrompt(
    Assistant assistant, {
    required String userNickname,
  }) {
    final card = assistant.characterData;
    final sections = <String>[
      if (assistant.systemPrompt.trim().isNotEmpty)
        assistant.systemPrompt.trim(),
      if (card?.systemPrompt.trim().isNotEmpty == true)
        card!.systemPrompt.trim(),
      if (card?.description.trim().isNotEmpty == true)
        '<character_description>\n${card!.description.trim()}\n</character_description>',
      if (card?.personality.trim().isNotEmpty == true)
        '<personality>\n${card!.personality.trim()}\n</personality>',
      if (card?.scenario.trim().isNotEmpty == true)
        '<scenario>\n${card!.scenario.trim()}\n</scenario>',
      if (card?.mesExample.trim().isNotEmpty == true)
        '<example_dialogue>\n${card!.mesExample.trim()}\n</example_dialogue>',
    ];
    return replaceCharacterCardPlaceholders(
      sections.join('\n\n'),
      characterName: assistant.name,
      userNickname: userNickname,
    );
  }

  static String buildCharacterCardPostHistoryInstructions(
    Assistant assistant, {
    required String userNickname,
  }) {
    final raw = assistant.characterData?.postHistoryInstructions.trim() ?? '';
    return replaceCharacterCardPlaceholders(
      raw,
      characterName: assistant.name,
      userNickname: userNickname,
    );
  }

  static Map<String, String> buildPlaceholders({
    required BuildContext context,
    required Assistant assistant,
    required String? modelId,
    required String? modelName,
    required String userNickname,
  }) {
    final now = DateTime.now();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final tz = now.timeZoneName;
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dt = '$date $time';
    final os = Platform.operatingSystem;
    final osv = Platform.operatingSystemVersion;
    final device =
        os; // Simple fallback; can be extended with device_info plugins
    final battery = 'unknown';

    return <String, String>{
      '{cur_date}': date,
      '{cur_time}': time,
      '{cur_datetime}': dt,
      '{model_id}': modelId ?? '',
      '{model_name}': modelName ?? (modelId ?? ''),
      '{locale}': locale,
      '{timezone}': tz,
      '{system_version}': '$os $osv',
      '{device_info}': device,
      '{battery_level}': battery,
      '{nickname}': userNickname,
      '{assistant_name}': assistant.name,
    };
  }

  static String replacePlaceholders(String text, Map<String, String> vars) {
    var out = text;
    vars.forEach((k, v) {
      out = out.replaceAll(k, v);
    });
    return out;
  }

  // Very simple mustache-like replacement for message template variables
  // Supported: {{ role }}, {{ message }}, {{ time }}, {{ date }}
  static String applyMessageTemplate(
    String template, {
    required String role,
    required String message,
    required DateTime now,
  }) {
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final vars = <String, String>{
      'role': role,
      'message': message,
      'time': time,
      'date': date,
    };

    return template.replaceAllMapped(RegExp(r'{{\s*(\w+)\s*}}'), (match) {
      final key = match.group(1);
      return key != null && vars.containsKey(key)
          ? vars[key]!
          : match.group(0) ?? '';
    });
  }
}
