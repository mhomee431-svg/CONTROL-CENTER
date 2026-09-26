import 'package:flutter/foundation.dart';

/// A secure logging utility that:
/// - Only logs in debug mode (never in release builds)
/// - Automatically redacts sensitive data (tokens, passwords, secrets, etc.)
/// - Strips personally identifiable information (PII) from log output
/// - Never logs full request/response bodies in production
class SafeLogger {
  static const Set<String> _sensitiveKeys = {
    'password',
    'token',
    'authorization',
    'jwt',
    'otp',
    'secret',
    'access_token',
    'refresh_token',
    'api_key',
    'apikey',
    'auth',
    'bearer',
    'ssn',
    'aadhaar',
    'pan',
    'credit_card',
    'cvv',
  };

  /// Log a debug message. Only prints in non-release mode.
  static void debug(String message) {
    if (!kReleaseMode) {
      debugPrint('[DEBUG] ${_sanitize(message)}');
    }
  }

  /// Log a warning message. Only prints in non-release mode.
  static void warning(String message) {
    if (!kReleaseMode) {
      debugPrint('[WARN] ${_sanitize(message)}');
    }
  }

  /// Log an error message. Error messages are always printed (even in release)
  /// but sensitive data is still redacted. Stack traces are only shown in debug.
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    debugPrint('[ERROR] ${_sanitize(message)}');
    if (error != null) {
      final errorStr = error.toString();
      // Only log error details in debug mode to avoid leaking info
      if (!kReleaseMode) {
        debugPrint('Exception: ${_sanitize(errorStr)}');
      }
    }
    if (stackTrace != null && !kReleaseMode) {
      debugPrint(stackTrace.toString());
    }
  }

  /// Sanitize a string by redacting sensitive key-value pairs and PII patterns.
  static String _sanitize(String input) {
    var sanitized = input;

    // Redact sensitive key-value pairs (e.g., token=abc123, Authorization: Bearer xyz)
    for (final key in _sensitiveKeys) {
      // Match patterns like: key=value, key: value, "key": "value"
      final regex = RegExp('$key[:=]\\s*[^\\s,\\]\\}"]+', caseSensitive: false);
      sanitized = sanitized.replaceAll(regex, '$key=[REDACTED]');

      // Match JSON-style patterns: "key": "value"
      final jsonRegex = RegExp('"$key"\\s*:\\s*"[^"]+"', caseSensitive: false);
      sanitized = sanitized.replaceAll(jsonRegex, '"$key": "[REDACTED]"');
    }

    // Redact email addresses
    sanitized = sanitized.replaceAll(
      RegExp(r'[\w\.-]+@[\w\.-]+\.\w+'),
      '[EMAIL REDACTED]',
    );

    // Redact phone numbers (Indian format: 10-12 digits, optional +91 prefix)
    sanitized = sanitized.replaceAll(
      RegExp(r'(\+91[-\s]?)?[0-9]{10,12}'),
      '[PHONE REDACTED]',
    );

    return sanitized;
  }
}
