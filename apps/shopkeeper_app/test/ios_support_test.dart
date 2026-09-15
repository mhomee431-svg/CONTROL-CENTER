import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/auth/firebase_auth_service.dart';
import 'package:hyperlocal_shopkeeper_app/firebase_options.dart';

/// iOS platform-support regression tests.
///
/// The iOS binary can only be produced on macOS, but every declaration the
/// project ships under `ios/` is verifiable from here — and these assertions
/// cover the failure modes that actually break a release:
///
///   * a missing usage description (iOS TERMINATES the app the moment the
///     feature is used, e.g. camera or location);
///   * a bundle-id / Firebase mismatch (Google Sign-In silently fails);
///   * an OAuth callback URL scheme that is not registered (the browser cannot
///     hand the credential back — breaks Google Sign-In and Phone-Auth
///     reCAPTCHA on iOS);
///   * ATS blocking the plain-HTTP dev backend;
///   * the Android-only native Google channel being used on iOS.
void main() {
  final infoPlistFile = File('ios/Runner/Info.plist');
  final pbxprojFile = File('ios/Runner.xcodeproj/project.pbxproj');

  group('iOS platform scaffold', () {
    test('the iOS runner project is present and labelled as this app', () {
      expect(infoPlistFile.existsSync(), isTrue, reason: 'ios/Runner/Info.plist');
      expect(pbxprojFile.existsSync(), isTrue,
          reason: 'ios/Runner.xcodeproj/project.pbxproj');
      expect(File('ios/Runner/AppDelegate.swift').existsSync(), isTrue);
      expect(File('ios/Runner/SceneDelegate.swift').existsSync(), isTrue);
      expect(infoPlistFile.readAsStringSync(),
          contains('<string>Hyperlocal Shopkeeper App</string>'));
    });
  });

  group('iOS permission strings (parity with AndroidManifest permissions)', () {
    final plist = infoPlistFile.readAsStringSync();

    test('camera — barcode scanning (mobile_scanner)', () {
      expect(plist, contains('<key>NSCameraUsageDescription</key>'));
    });

    test('location — shop GPS capture (geolocator)', () {
      expect(plist, contains('<key>NSLocationWhenInUseUsageDescription</key>'));
    });

    test('photo library — product / shop photos (file_picker images)', () {
      expect(plist, contains('<key>NSPhotoLibraryUsageDescription</key>'));
    });

    test('every usage description carries real copy, never an empty string',
        () {
      const keys = [
        'NSCameraUsageDescription',
        'NSLocationWhenInUseUsageDescription',
        'NSPhotoLibraryUsageDescription',
      ];
      for (final key in keys) {
        final match = RegExp('<key>$key</key>\\s*<string>(.*?)</string>',
                dotAll: true)
            .firstMatch(plist);
        expect(match, isNotNull, reason: '$key is missing from Info.plist');
        expect(match!.group(1)!.trim(), isNotEmpty, reason: '$key is empty');
      }
    });
  });

  group('iOS app identity', () {
    final project = pbxprojFile.readAsStringSync();

    test('bundle id matches the Android applicationId (Firebase parity)', () {
      expect(project,
          contains('PRODUCT_BUNDLE_IDENTIFIER = com.hyperlocal.app;'));
      expect(project, isNot(contains('hyperlocalShopkeeperApp')));
      expect(
        File('android/app/build.gradle.kts').readAsStringSync(),
        contains('applicationId = "com.hyperlocal.app"'),
        reason: 'iOS and Android must present the SAME app identity to Firebase',
      );
    });

    test('deployment target satisfies the newest plugin (Firebase needs 15.0)',
        () {
      final targets = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);')
          .allMatches(project)
          .map((m) => double.parse(m.group(1)!))
          .toList();
      expect(targets, isNotEmpty);
      for (final target in targets) {
        expect(target, greaterThanOrEqualTo(15.0));
      }
    });

    test('the iOS Firebase options carry the OAuth client + bundle id', () {
      final ios = AppFirebaseOptions.iOS;
      expect(ios.iosClientId, AppFirebaseOptions.googleOAuthClientId);
      expect(ios.iosBundleId, AppFirebaseOptions.iOSBundleId);
      expect(ios.projectId, 'local-pier-506805-g5');
      // Must agree with what the Xcode project actually builds.
      expect(project, contains(ios.iosBundleId!));
    });

    test('the REVERSED OAuth client id is a registered URL scheme', () {
      final plist = infoPlistFile.readAsStringSync();
      final reversed = AppFirebaseOptions.googleOAuthClientId
          .split('.')
          .reversed
          .join('.');
      expect(plist, contains('<key>CFBundleURLTypes</key>'));
      expect(plist, contains('<string>$reversed</string>'));
    });

    test('local-network HTTP stays reachable for the dev backend', () {
      final plist = infoPlistFile.readAsStringSync();
      expect(plist, contains('<key>NSAppTransportSecurity</key>'));
      expect(plist, contains('<key>NSAllowsLocalNetworking</key>'));
    });
  });

  group('platform routing for Google Sign-In', () {
    test('iOS uses the Firebase OAuth provider flow, never the Android channel',
        () {
      expect(
        googleSignInStrategyFor(TargetPlatform.iOS),
        GoogleSignInStrategy.firebaseOAuthProvider,
      );
    });

    test('Android keeps the native Credential Manager MethodChannel', () {
      expect(
        googleSignInStrategyFor(TargetPlatform.android),
        GoogleSignInStrategy.androidCredentialManager,
      );
    });

    test('the Firebase options stay platform-aware', () {
      final current = AppFirebaseOptions.currentPlatform;
      expect(current.projectId, 'local-pier-506805-g5');
      expect(current.appId, isNotEmpty);
      expect(AppFirebaseOptions.iOS.appId,
          isNot(AppFirebaseOptions.android.appId));
    });
  });
}
