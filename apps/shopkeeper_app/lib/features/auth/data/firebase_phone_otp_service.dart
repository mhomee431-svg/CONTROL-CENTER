import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/phone_otp.dart';
import 'auth_repository.dart' show kUseMockAuth;

/// Real [PhoneOtpService] on top of **Firebase Phone Auth**.
///
/// This is the "future apply" implementation: it is fully wired and compiled
/// into the app today, but the OTP screen only becomes reachable when the
/// build enables [AuthMethod.phoneOtp] (`enabledAuthMethodsProvider`).
///
/// Platform notes (Firebase Phone Auth behaviour, not app logic):
///   * Android / web: `signInWithPhoneNumber` returns a confirmation once the
///     code has been sent.
///   * iOS / macOS: `signInWithPhoneNumber` is unavailable, so
///     `verifyPhoneNumber` is used; it may also auto-verify the number through
///     a silent APNs push, in which case the flow completes without a code.
class FirebasePhoneOtpService implements PhoneOtpService {
  FirebasePhoneOtpService({
    FirebaseAuth? auth,
    this.timeout = const Duration(seconds: 60),
  }) : _authOverride = auth;

  /// Optional test override; `FirebaseAuth.instance` is resolved lazily at USE
  /// time so constructing the service never crashes without an initialised
  /// Firebase core.
  final FirebaseAuth? _authOverride;

  /// How long `verifyPhoneNumber` waits for the SMS before reporting a
  /// timeout (`codeAutoRetrievalTimeout`).
  final Duration timeout;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  @override
  bool get isSupported {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Future<PhoneOtpRequest> requestCode(
    String e164PhoneNumber, {
    int? resendToken,
  }) async {
    if (!isSupported) {
      throw const PhoneOtpException(
        'Phone sign-in is not available on this device.',
        code: 'unsupported-platform',
      );
    }

    // Clear any stale Firebase session first — the same reason Google
    // Sign-In does it: a cached invalid credential breaks re-verification.
    try {
      await _auth.signOut();
    } catch (_) {
      // Best-effort: continue with the fresh verification request.
    }

    try {
      if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) {
        final confirmation = await _auth.signInWithPhoneNumber(
          e164PhoneNumber,
        );
        return PhoneOtpRequest(
          phoneNumber: e164PhoneNumber,
          verificationId: confirmation.verificationId,
        );
      }
      // `await` (not a bare return) so a failure from the iOS callback-based
      // path is still converted by the catch blocks below.
      return await _requestCodeViaVerifyPhoneNumber(e164PhoneNumber, resendToken);
    } on PhoneOtpException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw _map(e);
    } catch (_) {
      throw const PhoneOtpException(
        'Could not send the code. Please try again.',
      );
    }
  }

  /// iOS / macOS path: `verifyPhoneNumber` reports the outcome through
  /// callbacks, so the future is completed as soon as the code is sent — or
  /// immediately when the platform auto-verified the number.
  Future<PhoneOtpRequest> _requestCodeViaVerifyPhoneNumber(
    String phoneNumber,
    int? resendToken,
  ) {
    final completer = Completer<PhoneOtpRequest>();
    _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: timeout,
      forceResendingToken: resendToken,
      verificationCompleted: (credential) async {
        if (completer.isCompleted) return;
        try {
          final token = await _idTokenFromCredential(credential);
          completer.complete(
            PhoneOtpRequest(
              phoneNumber: phoneNumber,
              autoVerifiedIdToken: token,
            ),
          );
        } catch (e) {
          if (!completer.isCompleted) {
            completer.completeError(
              e is PhoneOtpException
                  ? e
                  : const PhoneOtpException(
                      'Phone sign-in could not be completed. Please try again.',
                    ),
            );
          }
        }
      },
      verificationFailed: (e) {
        if (!completer.isCompleted) completer.completeError(_map(e));
      },
      codeSent: (verificationId, forceResendingToken) {
        if (completer.isCompleted) return;
        completer.complete(
          PhoneOtpRequest(
            phoneNumber: phoneNumber,
            verificationId: verificationId,
            resendToken: forceResendingToken,
          ),
        );
      },
      // The SMS may still arrive after this fires; the code step is already
      // available, so nothing to do.
      codeAutoRetrievalTimeout: (_) {},
    );
    return completer.future;
  }

  @override
  Future<String> verifyCode({
    required String verificationId,
    required String code,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );
      return await _idTokenFromCredential(credential);
    } on PhoneOtpException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw _map(e);
    } catch (_) {
      throw const PhoneOtpException('Phone sign-in failed. Please try again.');
    }
  }

  /// Signs the Firebase credential in and returns its refreshed ID token —
  /// the token the backend verifies through `/shopkeeper/auth/firebase-login`.
  Future<String> _idTokenFromCredential(PhoneAuthCredential credential) async {
    final result = await _auth.signInWithCredential(credential);
    final token = await result.user?.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw const PhoneOtpException(
        'Phone sign-in could not be completed. Please try again.',
        code: 'id-token-null',
      );
    }
    return token;
  }

  /// Maps Firebase error codes to shopkeeper-readable text, keeping the raw
  /// code so the UI can offer targeted recovery later.
  PhoneOtpException _map(FirebaseAuthException e) => PhoneOtpException(
        switch (e.code) {
          'invalid-phone-number' =>
            'That phone number is not valid. Please check and try again.',
          'invalid-verification-code' => 'The code you entered is incorrect.',
          'session-expired' =>
            'This code has expired. Please request a new one.',
          'too-many-requests' =>
            'Too many attempts. Please try again in a few minutes.',
          'quota-exceeded' =>
            'The daily SMS limit has been reached. Please try again later.',
          'operation-not-supported-in-this-environment' =>
            'Phone sign-in is not available on this device.',
          'app-not-authorized' =>
            'Phone sign-in is not configured for this build.',
          'missing-verification-id' =>
            'Phone verification could not be started. Please retry.',
          'web-context-cancelled' =>
            'Phone sign-in was cancelled. Please try again.',
          _ => (e.message?.trim().isNotEmpty ?? false)
              ? e.message!.trim()
              : 'Phone sign-in failed. Please try again.',
        },
        code: e.code,
      );
}

/// OTP provider used by the app.
///
/// Mirrors `authRepositoryProvider`: `kUseMockAuth` builds (offline dev, demo
/// mode) get the mock so the whole flow works without Firebase or SMS.
final phoneOtpServiceProvider = Provider<PhoneOtpService>((ref) {
  if (kUseMockAuth) return MockPhoneOtpService();
  return FirebasePhoneOtpService();
});