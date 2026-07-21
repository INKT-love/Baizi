import 'package:flutter_test/flutter_test.dart';

import 'package:Baizi/core/config/baizi_brand.dart';

void main() {
  test('uses the Baizi GitHub repository for brand links', () {
    expect(BaiziBrand.upstreamName, 'Baizi');
    expect(
      BaiziBrand.upstreamRepositoryUrl,
      'https://github.com/INKT-love/Baizi',
    );
    expect(
      BaiziBrand.licenseUrl,
      'https://github.com/INKT-love/Baizi/blob/main/LICENSE',
    );
  });
}
