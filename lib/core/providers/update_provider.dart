import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config/baizi_brand.dart';

enum UpdateCheckStatus {
  disabled,
  idle,
  checking,
  upToDate,
  updateAvailable,
  failed,
}

typedef CurrentVersionLoader = Future<String> Function();

class UpdateInfo {
  final String app;
  final String version;
  final int? build;
  final DateTime? releasedAt;
  final String? notes;
  final bool mandatory;
  final Map<String, String> downloads;

  const UpdateInfo({
    required this.app,
    required this.version,
    this.build,
    this.releasedAt,
    this.notes,
    this.mandatory = false,
    this.downloads = const {},
  });

  String? bestDownloadUrl() {
    if (Platform.isIOS) {
      return downloads['ios'] ??
          downloads['iosAppStore'] ??
          downloads['universal'];
    }
    if (Platform.isAndroid) {
      return downloads['android'] ?? downloads['universal'];
    }
    if (Platform.isMacOS) {
      return downloads['macos'] ??
          downloads['mac'] ??
          downloads['darwin'] ??
          downloads['universal'];
    }
    if (Platform.isWindows) {
      return downloads['windows'] ?? downloads['win'] ?? downloads['universal'];
    }
    if (Platform.isLinux) {
      return downloads['linux'] ?? downloads['universal'];
    }
    return downloads['universal'] ?? downloads['android'] ?? downloads['ios'];
  }

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final latest = (json['latest'] as Map?) ?? const {};
    final downloads =
        (latest['downloads'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        const {};
    DateTime? released;
    final releasedRaw = latest['releasedAt']?.toString();
    if (releasedRaw != null && releasedRaw.isNotEmpty) {
      try {
        released = DateTime.parse(releasedRaw);
      } catch (_) {}
    }
    return UpdateInfo(
      app: (json['app'] ?? '').toString(),
      version: (latest['version'] ?? '').toString(),
      build: int.tryParse((latest['build'] ?? '').toString()),
      releasedAt: released,
      notes: (latest['notes'] ?? '').toString(),
      mandatory: (latest['mandatory'] as bool?) ?? false,
      downloads: downloads,
    );
  }
}

class UpdateProvider extends ChangeNotifier {
  UpdateProvider({
    String? releaseManifestUrl = BaiziBrand.releaseManifestUrl,
    http.Client? client,
    CurrentVersionLoader? currentVersionLoader,
  }) : _releaseManifestUri = _parseManifestUri(releaseManifestUrl),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _currentVersionLoader =
           currentVersionLoader ?? _loadCurrentVersionFromPlatform,
       _status = _parseManifestUri(releaseManifestUrl) == null
           ? UpdateCheckStatus.disabled
           : UpdateCheckStatus.idle;

  final Uri? _releaseManifestUri;
  final http.Client _client;
  final bool _ownsClient;
  final CurrentVersionLoader _currentVersionLoader;

  UpdateInfo? _available;
  UpdateInfo? get available => _available;
  bool _checking = false;
  bool get checking => _checking;
  String? _error;
  String? get error => _error;
  UpdateCheckStatus _status;
  UpdateCheckStatus get status => _status;
  bool get isEnabled => _releaseManifestUri != null;

  Future<void> checkForUpdates() async {
    if (!isEnabled) {
      _available = null;
      _error = null;
      _checking = false;
      _status = UpdateCheckStatus.disabled;
      return;
    }
    if (_checking) return;
    _checking = true;
    _available = null;
    _error = null;
    _status = UpdateCheckStatus.checking;
    notifyListeners();
    try {
      final source = _releaseManifestUri!;
      if (BaiziBrand.isKelivoReleaseUri(source)) {
        throw StateError('Kelivo release manifests are not valid for Baizi');
      }
      final url = source.replace(
        queryParameters: <String, String>{
          ...source.queryParameters,
          'baizi': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final resp = await _client.get(url);
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final info = UpdateInfo.fromJson(data);
      _validateManifest(info);

      final currentVer = await _currentVersionLoader();

      // Compare by version only; ignore build numbers
      final hasNew = _isRemoteNewer(
        remoteVersion: info.version,
        currentVersion: currentVer,
      );
      _available = hasNew ? info : null;
      _status = hasNew
          ? UpdateCheckStatus.updateAvailable
          : UpdateCheckStatus.upToDate;
    } catch (e) {
      _error = e.toString();
      _status = UpdateCheckStatus.failed;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  bool _isRemoteNewer({
    required String remoteVersion,
    required String currentVersion,
  }) {
    // Compare semantic versions only (ignore internal build numbers)
    List<int> parseVer(String v) {
      final parts = v.split('.');
      final nums = <int>[];
      for (int i = 0; i < 3; i++) {
        nums.add(i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
      }
      return nums;
    }

    final a = parseVer(remoteVersion);
    final b = parseVer(currentVersion);
    if (a[0] != b[0]) return a[0] > b[0];
    if (a[1] != b[1]) return a[1] > b[1];
    if (a[2] != b[2]) return a[2] > b[2];
    return false;
  }

  static Uri? _parseManifestUri(String? rawUrl) {
    final trimmed = rawUrl?.trim() ?? '';
    return trimmed.isEmpty ? null : Uri.parse(trimmed);
  }

  static Future<String> _loadCurrentVersionFromPlatform() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  static void _validateManifest(UpdateInfo info) {
    if (info.app.trim().toLowerCase() != BaiziBrand.updateManifestAppId) {
      throw const FormatException('Unexpected update manifest app for Baizi');
    }
    for (final rawUrl in info.downloads.values) {
      final uri = Uri.tryParse(rawUrl);
      if (uri != null && BaiziBrand.isKelivoReleaseUri(uri)) {
        throw const FormatException(
          'Kelivo download URLs are not valid for Baizi',
        );
      }
    }
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
