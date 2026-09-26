import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/auth/data/google_auth_service.dart';
import 'package:hyperlocal_app/features/auth/data/phone_auth_service.dart';

/// Every code that has a dedicated (friendly) translation.
const _phoneKnownCodes = <String>[
  'invalid-phone-number',
  'missing-phone-number',
  'invalid-verification-code',
  'missing-verification-code',
  'invalid-verification-id',
  'session-expired',
  'no_verification',
  'too-many-requests',
  'quota-exceeded',
  'user-disabled',
  'operation-not-allowed',
  'app-not-authorized',
  'missing-client-identifier',
  'network-request-failed',
  'captcha-check-failed',
  'invalid-app-credential',
  'missing-app-credential',
  'credential-already-in-use',
  'provider-already-linked',
  'user-mismatch',
  'account-exists-with-different-credential',
  'no_token',
];

const _googleKnownCodes = <String>[
  'cancelled',
  'canceled',
  'network-request-failed',
  'account-exists-with-different-credential',
  'operation-not-allowed',
  'user-disabled',
  'no-google-accounts',
  'google-sign-in-unavailable',
  'id-token-null',
  'firebase-user-null',
];

void main() {
  group('phoneAuthErrorMessage', () {
    test('maps the OTP lifecycle codes to actionable copy', () {
      expect(
        phoneAuthErrorMessage('invalid-verification-code'),
        'Incorrect OTP. Please check the code and try again.',
      );
      expect(
        phoneAuthErrorMessage('invalid-verification-id'),
        contains('expired'),
      );
      expect(phoneAuthErrorMessage('session-expired'), contains('Resend OTP'));
      expect(
        phoneAuthErrorMessage('network-request-failed'),
        'Network error. Check your connection and try again.',
      );
      // The expired message must tell the customer how to recover.
      expect(phoneAuthErrorMessage('no_verification'), contains('Resend OTP'));
    });

    test('maps throttling codes without exposing Firebase wording', () {
      expect(
        phoneAuthErrorMessage('too-many-requests'),
        contains('Too many attempts'),
      );
      expect(phoneAuthErrorMessage('quota-exceeded'), contains('SMS limit'));
    });

    test('every known code yields human copy, never the raw code', () {
      for (final code in _phoneKnownCodes) {
        final message = phoneAuthErrorMessage(code);
        expect(message, isNotEmpty, reason: code);
        expect(message, isNot(contains('Firebase')), reason: code);
        expect(message, isNot(contains('auth/')), reason: code);
        expect(message, isNot(contains('Exception')), reason: code);
      }
    });

    test('unknown/technical codes fall back to a generic sentence', () {
      for (final code in <String?>[
        'invalid-api-key',
        'internal-error',
        'unknown',
        null,
      ]) {
        final message = phoneAuthErrorMessage(code);
        expect(
          message,
          'We could not verify your number right now. Please try again.',
        );
      }
    });

    test('fallback copy never carries technical details', () {
      final message = phoneAuthErrorMessage('some-random-internal-code');
      expect(message, isNot(contains('(')));
      expect(message, isNot(contains(')')));
      expect(message.toLowerCase(), isNot(contains('exception')));
    });
  });

  group('googleAuthErrorMessage', () {
    test('maps the Google lifecycle codes to actionable copy', () {
      expect(
        googleAuthErrorMessage('cancelled'),
        'Google sign-in was cancelled.',
      );
      expect(
        googleAuthErrorMessage('canceled'),
        'Google sign-in was cancelled.',
      );
      expect(
        googleAuthErrorMessage('network-request-failed'),
        contains('Network error'),
      );
      expect(
        googleAuthErrorMessage('no-google-accounts'),
        contains('No Google account'),
      );
    });

    test('every known code yields human copy, never the raw code', () {
      for (final code in _googleKnownCodes) {
        final message = googleAuthErrorMessage(code);
        expect(message, isNotEmpty, reason: code);
        expect(message, isNot(contains('Firebase')), reason: code);
        expect(message, isNot(contains('auth/')), reason: code);
        expect(message, isNot(contains('Exception')), reason: code);
      }
    });

    test('unknown codes fall back to a generic sentence', () {
      expect(
        googleAuthErrorMessage('plugin-crash-xyz'),
        'Google Sign-In failed. Please try again.',
      );
      expect(
        googleAuthErrorMessage(null),
        'Google Sign-In failed. Please try again.',
      );
    });
  });

  group('FakePhoneAuthService', () {
    test('sendOtp reports code-sent on success', () async {
      final fake = FakePhoneAuthService();
      String? verificationId;
      String? error;
      await fake.sendOtp(
        phoneNumber: '+919999999999',
        onCodeSent: (id) => verificationId = id,
        onError: (message) => error = message,
      );
      expect(verificationId, isNotNull);
      expect(error, isNull);
    });

    test('sendOtp reports a sanitized error on failure', () async {
      final fake = FakePhoneAuthService(shouldFail: true);
      String? error;
      await fake.sendOtp(
        phoneNumber: '+919999999999',
        onCodeSent: (_) {},
        onError: (message) => error = message,
      );
      expect(error, isNotNull);
      expect(error, isNot(contains('Exception')));
    });

    test('cancelPendingVerification is safe on every implementation', () async {
      await FakePhoneAuthService().cancelPendingVerification();
      await FakePhoneAuthService(shouldFail: true).cancelPendingVerification();
    });
  });
}
