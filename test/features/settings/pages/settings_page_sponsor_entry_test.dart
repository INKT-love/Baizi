import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile settings page does not expose the sponsor entry', () async {
    final source = await File(
      'lib/features/settings/pages/settings_page.dart',
    ).readAsString();

    expect(source, isNot(contains("import 'sponsor_page.dart';")));
    expect(source, isNot(contains('const SponsorPage()')));
    expect(source, isNot(contains('label: l10n.settingsPageSponsor')));
  });
}
