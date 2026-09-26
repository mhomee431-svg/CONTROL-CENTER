import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/error/failures.dart';
import 'package:hyperlocal_app/core/storage/secure_storage_service.dart';
import 'package:hyperlocal_app/features/auth/domain/auth_repository.dart';
import 'package:hyperlocal_app/features/auth/domain/auth_service.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'auth_service_test.mocks.dart';

@GenerateMocks([AuthRepository, SecureStorageService])
void main() {
  late MockAuthRepository mockRepo;
  late MockSecureStorageService mockStorage;
  late AuthService service;

  setUp(() {
    mockRepo = MockAuthRepository();
    mockStorage = MockSecureStorageService();
    service = AuthService(mockRepo, mockStorage);
  });

  group('AuthService - Session persistence (app restart)', () {
    test('restoreSession returns null when no session stored', () async {
      when(mockStorage.getToken()).thenAnswer((_) async => null);
      when(mockStorage.getSessionId()).thenAnswer((_) async => null);

      final session = await service.restoreSession();

      expect(session, isNull);
    });

    test('restoreSession restores valid session after verifyOtp', () async {
      // Step 1: Login and persist
      when(mockStorage.getDeviceId()).thenAnswer((_) async => null);
      when(mockStorage.saveDeviceId(any)).thenAnswer((_) async => {});
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
          accessToken: 'persisted-token',
          refreshToken: 'persisted-refresh',
          sessionId: 'persisted-session',
          userId: 7,
          phoneNumber: '9999999999',
          name: 'Persist User',
          role: 'customer',
        ),
      );
      when(mockStorage.saveToken('persisted-token'))
          .thenAnswer((_) async => {});
      when(mockStorage.saveRefreshToken('persisted-refresh'))
          .thenAnswer((_) async => {});
      when(mockStorage.saveSessionId('persisted-session'))
          .thenAnswer((_) async => {});
      when(mockStorage.setGuestMode(false)).thenAnswer((_) async => {});

      await service.verifyOtp(
        phoneNumber: '9999999999',
        otpCode: '123456',
        isNewUser: false,
      );

      // Step 2: "App restart" - storage now returns persisted data
      when(mockStorage.getToken()).thenAnswer((_) async => 'persisted-token');
      when(mockStorage.getSessionId())
          .thenAnswer((_) async => 'persisted-session');
      when(mockStorage.getRefreshToken())
          .thenAnswer((_) async => 'persisted-refresh');
      when(mockStorage.getDeviceId()).thenAnswer((_) async => 'dev-1');

      final restored = await service.restoreSession();

      expect(restored, isNotNull);
      expect(restored!.isValid, isTrue);
      expect(restored.accessToken, 'persisted-token');
      expect(restored.sessionId, 'persisted-session');
    });
  });

  group('AuthService - sendOtp', () {
    test('passes through to repository', () async {
      when(mockRepo.sendOtp('9999999999')).thenAnswer((_) async => {});
      await service.sendOtp('9999999999');
      verify(mockRepo.sendOtp('9999999999')).called(1);
    });

    test('surfaces InvalidPhoneNumberFailure', () async {
      when(mockRepo.sendOtp('123'))
          .thenThrow(const InvalidPhoneNumberFailure());
      expect(
        () => service.sendOtp('123'),
        throwsA(isA<InvalidPhoneNumberFailure>()),
      );
    });
  });

  group('AuthService - logout', () {
    test('clears storage after backend revocation', () async {
      when(mockStorage.getRefreshToken()).thenAnswer((_) async => 'rt');
      when(mockStorage.getSessionId()).thenAnswer((_) async => 'sid');
      when(mockRepo.logout(refreshToken: 'rt', sessionId: 'sid'))
          .thenAnswer((_) async => {});
      when(mockStorage.clearAll()).thenAnswer((_) async => {});

      await service.logout();

      verify(mockStorage.clearAll()).called(1);
    });

    test('clears local state even if backend logout fails', () async {
      when(mockStorage.getRefreshToken()).thenAnswer((_) async => 'rt');
      when(mockStorage.getSessionId()).thenAnswer((_) async => 'sid');
      when(mockRepo.logout(refreshToken: 'rt', sessionId: 'sid'))
          .thenThrow(const NetworkFailure());
      when(mockStorage.clearAll()).thenAnswer((_) async => {});

      await service.logout();

      verify(mockStorage.clearAll()).called(1);
    });
  });

  group('AuthService - first-time user flag', () {
    test('isFirstTimeUser true when flag not set', () async {
      when(mockStorage.read(key: 'has_onboarded'))
          .thenAnswer((_) async => null);
      expect(await service.isFirstTimeUser(), isTrue);
    });

    test('markOnboarded then isFirstTimeUser false', () async {
      when(mockStorage.write(key: 'has_onboarded', value: 'true'))
          .thenAnswer((_) async => {});
      await service.markOnboarded();
      when(mockStorage.read(key: 'has_onboarded'))
          .thenAnswer((_) async => 'true');
      expect(await service.isFirstTimeUser(), isFalse);
    });
  });

  group('AuthService - Google Sign-In', () {
    test('persists the session returned by the repository', () async {
      when(mockStorage.getDeviceId()).thenAnswer((_) async => 'dev-google');
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
          userId: 9,
          name: 'Google Customer',
          role: 'customer',
        ),
      );
      when(mockStorage.saveToken('google-at')).thenAnswer((_) async => {});
      when(mockStorage.saveRefreshToken('google-rt'))
          .thenAnswer((_) async => {});
      when(mockStorage.saveSessionId('google-sid')).thenAnswer((_) async => {});
      when(mockStorage.setGuestMode(false)).thenAnswer((_) async => {});

      final session = await service.signInWithGoogle();

      expect(session.isValid, isTrue);
      expect(session.accessToken, 'google-at');
      expect(session.sessionId, 'google-sid');
      verify(
        mockRepo.signInWithGoogle(
          deviceId: 'dev-google',
          deviceName: authDeviceName,
          deviceType: authDeviceType,
          appVersion: authAppVersion,
        ),
      ).called(1);
    });
  });
}
