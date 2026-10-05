import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks the Firebase client configuration contract.
///
/// ## Why a test and not a review note
/// ---------------------------------
/// Firebase client configuration fails SILENTLY and LATE. A package-name
/// mismatch, a missing plugin, or a renamed `applicationId` all compile
/// perfectly and only surface at runtime as `core/no-app` or "No matching
/// client found for package name" — on a real device, with a real phone
/// number, at the point a customer is trying to sign in.
///
/// Every assertion here corresponds to a failure that is invisible until it
/// costs a login.
///
/// ## Scope: this does NOT create anything
/// --------------------------------------
/// No Firebase project is created, no console setting is changed, and no
/// credential is invented. This reads the configuration that already exists and
/// states what must stay true. Where a platform is genuinely unconfigured, the
/// test says so explicitly rather than pretending otherwise.
void main() {
  const androidConfig = 'android/app/google-services.json';
  const androidAppGradle = 'android/app/build.gradle.kts';
  const androidSettingsGradle = 'android/settings.gradle.kts';
  const iosPlist = 'ios/Runner/GoogleService-Info.plist';
  const generatedOptions = 'lib/firebase_options.dart';

  Map<String, dynamic> readAndroidConfig() {
    final file = File(androidConfig);
    expect(
      file.existsSync(),
      isTrue,
      reason:
          '$androidConfig is missing, so the google-services Gradle plugin '
          'has nothing to read and Firebase cannot initialise on Android',
    );
    return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  /// The Android package name Firebase has registered this app under.
  String registeredPackage() {
    final config = readAndroidConfig();
    final clients = config['client'] as List<dynamic>;
    final client = clients.first as Map<String, dynamic>;
    final info = client['client_info'] as Map<String, dynamic>;
    final androidInfo = info['android_client_info'] as Map<String, dynamic>;
    return androidInfo['package_name'] as String;
  }

  group('the Android Firebase client config is present and coherent', () {
    test('it names a real project rather than a placeholder', () {
      final config = readAndroidConfig();
      final project = config['project_info'] as Map<String, dynamic>;
      final projectId = project['project_id'] as String? ?? '';

      expect(projectId, isNotEmpty, reason: 'project_id is required');
      expect(
        projectId,
        isNot(contains('your-project')),
        reason: 'project_id still looks like a placeholder',
      );
      expect(
        projectId,
        isNot(contains('REPLACE')),
        reason: 'project_id still looks like a placeholder',
      );
    });

    test('the registered app id and API key are present', () {
      // Phone Auth needs the API key at runtime; a config missing it fails on
      // the first OTP request rather than at startup, which is worse to debug.
      final config = readAndroidConfig();
      final clients = config['client'] as List<dynamic>;
      expect(clients, isNotEmpty, reason: 'no client entries at all');

      final client = clients.first as Map<String, dynamic>;
      final info = client['client_info'] as Map<String, dynamic>;
      expect(
        info['mobilesdk_app_id'] as String?,
        isNotNull,
        reason: 'mobilesdk_app_id identifies the app to Firebase',
      );

      final keys = client['api_key'] as List<dynamic>?;
      final currentKey = keys == null
          ? null
          : (keys.first as Map<String, dynamic>)['current_key'] as String?;
      expect(
        currentKey,
        isNotNull,
        reason:
            'Phone Auth calls the Identity Toolkit with this key; without '
            'it every OTP request fails at runtime',
      );
    });

    test('it is a CLIENT config, never an Admin service account', () {
      // The distinction that actually matters: an `AIza…` client key ships in
      // every build by design, while a service-account `private_key` would let
      // anyone holding the repo act as the entire user base.
      final raw = File(androidConfig).readAsStringSync();
      expect(raw, isNot(contains('"type": "service_account"')));
      expect(raw, isNot(contains('"private_key"')));
    });
  });

  group('the package name agrees between Gradle and Firebase', () {
    // THE high-value check. The google-services plugin matches the
    // applicationId against `package_name` as an exact, case-sensitive string.
    // A mismatch — including a single capital letter — compiles fine and fails
    // only at runtime on a device.
    test('applicationId and namespace match the registered package_name', () {
      final registered = registeredPackage();
      final gradle = File(androidAppGradle).readAsStringSync();

      final applicationId = RegExp(r'applicationId\s*=\s*"([^"]+)"')
          .firstMatch(gradle)
          ?.group(1);
      final namespace = RegExp(r'namespace\s*=\s*"([^"]+)"')
          .firstMatch(gradle)
          ?.group(1);

      expect(
        applicationId,
        isNotNull,
        reason: 'could not read applicationId out of $androidAppGradle',
      );
      expect(
        applicationId,
        registered,
        reason:
            'applicationId "$applicationId" does not match the '
            'package_name "$registered" in $androidConfig. Firebase matches '
            'this EXACTLY, so the app would fail to initialise at runtime with '
            '"No matching client found for package name".',
      );
      expect(
        namespace,
        applicationId,
        reason:
            'namespace and applicationId must agree, or the generated '
            'resources reference a package that does not exist',
      );
    });
  });
  group('the Gradle wiring for Firebase is present', () {
    test('the google-services plugin is resolved in settings', () {
      // Applying `id("com.google.gms.google-services")` in the app module
      // without a version in settings fails the build with a confusing
      // "plugin not found" rather than anything mentioning Firebase.
      final settings = File(androidSettingsGradle).readAsStringSync();
      expect(
        settings,
        contains('com.google.gms.google-services'),
        reason: 'the plugin version must be declared in $androidSettingsGradle',
      );
      expect(
        settings,
        contains('useModule('),
        reason: 'the google-services plugin is not on the classpath',
      );
    });

    test('the google-services plugin is applied by the app module', () {
      final gradle = File(androidAppGradle).readAsStringSync();
      expect(
        gradle,
        contains('id("com.google.gms.google-services")'),
        reason:
            'without this the json is never read into resources and '
            'Firebase cannot find its default options',
      );
    });

    test('the Firebase SDK dependencies are declared', () {
      final gradle = File(androidAppGradle).readAsStringSync();
      expect(gradle, contains('com.google.firebase:firebase-bom'));
      expect(gradle, contains('com.google.firebase:firebase-auth'));
    });

    test('minSdk is high enough for Firebase Auth', () {
      // Firebase Auth requires API 23+. Silently lowering this is how a build
      // starts failing to install with an unhelpful manifest merger error.
      final gradle = File(androidAppGradle).readAsStringSync();
      final minSdk = RegExp(
        r'minSdk\s*=\s*maxOf\(flutter\.minSdkVersion,\s*(\d+)\)',
      ).firstMatch(gradle)?.group(1);

      expect(minSdk, isNotNull, reason: 'could not read the minSdk floor');
      expect(
        int.parse(minSdk!),
        greaterThanOrEqualTo(23),
        reason: 'Firebase Auth requires API 23 or newer',
      );
    });
  });

  group('the Dart side declares the plugins it uses', () {
    test('firebase_core, firebase_auth and messaging are dependencies', () {
      // firebase_core is what `Firebase.initializeApp()` comes from;
      // firebase_messaging backs the FCM handler registered in main.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final package in const [
        'firebase_core',
        'firebase_auth',
        'firebase_messaging',
      ]) {
        expect(
          pubspec,
          contains('$package:'),
          reason: '$package is used by the app but not declared',
        );
      }
    });
  });

  group('platform coverage is stated honestly', () {
    test('iOS Firebase is NOT configured, and that is recorded here', () {
      // Stated rather than hidden. `ios/` is a real target (Podfile, xcodeproj,
      // xcworkspace and RunnerTests all exist), so iOS builds are expected to
      // work — but Firebase cannot initialise there today, because neither a
      // GoogleService-Info.plist nor lib/firebase_options.dart is committed.
      //
      // This test PASSES while noting the gap. When the plist is added, this
      // assertion starts failing and should be replaced by a real presence
      // check — which is the point: the gap is a deliberate, visible marker
      // rather than a silent one.
      final iosConfigured =
          File(iosPlist).existsSync() || File(generatedOptions).existsSync();

      expect(
        iosConfigured,
        isFalse,
        reason:
            'iOS Firebase config appeared. If that was deliberate, replace '
            'this test with a real presence check for $iosPlist and delete this '
            'comment — otherwise it will pass while proving nothing.',
      );

      // Sanity: iOS is a genuine target, so the gap is real and not an artefact
      // of a scaffold that was never built.
      //
      // `Directory`, not `File`: `File('ios/Runner.xcodeproj').existsSync()`
      // returns FALSE for a directory, always. That made this test fail against
      // a perfectly correct repository — a good reminder that an assertion has
      // to be about the thing being asserted. `.xcodeproj` is a bundle
      // directory; only `Podfile` is a real file.
      expect(
        Directory('ios/Runner.xcodeproj').existsSync(),
        isTrue,
        reason: 'if the iOS project is gone, drop the whole iOS gap note',
      );
      expect(File('ios/Podfile').existsSync(), isTrue);
    });
  });
}
