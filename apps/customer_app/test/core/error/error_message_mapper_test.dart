import 'dart:async';
import 'dart:io';

import 'package:hyperlocal_app/core/error/app_exception.dart';
import 'package:hyperlocal_app/core/error/error_message_mapper.dart';
import 'package:hyperlocal_app/core/error/failures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ErrorMessageMapper produces customer-meaningful copy', () {
    test('a Failure renders the copy it already carries', () {
      expect(
        ErrorMessageMapper.message(const InvalidOtpFailure()),
        contains('Invalid OTP'),
      );
      expect(
        ErrorMessageMapper.message(const NetworkFailure()),
        contains('No internet connection'),
      );
    });

    test('an AppException renders the copy it already carries', () {
      expect(
        ErrorMessageMapper.message(
          const ValidationException('Enter your name.'),
        ),
        'Enter your name.',
      );
      expect(
        ErrorMessageMapper.message(const ServerException(500)),
        isNot(contains('500')),
      );
    });

    test('a server status code never reaches the customer', () {
      // The generic copy is deliberate. `ServerException(503)` interpolated
      // would be both an internal detail and copy nobody approved.
      expect(
        ErrorMessageMapper.message(const ServerException(503)),
        isNot(contains('503')),
      );
    });

    test('platform errors become advice, not SDK vocabulary', () {
      const socket = SocketException('Connection failed', osError: null);
      final mapped = ErrorMessageMapper.message(socket);
      expect(mapped, contains('No internet connection'));
      expect(mapped, isNot(contains('Connection failed')));
      expect(mapped, isNot(contains('SocketException')));
    });

    test('a timeout reads as slow, not as a crash', () {
      final mapped = ErrorMessageMapper.message(TimeoutException('deadline'));
      expect(mapped, contains('taking too long'));
    });

    test(
      'an unknown error degrades to generic copy WITHOUT interpolating it',
      () {
        // The critical case: a raw leak would put "Exception: <internal>" in a
        // banner. This must not be `'$error'`.
        final mapped = ErrorMessageMapper.message(
          Exception('db://user:pass@internal-host 500'),
        );
        expect(mapped, ErrorMessageMapper.genericMessage);
        expect(mapped, isNot(contains('internal-host')));
        expect(mapped, isNot(contains('Exception:')));
      },
    );

    test('a null error still yields something renderable', () {
      expect(
        ErrorMessageMapper.message(null),
        ErrorMessageMapper.genericMessage,
      );
      expect(ErrorMessageMapper.message(null), isNotEmpty);
    });

    test('message() never returns null or empty for a non-cancellation', () {
      for (final e in <Object?>[null, Exception(), StateError('x'), 42]) {
        if (ErrorMessageMapper.isSilent(e)) continue;
        expect(ErrorMessageMapper.message(e), isNotEmpty);
      }
    });
  });

  group('cancellation stays silent', () {
    test('a cancelled Google sign-in renders nothing', () {
      // Showing "Google sign-in was cancelled." as an ERROR is wrong: the
      // customer did exactly what they meant to.
      const cancelled = GoogleSignInCancelledFailure();
      expect(ErrorMessageMapper.isSilent(cancelled), isTrue);
      expect(ErrorMessageMapper.message(cancelled), isEmpty);
    });

    test('messageOrFallback gives a snackbar something usable', () {
      const cancelled = GoogleSignInCancelledFailure();
      expect(
        ErrorMessageMapper.messageOrFallback(cancelled),
        ErrorMessageMapper.genericMessage,
      );
    });

    test('a timeout is NOT silent: the customer is still waiting', () {
      // Guards against over-broad cancellation. Silencing a timeout leaves the
      // customer staring at a spinner that never resolves.
      expect(ErrorMessageMapper.isSilent(TimeoutException('x')), isFalse);
      expect(
        ErrorMessageMapper.message(TimeoutException('x')),
        contains('taking too long'),
      );
    });

    test('a StateError is a bug, not a cancellation', () {
      expect(ErrorMessageMapper.isSilent(StateError('x')), isFalse);
      expect(
        ErrorMessageMapper.message(StateError('x')),
        ErrorMessageMapper.genericMessage,
      );
    });
  });

  group('the hierarchy stays closed', () {
    test('every Failure offers a default message that is non-empty', () {
      final failures = <Failure>[
        const ServerFailure(),
        const NetworkFailure(),
        const InvalidOtpFailure(),
        const ExpiredOtpFailure(),
        const TooManyAttemptsFailure(),
        const InvalidPhoneNumberFailure(),
        const OtpRateLimitFailure(),
        const SessionExpiredFailure(),
        const GoogleSignInCancelledFailure(),
      ];
      for (final f in failures) {
        expect(
          f.message,
          isNotEmpty,
          reason: '${f.runtimeType} would render a blank banner',
        );
      }
    });

    test('AppException.toString() is the message, not a prefix', () {
      expect(const AppException('Nope.').toString(), 'Nope.');
      expect(
        const AppException('Nope.').toString(),
        isNot(contains('AppException')),
      );
    });
  });
}
