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
    String? firstAvailable(List<String> keys) {
      for (final key in keys) {
        final value = downloads[key]?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    if (Platform.isIOS) {
      return firstAvailable(['ios', 'iosAppStore', 'universal']);
    }
    if (Platform.isAndroid) {
      return firstAvailable([
        'android',
        'androidUniversal',
        'androidApk',
        'androidArm64',
        'android-arm64',
        'arm64-v8a',
        'androidArm32',
        'android-arm32',
        'armeabi-v7a',
        'androidX64',
        'android-x64',
        'x86_64',
        'apk',
        'universal',
      ]);
    }
    if (Platform.isMacOS) {
      return firstAvailable(['macos', 'mac', 'darwin', 'universal']);
    }
    if (Platform.isWindows) {
      return firstAvailable(['windows', 'win', 'universal']);
    }
    if (Platform.isLinux) {
      return firstAvailable(['linux', 'universal']);
    }
    return firstAvailable(['universal', 'android', 'ios']);
  }

  factory UpdateInfo.fromJson(Map<String, dynamic> json, {Uri? sourceUri}) {
    final latest = (json['latest'] as Map?) ?? const {};
    final downloads =
        (latest['downloads'] as Map?)?.map(
          (k, v) => MapEntry(
            k.toString(),
            _normalizeDownloadUrl(v.toString(), sourceUri),
          ),
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

  static String _normalizeDownloadUrl(String rawUrl, Uri? sourceUri) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || sourceUri == null) return trimmed;
    final resolved = uri.hasScheme ? uri : sourceUri.resolve(trimmed);
    if (resolved.scheme == sourceUri.scheme &&
        resolved.host.toLowerCase() == sourceUri.host.toLowerCase() &&
        !resolved.hasPort &&
        sourceUri.hasPort) {
      return resolved.replace(port: sourceUri.port).toString();
    }
    return resolved.toString();
  }

  factory UpdateInfo.fromGitHubReleasePageUri(Uri releasePageUri) {
    return UpdateInfo(
      app: BaiziBrand.updateManifestAppId,
      version: releasePageUri.pathSegments.lastOrNull ?? '',
      downloads: <String, String>{'universal': releasePageUri.toString()},
    );
  }
}

class UpdateProvider extends ChangeNotifier {
  UpdateProvider({
    String? releaseManifestUrl = BaiziBrand.releaseManifestUrl,
    http.Client? client,
    CurrentVersionLoader? currentVersionLoader,
  }) : _releaseManifestUris = _parseManifestUris(releaseManifestUrl),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _currentVersionLoader =
           currentVersionLoader ?? _loadCurrentVersionFromPlatform,
       _status = _parseManifestUris(releaseManifestUrl).isEmpty
           ? UpdateCheckStatus.disabled
           : UpdateCheckStatus.idle;

  final List<Uri> _releaseManifestUris;
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
  bool get isEnabled => _releaseManifestUris.isNotEmpty;

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
      Object? lastError;
      for (final source in _releaseManifestUris) {
        try {
          final info = await _loadUpdateInfo(source);
          _validateManifest(info);
          await _finishCheck(info);
          return;
        } catch (e) {
          lastError = e;
        }
      }
      throw lastError ?? StateError('No Baizi update sources are configured');
    } catch (e) {
      _error = e.toString();
      _status = UpdateCheckStatus.failed;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<UpdateInfo> _loadUpdateInfo(Uri source) async {
    if (BaiziBrand.isKelivoReleaseUri(source)) {
      throw StateError('Kelivo release manifests are not valid for Baizi');
    }
    if (_isOpenListManifestApiUri(source)) {
      return _loadOpenListManifest(source);
    }
    if (_isGitHubLatestReleaseUri(source)) {
      return _loadGitHubLatestRelease(source);
    }

    final url = _withCacheBuster(source);
    final resp = await _client.get(url);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final data =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return UpdateInfo.fromJson(data, sourceUri: url);
  }

  Future<UpdateInfo> _loadOpenListManifest(Uri source) async {
    final manifestPath =
        source.queryParameters['path'] ?? BaiziBrand.openListManifestPath;
    final apiUri = _withoutQueryAndFragment(source);
    final resp = await _client.post(
      apiUri,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(<String, Object>{'path': manifestPath, 'password': ''}),
    );
    if (resp.statusCode != 200) {
      throw Exception('OpenList HTTP ${resp.statusCode}');
    }
    final payload =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final code = int.tryParse((payload['code'] ?? '').toString());
    if (code != 200) {
      throw Exception('OpenList ${payload['message'] ?? 'request failed'}');
    }
    final data = payload['data'];
    if (data is! Map) {
      throw const FormatException('OpenList manifest file data is missing');
    }

    final rawManifestUrl = _openListRawUrl(
      apiUri: apiUri,
      filePath: manifestPath,
      fileData: data,
    );
    final manifestUri = _withCacheBuster(rawManifestUrl);
    final manifestResp = await _client.get(manifestUri);
    if (manifestResp.statusCode != 200) {
      throw Exception('Manifest HTTP ${manifestResp.statusCode}');
    }
    final manifestData =
        jsonDecode(utf8.decode(manifestResp.bodyBytes)) as Map<String, dynamic>;
    return UpdateInfo.fromJson(manifestData, sourceUri: manifestUri);
  }

  Future<UpdateInfo> _loadGitHubLatestRelease(Uri source) async {
    final request = http.Request('GET', source)
      ..followRedirects = false
      ..maxRedirects = 0;
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    if (response.statusCode < 300 || response.statusCode >= 400) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final location = response.headers['location'];
    if (location == null || location.isEmpty) {
      throw const FormatException('GitHub release location is missing');
    }
    return UpdateInfo.fromGitHubReleasePageUri(source.resolve(location));
  }

  Uri _openListRawUrl({
    required Uri apiUri,
    required String filePath,
    required Map<dynamic, dynamic> fileData,
  }) {
    final rawUrl = (fileData['raw_url'] ?? fileData['rawUrl'])?.toString();
    if (rawUrl != null && rawUrl.trim().isNotEmpty) {
      final rawUri = apiUri.resolve(rawUrl.trim());
      if (rawUri.scheme == apiUri.scheme &&
          rawUri.host.toLowerCase() == apiUri.host.toLowerCase() &&
          !rawUri.hasPort &&
          apiUri.hasPort) {
        return rawUri.replace(port: apiUri.port);
      }
      return rawUri;
    }

    final sign = fileData['sign']?.toString();
    final encodedPath = filePath.split('/').map(Uri.encodeComponent).join('/');
    return apiUri.replace(
      path: '/d$encodedPath',
      queryParameters: sign == null || sign.isEmpty
          ? null
          : <String, String>{'sign': sign},
      fragment: null,
    );
  }

  Uri _withCacheBuster(Uri source) {
    return source.replace(
      queryParameters: <String, String>{
        ...source.queryParameters,
        'baizi': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
  }

  Uri _withoutQueryAndFragment(Uri source) {
    return Uri(
      scheme: source.scheme,
      userInfo: source.userInfo,
      host: source.host,
      port: source.hasPort ? source.port : null,
      path: source.path,
    );
  }

  static List<Uri> _parseManifestUris(String? rawUrl) {
    final trimmed = rawUrl?.trim() ?? '';
    if (trimmed.isEmpty) return const [];
    final sources = trimmed == BaiziBrand.releaseManifestUrl
        ? BaiziBrand.releaseManifestUrls
        : <String>[trimmed];
    return sources.map(Uri.parse).toList(growable: false);
  }

  static bool _isOpenListManifestApiUri(Uri uri) {
    final configured = Uri.parse(BaiziBrand.openListManifestApiUrl);
    return uri.scheme == configured.scheme &&
        uri.host.toLowerCase() == configured.host.toLowerCase() &&
        uri.port == configured.port &&
        uri.path == configured.path;
  }

  Future<void> _finishCheck(UpdateInfo info) async {
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
  }

  bool _isRemoteNewer({
    required String remoteVersion,
    required String currentVersion,
  }) {
    // Compare semantic versions only (ignore internal build numbers)
    List<int> parseVer(String v) {
      final normalized = v.trim().replaceFirst(RegExp(r'^[vV]'), '');
      final parts = normalized.split('.');
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

  static bool _isGitHubLatestReleaseUri(Uri uri) {
    return uri.host.toLowerCase() == 'github.com' &&
        uri.path.toLowerCase() == '/inkt-love/baizi/releases/latest';
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
