abstract final class BaiziBrand {
  static const String updateManifestAppId = 'baizi';

  // A dedicated Baizi release manifest has not been published yet.
  static const String? releaseManifestUrl = null;
  static const String? websiteUrl = null;

  static const String upstreamName = 'Kelivo';
  static const String upstreamRepositoryUrl =
      'https://github.com/Chevey339/kelivo';
  static const String licenseName = 'AGPL-3.0';
  static const String licenseUrl = '$upstreamRepositoryUrl/blob/master/LICENSE';

  static bool isKelivoReleaseUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'kelivo.psycheas.top') return true;

    final path = uri.path.toLowerCase();
    return host == 'github.com' &&
        (path == '/chevey339/kelivo' || path.startsWith('/chevey339/kelivo/'));
  }
}
