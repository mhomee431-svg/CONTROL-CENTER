import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_app/core/error/failures.dart';
import 'package:hyperlocal_app/core/storage/secure_storage_service.dart';
import 'package:hyperlocal_app/features/auth/domain/auth_repository.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'auth_controller_test.mocks.dart';

@GenerateMocks([AuthRepository, SecureStorageService])
void main() {
  late MockAuthRepository mockRepo;
  late MockSecureStorageService mockStorage;
  late ProviderContainer container;
  late AuthController controller;

  setUpAll(() {
    provideDummy<AuthResult>(
      const AuthResult(
        accessToken: 'dummy',
        refreshToken: 'dummy',
        sessionId: 'dummy',
      ),
    );
  });

  setUp(() {
    mockRepo = MockAuthRepository();
    mockStorage = MockSecureStorageService();

    // Stub common storage calls
    when(mockStorage.getToken()).thenAnswer((_) async => null);
    when(mockStorage.getSessionId()).thenAnswer((_) async => null);
    when(mockStorage.getRefreshToken()).thenAnswer((_) async => null);
    when(mockStorage.getDeviceId()).thenAnswer((_) async => null);
    when(mockStorage.saveDeviceId(any)).thenAnswer((_) async => {});
    when(mockStorage.saveToken(any)).thenAnswer((_) async => {});
    when(mockStorage.saveRefreshToken(any)).thenAnswer((_) async => {});
    when(mockStorage.saveSessionId(any)).thenAnswer((_) async => {});
    when(mockStorage.setGuestMode(any)).thenAnswer((_) async => {});
    when(mockStorage.clearAll()).thenAnswer((_) async => {});
    when(mockStorage.write(key: anyNamed('key'), value: anyNamed('value')))
        .thenAnswer((_) async => {});
    when(mockStorage.read(key: anyNamed('key'))).thenAnswer((_) async => null);
    when(mockStorage.isGuestMode()).thenAnswer((_) async => false);

    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepo),
        secureStorageProvider.overrideWithValue(mockStorage),
      ],
    );

    controller = container.read(authControllerProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  test('Initial state is AuthStatus.initial', () {
    expect(container.read(authControllerProvider).status, AuthStatus.initial);
  });

  test('checkAuthStatus: no session -> guest (guest-first)', () async {
    final restored = await controller.checkAuthStatus();
    expect(restored, isFalse);
    expect(container.read(authControllerProvider).status, AuthStatus.guest);
  });

  test('checkAuthStatus: guest mode -> guest', () async {
    when(mockStorage.isGuestMode()).thenAnswer((_) async => true);
    final restored = await controller.checkAuthStatus();
    expect(restored, isFalse);
    expect(container.read(authControllerProvider).status, AuthStatus.guest);
  });

  test('checkAuthStatus: valid session -> authenticated', () async {
    when(mockStorage.getToken()).thenAnswer((_) async => 'jwt');
    when(mockStorage.getSessionId()).thenAnswer((_) async => 's1');
    when(mockStorage.getRefreshToken()).thenAnswer((_) async => 'rt');
    when(mockStorage.getDeviceId()).thenAnswer((_) async => 'd1');
    when(mockRepo.refreshToken('rt', deviceId: 'd1')).thenAnswer(
      (_) async => const AuthResult(
        accessToken: 'new-jwt',
        refreshToken: 'rotated-rt',
        sessionId: 's1',
      ),
    );

    final restored = await controller.checkAuthStatus();
    expect(restored, isTrue);
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
  });

  test('checkAuthStatus: expired session -> guest (no login wall)', () async {
    when(mockStorage.getToken()).thenAnswer((_) async => 'jwt');
    when(mockStorage.getSessionId()).thenAnswer((_) async => 's1');
    when(mockStorage.getRefreshToken()).thenAnswer((_) async => 'rt');
    when(mockStorage.getDeviceId()).thenAnswer((_) async => 'd1');
    when(mockRepo.refreshToken('rt', deviceId: 'd1'))
        .thenThrow(const SessionExpiredFailure());

    final restored = await controller.checkAuthStatus();
    expect(restored, isFalse);
    expect(container.read(authControllerProvider).status, AuthStatus.guest);
  });

  test('sendOtp: success -> otpSent with phone', () async {
    when(mockRepo.sendOtp('9999999999')).thenAnswer((_) async => {});
    final ok = await controller.sendOtp('9999999999');
    expect(ok, isTrue);
    final state = container.read(authControllerProvider);
    expect(state.status, AuthStatus.otpSent);
    expect(state.phoneNumber, '9999999999');
  });

  test('sendOtp: invalid phone -> error state', () async {
    when(mockRepo.sendOtp('123')).thenThrow(const InvalidPhoneNumberFailure());
    final ok = await controller.sendOtp('123');
    expect(ok, isFalse);
    expect(container.read(authControllerProvider).status, AuthStatus.error);
  });

  test('sendOtp: network failure -> error state', () async {
    when(mockRepo.sendOtp('9999999999')).thenThrow(const NetworkFailure());
    final ok = await controller.sendOtp('9999999999');
    expect(ok, isFalse);
    expect(container.read(authControllerProvider).status, AuthStatus.error);
  });

  test('verifyOtp: success -> authenticated + session persisted', () async {
    const result = AuthResult(
      accessToken: 'access',
      refreshToken: 'refresh',
      sessionId: 'sid',
      userId: 1,
      phoneNumber: '9999999999',
      name: 'Test',
      role: 'customer',
    );
    when(
      mockRepo.verifyOtp(
        phoneNumber: '9999999999',
        otpCode: '123456',
        deviceId: anyNamed('deviceId'),
        deviceName: anyNamed('deviceName'),
        deviceType: anyNamed('deviceType'),
        appVersion: anyNamed('appVersion'),
      ),
    ).thenAnswer((_) async => result);

    final ok = await controller.verifyOtp(
      phoneNumber: '9999999999',
      otpCode: '123456',
      isNewUser: false,
    );

    expect(ok, isTrue);
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
    verify(mockStorage.saveToken('access')).called(1);
    verify(mockStorage.saveRefreshToken('refresh')).called(1);
    verify(mockStorage.saveSessionId('sid')).called(1);
  });

  test('verifyOtp: invalid OTP -> error with message', () async {
    when(
      mockRepo.verifyOtp(
        phoneNumber: '9999999999',
        otpCode: '000000',
        deviceId: anyNamed('deviceId'),
        deviceName: anyNamed('deviceName'),
        deviceType: anyNamed('deviceType'),
        appVersion: anyNamed('appVersion'),
      ),
    ).thenThrow(const InvalidOtpFailure());

    final ok = await controller.verifyOtp(
      phoneNumber: '9999999999',
      otpCode: '000000',
      isNewUser: false,
    );

    expect(ok, isFalse);
    final state = container.read(authControllerProvider);
    expect(state.status, AuthStatus.error);
    expect(state.errorMessage, contains('Invalid OTP'));
  });

  test('verifyOtp: expired OTP -> error with message', () async {
    when(
      mockRepo.verifyOtp(
        phoneNumber: '9999999999',
        otpCode: '111111',
        deviceId: anyNamed('deviceId'),
        deviceName: anyNamed('deviceName'),
        deviceType: anyNamed('deviceType'),
        appVersion: anyNamed('appVersion'),
      ),
    ).thenThrow(const ExpiredOtpFailure());

    final ok = await controller.verifyOtp(
      phoneNumber: '9999999999',
      otpCode: '111111',
      isNewUser: false,
    );

    expect(ok, isFalse);
    final state = container.read(authControllerProvider);
    expect(state.status, AuthStatus.error);
    expect(state.errorMessage, contains('expired'));
  });

  test('verifyOtp: too many attempts -> error', () async {
    when(
      mockRepo.verifyOtp(
        phoneNumber: '9999999999',
        otpCode: '222222',
        deviceId: anyNamed('deviceId'),
        deviceName: anyNamed('deviceName'),
        deviceType: anyNamed('deviceType'),
        appVersion: anyNamed('appVersion'),
      ),
    ).thenThrow(const TooManyAttemptsFailure());

    final ok = await controller.verifyOtp(
      phoneNumber: '9999999999',
      otpCode: '222222',
      isNewUser: false,
    );

    expect(ok, isFalse);
    expect(container.read(authControllerProvider).status, AuthStatus.error);
  });

  test('verifyOtp: new user -> register flow used', () async {
    when(
      mockRepo.register(
        phoneNumber: '9999999999',
        otpCode: '444444',
        name: anyNamed('name'),
        deviceId: anyNamed('deviceId'),
        deviceName: anyNamed('deviceName'),
        deviceType: anyNamed('deviceType'),
        appVersion: anyNamed('appVersion'),
      ),
    ).thenAnswer(
      (_) async => const AuthResult(
        accessToken: 'at',
        refreshToken: 'rt',
        sessionId: 'sid',
        userId: 2,
        phoneNumber: '9999999999',
        name: 'New User',
        role: 'customer',
        isNewUser: true,
      ),
    );

    final ok = await controller.verifyOtp(
      phoneNumber: '9999999999',
      otpCode: '444444',
      isNewUser: true,
    );

    expect(ok, isTrue);
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
    verify(
      mockRepo.register(
        phoneNumber: '9999999999',
        otpCode: '444444',
        name: anyNamed('name'),
        deviceId: anyNamed('deviceId'),
        deviceName: anyNamed('deviceName'),
        deviceType: anyNamed('deviceType'),
        appVersion: anyNamed('appVersion'),
      ),
    ).called(1);
  });

  test('logout: clears session -> unauthenticated', () async {
    when(mockStorage.getRefreshToken()).thenAnswer((_) async => 'rt');
    when(mockStorage.getSessionId()).thenAnswer((_) async => 'sid');
    when(mockRepo.logout(refreshToken: 'rt', sessionId: 'sid'))
        .thenAnswer((_) async => {});

    await controller.logout();

    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    verify(mockStorage.clearAll()).called(1);
  });

  test('continueAsGuest: sets guest mode', () async {
    await controller.continueAsGuest();
    expect(container.read(authControllerProvider).status, AuthStatus.guest);
    verify(mockStorage.setGuestMode(true)).called(1);
  });

  group('signInWithGoogle', () {
    test('success -> authenticated and session persisted', () async {
      when(
        mockRepo.signInWithGoogle(
          deviceId: anyNamed('deviceId'),
          deviceName: anyNamed('deviceName'),
          deviceType: anyNamed('deviceType'),
          appVersion: anyNamed('appVersion'),
        ),
      ).thenAnswer(
        (_) async => const AuthResult(
          accessToken: 'google-at',
          refreshToken: 'google-rt',
          sessionId: 'google-sid',
          userId: 5,
          name: 'Google User',
          role: 'customer',
        ),
      );

      final ok = await controller.signInWithGoogle();

      expect(ok, isTrue);
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.authenticated,
      );
      verify(mockStorage.saveToken('google-at')).called(1);
      verify(mockStorage.setGuestMode(false)).called(1);
    });

    test('cancelled -> guest, no error message', () async {
      when(
        mockRepo.signInWithGoogle(
          deviceId: anyNamed('deviceId'),
          deviceName: anyNamed('deviceName'),
          deviceType: anyNamed('deviceType'),
          appVersion: anyNamed('appVersion'),
        ),
      ).thenThrow(const GoogleSignInCancelledFailure());

      final ok = await controller.signInWithGoogle();

      expect(ok, isFalse);
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.guest);
      expect(state.errorMessage, isNull);
    });

    test('backend rejection -> error state with message', () async {
      when(
        mockRepo.signInWithGoogle(
          deviceId: anyNamed('deviceId'),
          deviceName: anyNamed('deviceName'),
          deviceType: anyNamed('deviceType'),
          appVersion: anyNamed('appVersion'),
        ),
      ).thenThrow(const ServerFailure('Google account link conflict'));

      final ok = await controller.signInWithGoogle();

      expect(ok, isFalse);
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.error);
      expect(state.errorMessage, contains('link conflict'));
    });
  });

  group('error classification (UI recovery affordances)', () {
    Future<void> stubVerifyFailure(Object failure, String otp) async {
      when(
        mockRepo.verifyOtp(
          phoneNumber: '9999999999',
          otpCode: otp,
          deviceId: anyNamed('deviceId'),
          deviceName: anyNamed('deviceName'),
          deviceType: anyNamed('deviceType'),
          appVersion: anyNamed('appVersion'),
        ),
      ).thenThrow(failure);
      await controller.verifyOtp(
        phoneNumber: '9999999999',
        otpCode: otp,
        isNewUser: false,
      );
    }

    test('invalid OTP -> AuthErrorKind.invalidOtp', () async {
      await stubVerifyFailure(const InvalidOtpFailure(), '000000');
      expect(
        container.read(authControllerProvider).errorKind,
        AuthErrorKind.invalidOtp,
      );
    });

    test('expired OTP -> AuthErrorKind.expiredOtp', () async {
      await stubVerifyFailure(const ExpiredOtpFailure(), '111111');
      expect(
        container.read(authControllerProvider).errorKind,
        AuthErrorKind.expiredOtp,
      );
    });

    test('too many attempts -> AuthErrorKind.rateLimited', () async {
      await stubVerifyFailure(const TooManyAttemptsFailure(), '222222');
      expect(
        container.read(authControllerProvider).errorKind,
        AuthErrorKind.rateLimited,
      );
    });

    test('network failure -> AuthErrorKind.network', () async {
      await stubVerifyFailure(const NetworkFailure(), '333333');
      expect(
        container.read(authControllerProvider).errorKind,
        AuthErrorKind.network,
      );
    });

    test('unclassified failure -> AuthErrorKind.unknown', () async {
      await stubVerifyFailure(const ServerFailure('boom'), '444444');
      expect(
        container.read(authControllerProvider).errorKind,
        AuthErrorKind.unknown,
      );
    });

    test('resend rate limit -> AuthErrorKind.rateLimited', () async {
      when(mockRepo.sendOtp('9999999999'))
          .thenThrow(const OtpRateLimitFailure());
      final ok = await controller.sendOtp('9999999999');
      expect(ok, isFalse);
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.error);
      expect(state.errorKind, AuthErrorKind.rateLimited);
    });
  });

  group('cancelOtpVerification (cancelled flow)', () {
    test('clears the pending otpSent state back to guest', () async {
      when(mockRepo.sendOtp('9999999999')).thenAnswer((_) async => {});
      await controller.sendOtp('9999999999');
      expect(container.read(authControllerProvider).status, AuthStatus.otpSent);

      await controller.cancelOtpVerification();

      expect(container.read(authControllerProvider).status, AuthStatus.guest);
    });

    test(
      'also clears an error state left behind by a failed attempt',
      () async {
        when(mockRepo.sendOtp('9999999999')).thenThrow(const NetworkFailure());
        await controller.sendOtp('9999999999');
        expect(container.read(authControllerProvider).status, AuthStatus.error);

        await controller.cancelOtpVerification();

        final state = container.read(authControllerProvider);
        expect(state.status, AuthStatus.guest);
        expect(state.errorMessage, isNull);
      },
    );

    test('never downgrades an authenticated session', () async {
      when(
        mockRepo.verifyOtp(
          phoneNumber: '9999999999',
          otpCode: '123456',
          deviceId: anyNamed('deviceId'),
          deviceName: anyNamed('deviceName'),
          deviceType: anyNamed('deviceType'),
          appVersion: anyNamed('appVersion'),
        ),
      ).thenAnswer(
        (_) async => const AuthResult(
          accessToken: 'access',
          refreshToken: 'refresh',
          sessionId: 'sid',
        ),
      );
      await controller.verifyOtp(
        phoneNumber: '9999999999',
        otpCode: '123456',
        isNewUser: false,
      );
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.authenticated,
      );

      await controller.cancelOtpVerification();

      expect(
        container.read(authControllerProvider).status,
        AuthStatus.authenticated,
      );
    });
  });
}
