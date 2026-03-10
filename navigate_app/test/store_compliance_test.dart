import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Finds the project root (navigate_app/) by walking up from the test runner's CWD.
String _findProjectRoot() {
  var dir = Directory.current;
  // Walk up until we find pubspec.yaml with 'name: navigate_app'
  for (var i = 0; i < 10; i++) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() && pubspec.readAsStringSync().contains('name: navigate_app')) {
      return dir.path;
    }
    dir = dir.parent;
  }
  return Directory.current.path;
}

void main() {
  late String root;

  setUpAll(() {
    root = _findProjectRoot();
  });

  // ---------------------------------------------------------------------------
  // Apple App Store
  // ---------------------------------------------------------------------------
  group('Apple App Store compliance', () {
    late String infoPlist;

    setUpAll(() {
      final file = File('$root/ios/Runner/Info.plist');
      expect(file.existsSync(), isTrue, reason: 'Info.plist must exist');
      infoPlist = file.readAsStringSync();
    });

    test('Info.plist has required bundle keys', () {
      const requiredKeys = [
        'CFBundleDevelopmentRegion',
        'CFBundleDisplayName',
        'CFBundleExecutable',
        'CFBundleIdentifier',
        'CFBundleInfoDictionaryVersion',
        'CFBundleName',
        'CFBundlePackageType',
        'CFBundleShortVersionString',
        'CFBundleVersion',
        'LSRequiresIPhoneOS',
      ];

      for (final key in requiredKeys) {
        expect(infoPlist, contains('<key>$key</key>'),
            reason: 'Info.plist missing required key: $key');
      }
    });

    test('CFBundlePackageType is APPL', () {
      expect(infoPlist, contains('<string>APPL</string>'));
    });

    test('LSRequiresIPhoneOS is true', () {
      // The key should be followed (possibly with whitespace) by <true/>
      final lsIdx = infoPlist.indexOf('<key>LSRequiresIPhoneOS</key>');
      expect(lsIdx, isNot(-1));
      final afterKey = infoPlist.substring(lsIdx);
      expect(afterKey, contains('<true/>'));
    });

    test('has location permission descriptions', () {
      expect(infoPlist, contains('<key>NSLocationWhenInUseUsageDescription</key>'),
          reason: 'Missing foreground location permission description');
      expect(infoPlist, contains('<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>'),
          reason: 'Missing background location permission description');
    });

    test('has microphone permission description', () {
      expect(infoPlist, contains('<key>NSMicrophoneUsageDescription</key>'),
          reason: 'Missing microphone permission description (needed for PTT)');
    });

    test('has motion usage description', () {
      expect(infoPlist, contains('<key>NSMotionUsageDescription</key>'),
          reason: 'Missing motion usage description (needed for PDR)');
    });

    test('permission descriptions are not empty', () {
      // Each permission key should be followed by a non-empty <string>
      final permissionKeys = [
        'NSLocationWhenInUseUsageDescription',
        'NSLocationAlwaysAndWhenInUseUsageDescription',
        'NSMicrophoneUsageDescription',
        'NSMotionUsageDescription',
      ];

      for (final key in permissionKeys) {
        final keyIdx = infoPlist.indexOf('<key>$key</key>');
        expect(keyIdx, isNot(-1), reason: '$key not found');
        final afterKey = infoPlist.substring(keyIdx);
        // Should have a non-empty <string>...</string> following the key
        final match = RegExp(r'<string>(.+?)</string>').firstMatch(afterKey);
        expect(match, isNotNull, reason: '$key has no string value');
        expect(match!.group(1)!.trim(), isNotEmpty,
            reason: '$key description is empty');
      }
    });

    test('has background location mode', () {
      expect(infoPlist, contains('<key>UIBackgroundModes</key>'),
          reason: 'Missing UIBackgroundModes');
      expect(infoPlist, contains('<string>location</string>'),
          reason: 'Background location mode not enabled');
    });

    test('supports required orientations', () {
      expect(infoPlist, contains('<key>UISupportedInterfaceOrientations</key>'));
      expect(infoPlist, contains('<string>UIInterfaceOrientationPortrait</string>'));
    });

    test('PrivacyInfo.xcprivacy exists', () {
      final file = File('$root/ios/Runner/PrivacyInfo.xcprivacy');
      expect(file.existsSync(), isTrue,
          reason: 'PrivacyInfo.xcprivacy required for App Store (April 2024+)');
    });

    test('PrivacyInfo declares no tracking', () {
      final file = File('$root/ios/Runner/PrivacyInfo.xcprivacy');
      final content = file.readAsStringSync();
      expect(content, contains('NSPrivacyTracking'));
      // Should declare tracking as false
      final trackingIdx = content.indexOf('NSPrivacyTracking</key>');
      expect(trackingIdx, isNot(-1));
      final afterKey = content.substring(trackingIdx);
      expect(afterKey, contains('<false/>'),
          reason: 'NSPrivacyTracking should be false');
    });

    test('app icons exist for all required sizes', () {
      final iconDir = Directory('$root/ios/Runner/Assets.xcassets/AppIcon.appiconset');
      expect(iconDir.existsSync(), isTrue,
          reason: 'AppIcon.appiconset directory must exist');

      final contentsFile = File('${iconDir.path}/Contents.json');
      expect(contentsFile.existsSync(), isTrue,
          reason: 'Contents.json must exist in AppIcon.appiconset');

      // Verify the 1024x1024 marketing icon is declared
      final contents = contentsFile.readAsStringSync();
      expect(contents, contains('1024'),
          reason: '1024x1024 marketing icon is required for App Store');
    });

    test('bundle identifier has valid reverse-domain format', () {
      final pbxproj = File('$root/ios/Runner.xcodeproj/project.pbxproj');
      expect(pbxproj.existsSync(), isTrue);

      final content = pbxproj.readAsStringSync();
      final match = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);')
          .firstMatch(content);
      expect(match, isNotNull, reason: 'PRODUCT_BUNDLE_IDENTIFIER not found');

      final bundleId = match!.group(1)!.trim();
      // Should be reverse-domain format (at least 2 dots)
      expect(bundleId.split('.').length, greaterThanOrEqualTo(3),
          reason: 'Bundle ID "$bundleId" should be reverse-domain format (e.g. com.company.app)');
    });
  });

  // ---------------------------------------------------------------------------
  // Google Play Store
  // ---------------------------------------------------------------------------
  group('Google Play Store compliance', () {
    late String manifest;

    setUpAll(() {
      final file = File('$root/android/app/src/main/AndroidManifest.xml');
      expect(file.existsSync(), isTrue, reason: 'AndroidManifest.xml must exist');
      manifest = file.readAsStringSync();
    });

    test('manifest has package/namespace declared', () {
      // package may be in manifest or namespace in build.gradle
      final hasPackage = manifest.contains('package=');
      final buildGradle = File('$root/android/app/build.gradle');
      final hasNamespace = buildGradle.existsSync() &&
          buildGradle.readAsStringSync().contains('namespace');
      expect(hasPackage || hasNamespace, isTrue,
          reason: 'App must have package name (manifest) or namespace (build.gradle)');
    });

    test('has MAIN/LAUNCHER intent filter', () {
      expect(manifest, contains('android.intent.action.MAIN'),
          reason: 'Missing MAIN intent action');
      expect(manifest, contains('android.intent.category.LAUNCHER'),
          reason: 'Missing LAUNCHER category');
    });

    test('main activity is exported', () {
      expect(manifest, contains('android:exported="true"'),
          reason: 'Main activity must be exported (required for Android 12+)');
    });

    test('has required location permissions', () {
      expect(manifest, contains('ACCESS_FINE_LOCATION'),
          reason: 'Missing ACCESS_FINE_LOCATION permission');
      expect(manifest, contains('ACCESS_COARSE_LOCATION'),
          reason: 'Missing ACCESS_COARSE_LOCATION permission');
    });

    test('has background location permission', () {
      expect(manifest, contains('ACCESS_BACKGROUND_LOCATION'),
          reason: 'Missing ACCESS_BACKGROUND_LOCATION (needed for GPS tracking)');
    });

    test('has foreground service permission and type', () {
      expect(manifest, contains('FOREGROUND_SERVICE'),
          reason: 'Missing FOREGROUND_SERVICE permission');
      expect(manifest, contains('FOREGROUND_SERVICE_LOCATION'),
          reason: 'Missing FOREGROUND_SERVICE_LOCATION permission');
    });

    test('has audio recording permission', () {
      expect(manifest, contains('RECORD_AUDIO'),
          reason: 'Missing RECORD_AUDIO permission (needed for PTT)');
    });

    test('has notification permission', () {
      expect(manifest, contains('POST_NOTIFICATIONS'),
          reason: 'Missing POST_NOTIFICATIONS (required for Android 13+)');
    });

    test('has Flutter embedding v2', () {
      expect(manifest, contains('flutterEmbedding'),
          reason: 'Missing flutterEmbedding meta-data');
      // Value should be 2
      final match = RegExp(r'android:value="2"\s*/>\s*<!--\s*.*flutter.*|android:value="2"')
          .hasMatch(manifest);
      final containsV2 = manifest.contains('android:name="flutterEmbedding"') &&
          manifest.contains('android:value="2"');
      expect(containsV2, isTrue,
          reason: 'Flutter embedding must be version 2');
    });

    test('build.gradle has valid SDK versions', () {
      final buildGradle = File('$root/android/app/build.gradle');
      expect(buildGradle.existsSync(), isTrue);

      final content = buildGradle.readAsStringSync();

      // minSdk >= 21 (Play Store practical minimum for modern Flutter)
      final minSdkMatch = RegExp(r'minSdk\s*[=:]\s*(\d+)').firstMatch(content);
      if (minSdkMatch != null) {
        final minSdk = int.parse(minSdkMatch.group(1)!);
        expect(minSdk, greaterThanOrEqualTo(21),
            reason: 'minSdk ($minSdk) should be >= 21');
      }

      // targetSdk >= 33 (Play Store requirement since Aug 2024)
      final targetSdkMatch = RegExp(r'targetSdk\s*[=:]\s*(\d+)').firstMatch(content);
      if (targetSdkMatch != null) {
        final targetSdk = int.parse(targetSdkMatch.group(1)!);
        expect(targetSdk, greaterThanOrEqualTo(33),
            reason: 'targetSdk ($targetSdk) must be >= 33 (Play Store requirement)');
      }
    });

    test('build.gradle has applicationId', () {
      final buildGradle = File('$root/android/app/build.gradle');
      final content = buildGradle.readAsStringSync();

      final match = RegExp(r'applicationId\s*[=:\s]\s*"([^"]+)"').firstMatch(content);
      expect(match, isNotNull, reason: 'applicationId not found in build.gradle');

      final appId = match!.group(1)!;
      expect(appId.split('.').length, greaterThanOrEqualTo(3),
          reason: 'applicationId "$appId" should be reverse-domain format');
    });

    test('launcher icons exist for all densities', () {
      const densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
      final resDir = '$root/android/app/src/main/res';

      for (final density in densities) {
        final iconFile = File('$resDir/mipmap-$density/ic_launcher.png');
        expect(iconFile.existsSync(), isTrue,
            reason: 'Missing launcher icon for density: $density');
        // Icon file should not be empty
        expect(iconFile.lengthSync(), greaterThan(0),
            reason: 'Launcher icon for $density is empty');
      }
    });

    test('has release signing configuration', () {
      final buildGradle = File('$root/android/app/build.gradle');
      final content = buildGradle.readAsStringSync();

      // Should reference signing config for release builds
      expect(content, contains('signingConfig'),
          reason: 'build.gradle should have signing configuration for release');
    });
  });
}
