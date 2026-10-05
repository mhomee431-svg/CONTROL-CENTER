import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'app_exception.dart';
import 'failures.dart';

/// The ONE place that turns a thrown object into something a customer can read.
///
/// Everything the UI shows for an error must come through [message]. The reason
/// this is centralised is that the alternative is what the codebase was doing:
/// `e.toString()`, `$e` interpolation, and per-screen string literals. Those leak
/// `Exception: ` prefixes, `SocketException: Connection failed`, and — for a
/// `FirebaseAuthException` — SDK internal codes that mean nothing to a customer.
///
/// The order below matters, and each step earns its place:
///   1. our own types, because they already carry approved copy;
///   2. cancellation, because a cancelled sheet must stay SILENT, not render
///      "Google sign-in was cancelled." as an error;
///   3. platform/SDK errors, which need a table lookup;
///   4. a safe catch-all that never returns null, so a caller cannot forget to
///      handle the unknown case and render nothing at all.
abstract final class ErrorMessageMapper {
  /// Fallback for anything not recognised. Never null and never an interpolation.
  static const String genericMessage =
      'Something went wrong. Please try again.';

  /// Maps any thrown object to customer-facing copy.
  ///
  /// Never throws and never returns null: an error path that can itself fail is
  /// how blank screens and unhandled exceptions in the UI happen.
  static String message(Object? error) {
    if (error == null) return genericMessage;

    // 1. Cancellation, checked BEFORE our own types on purpose. A cancelled
    //    Google sign-in IS a `GoogleSignInCancelledFailure`, so a `Failure`
    //    check placed first would return "Google sign-in was cancelled." as a
    //    red error banner for something the customer chose to do.
    if (isCancellation(error)) return '';

    // 2. Our own types carry copy we already approved.
    if (error is Failure) return error.message;
    if (error is AppException) return error.message;

    // 3. Platform + SDK errors, which need a table.
    final mapped = _fromPlatform(error) ?? _fromFirebaseAuth(error);
    if (mapped != null) return mapped;

    // 4. Unknown. Do NOT interpolate `error` — its toString() may contain a
    //    stack trace, a file path, or an internal identifier.
    if (kDebugMode) {
      debugPrint('Unmapped error surfaced to the UI: $error');
    }
    return genericMessage;
  }

  /// Non-empty message for a snackbar/dialog. Use when the UI needs *some* text
  /// and a cancellation should read as a fallback rather than as silence.
  static String messageOrFallback(Object? error) {
    final m = message(error);
    return m.isEmpty ? genericMessage : m;
  }

  /// True when the UI should stay silent.
  static bool isSilent(Object? error) =>
      error is GoogleSignInCancelledFailure || isCancellation(error);

  /// True only when the error is a deliberate, customer-initiated dismissal.
  ///
  /// Deliberately narrow. A `TimeoutException` is NOT a cancellation — the
  /// customer is still staring at a spinner waiting for an answer, so silence
  /// there is the worst option and "This is taking too long" is the right one.
  /// A `StateError` is not a cancellation either; it is a bug, and it degrades
  /// to the generic copy so it stays visible in bug reports.
  static bool isCancellation(Object? error) =>
      error is GoogleSignInCancelledFailure;

  static String? _fromPlatform(Object error) {
    if (error is SocketException || error is HttpException) {
      return 'No internet connection. Please check your network.';
    }
    if (error is TimeoutException) {
      return 'This is taking too long. Please try again.';
    }
    // Handled on web/IO; a null message otherwise proves nothing went wrong.
    if (error is FormatException) return genericMessage;
    return null;
  }

  /// Firebase codes the customer can act on. Anything not listed here falls
  /// through to [genericMessage] on purpose: a raw `firebase_auth` string such
  /// as "network-request-failed" or an internal exception id is not copy.
  static String? _fromFirebaseAuth(Object error) {
    if (error is! FirebaseAuthException) return null;
    switch (error.code) {
      case 'invalid-phone-number':
        return 'Please enter a valid 10-digit mobile number.';
      case 'invalid-verification-code':
      case 'invalid-verification-id':
        return 'Invalid OTP entered. Please check and try again.';
      case 'session-expired':
        return 'Your session has expired. Please log in again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      case 'operation-not-allowed':
        return 'Phone sign-in is not enabled right now. Please try again later.';
      case 'quota-exceeded':
        return 'We could not send the code right now. Please try again later.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      default:
        // Platform-specific codes (Web: 'popup-closed-by-user',
        // 'popup-blocked', 'canceled') are all a customer cancelling or a
        // browser policy. Neither is worth an error banner, so they fall
        // through to the generic copy.
        return null;
    }
  }
}
