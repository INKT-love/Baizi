import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  test('Android release build uses Baizi branding and R8 shrinking', () async {
    final buildGradle = await File(
      'android/app/build.gradle.kts',
    ).readAsString();
    final applicationId = RegExp(
      r'^\s*applicationId\s*=\s*"([^"]+)"\s*$',
      multiLine: true,
    ).firstMatch(buildGradle)?.group(1);

    final manifest = XmlDocument.parse(
      await File('android/app/src/main/AndroidManifest.xml').readAsString(),
    );
    final application = manifest.findAllElements('application').single;
    final label = application.getAttribute(
      'label',
      namespace: 'http://schemas.android.com/apk/res/android',
    );

    expect(applicationId, 'top.inktandwkx.baizi');
    expect(label, '白子');
    expect(buildGradle, contains('isMinifyEnabled = true'));
    expect(buildGradle, contains('isShrinkResources = true'));
    expect(buildGradle, contains('proguard-android-optimize.txt'));
  });
}
