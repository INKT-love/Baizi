import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/menstrual_care.dart';

class MenstrualCareStore {
  MenstrualCareStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'baizi_menstrual_care',
              resetOnError: false,
              migrateWithBackup: false,
            ),
          );
  static const _key = 'profile_v1';
  final FlutterSecureStorage _storage;
  Future<MenstrualCareProfile?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    final json = jsonDecode(raw);
    if (json is! Map)
      throw const FormatException('Invalid menstrual care data');
    return MenstrualCareProfile.fromJson(Map<String, dynamic>.from(json));
  }

  Future<void> write(MenstrualCareProfile value) =>
      _storage.write(key: _key, value: jsonEncode(value.toJson()));
  Future<void> clear() => _storage.delete(key: _key);
}
