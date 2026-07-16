abstract final class BaiziBrand {
  static const String updateManifestAppId = 'baizi';

  static const String releaseManifestUrl =
      'https://github.com/INKT-love/Baizi/releases/latest';
  static const String? websiteUrl = null;

  static const String upstreamName = 'Baizi';
  static const String upstreamRepositoryUrl =
      'https://github.com/INKT-love/Baizi';
  static const String licenseName = 'AGPL-3.0';
  static const String licenseUrl = '$upstreamRepositoryUrl/blob/main/LICENSE';

  static bool isKelivoReleaseUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'kelivo.psycheas.top') return true;

    final path = uri.path.toLowerCase();
    return host == 'github.com' &&
        (path == '/chevey339/kelivo' || path.startsWith('/chevey339/kelivo/'));
  }
}
