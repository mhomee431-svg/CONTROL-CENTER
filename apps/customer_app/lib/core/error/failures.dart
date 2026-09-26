abstract class Failure {
  final String message;
  const Failure(this.message);
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'A server error occurred']);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection']);
}

/// Thrown when the user enters an incorrect OTP code.
class InvalidOtpFailure extends Failure {
  const InvalidOtpFailure([
    super.message = 'Invalid OTP entered. Please check and try again.',
  ]);
}

/// Thrown when the OTP code has expired.
class ExpiredOtpFailure extends Failure {
  const ExpiredOtpFailure([
    super.message = 'This OTP has expired. Please request a new one.',
  ]);
}

/// Thrown when the user exceeds the maximum number of OTP attempts.
class TooManyAttemptsFailure extends Failure {
  const TooManyAttemptsFailure([
    super.message =
        'Too many incorrect attempts. Please wait and try again later.',
  ]);
}

/// Thrown when the user submits an invalid mobile number.
class InvalidPhoneNumberFailure extends Failure {
  const InvalidPhoneNumberFailure([
    super.message = 'Please enter a valid 10-digit mobile number.',
  ]);
}

/// Thrown when the user exceeds the OTP resend rate limit.
class OtpRateLimitFailure extends Failure {
  const OtpRateLimitFailure([
    super.message =
        'Too many OTP requests. Please wait a moment before resending.',
  ]);
}

/// Thrown when the user's session has expired.
class SessionExpiredFailure extends Failure {
  const SessionExpiredFailure([
    super.message = 'Your session has expired. Please log in again.',
  ]);
}

/// Thrown when the customer dismisses the Google Sign-In sheet.
///
/// Deliberately distinct from a real error so the UI can stay silent instead
/// of showing a red error message for an intentional cancellation.
class GoogleSignInCancelledFailure extends Failure {
  const GoogleSignInCancelledFailure([
    super.message = 'Google sign-in was cancelled.',
  ]);
}
