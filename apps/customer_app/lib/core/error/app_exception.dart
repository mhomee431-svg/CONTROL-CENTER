/// Base class for every error this app throws deliberately.
///
/// The point of this type is that the message travels WITH the error. A
/// `throw AppException(...)` at a repository means the UI can render the copy
/// without the presentation layer having to guess what went wrong.
///
/// Deliberately not carrying a `code`: the existing `Failure` hierarchy and the
/// SDK code tables already cover categorisation. This type is the "throw me
/// something meaningful" half of the system, [Failure] is the "hand the UI a
/// typed state" half.
class AppException implements Exception {
  /// Copy shown to the customer. Must already be user-safe: no stack traces,
  /// no raw status codes, no internals.
  final String message;

  /// Which retry, if any, is worth offering. Drives whether the UI shows a
  /// "Try again" affordance instead of a dead end.
  ///
  /// Defaults to false because an error that is not worth retrying is the common
  /// case, and offering "Try again" on a validation error just invites a loop.
  final bool isRetryable;

  const AppException(this.message, {this.isRetryable = false});

  @override
  String toString() => message;
}

/// The device could not reach the backend at all.
///
/// Separate from [AppException] because it is the one error that is genuinely
/// worth a silent retry, and because it is the one case where a raw `SocketException`
/// or `ClientException` must never reach the UI verbatim.
class NetworkException extends AppException {
  const NetworkException([
    super.message = 'No internet connection. Please check your network.',
  ]) : super(isRetryable: true);
}

/// The request was well-formed but the server rejected it (4xx/5xx).
///
/// [message] is intentionally generic. Putting the server's body in front of a
/// customer leaks internals and produces copy nobody approved.
class ServerException extends AppException {
  final int? statusCode;

  const ServerException([this.statusCode])
    : super('Something went wrong. Please try again.');
}

/// The user did something the app can explain better than the backend can.
///
/// [action] is the corrective verb pair shown under the message, e.g.
/// `('Retry', 'Cancel')`. Optional because not every error has a choice.
class ValidationException extends AppException {
  final String? actionLabel;
  final String? cancelLabel;

  const ValidationException(super.message, {this.actionLabel, this.cancelLabel})
    : super(isRetryable: true);
}
