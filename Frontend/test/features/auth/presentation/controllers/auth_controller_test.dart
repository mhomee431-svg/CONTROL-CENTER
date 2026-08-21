import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_customer_app/core/error/failures.dart';
import 'package:hyperlocal_customer_app/core/storage/secure_storage_service.dart';
import 'package:hyperlocal_customer_app/features/auth/domain/auth_repository.dart';
import 'package:hyperlocal_customer_app/features/auth/presentation/controllers/auth_controller.dart';
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
        accessToken: 'dummy-token',
        refreshToken: 'dummy-refresh',
        sessionId: 'dummy-session',
      ),
    );
  });

  setUp(() {
    mockRepo = MockAuthRepository();
    mockStorage = MockSecureStorageService();

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

  test('Initial state should be AuthStatus.initial', () {
    expect(container.read(authControllerProvider).status, AuthStatus.initial);
  });

  test('checkAuthStatus with no token and no guest mode sets unauthenticated', () async {
    when(mockStorage.getToken()).thenAnswer((_) async => null);
    when(mockStorage.isGuestMode()).thenAnswer((_) async => false);

    await controller.checkAuthStatus();

    expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
  });

  test('checkAuthStatus with token sets authenticated', () async {
    when(mockStorage.getToken()).thenAnswer((_) async => 'mock_jwt_token');
    when(mockStorage.isGuestMode()).thenAnswer((_) async => false);

    await controller.checkAuthStatus();

    expect(container.read(authControllerProvider).status, AuthStatus.authenticated);
  });

  test('checkAuthStatus with guest mode sets guest', () async {
    when(mockStorage.getToken()).thenAnswer((_) async => null);
    when(mockStorage.isGuestMode()).thenAnswer((_) async => true);

    await controller.checkAuthStatus();

    expect(container.read(authControllerProvider).status, AuthStatus.guest);
  });

  test('Guest mode updates state to guest correctly', () async {
    when(mockStorage.setGuestMode(true)).thenAnswer((_) async => {});

    await controller.continueAsGuest();

    expect(container.read(authControllerProvider).status, AuthStatus.guest);
    verify(mockStorage.setGuestMode(true)).called(1);
  });

  test('sendOtp success returns true and sets unauthenticated', () async {
    when(mockRepo.sendOtp('9999999999')).thenAnswer((_) async => {});

    final success = await controller.sendOtp('9999999999');

    expect(success, isTrue);
    expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    verify(mockRepo.sendOtp('9999999999')).called(1);
  });

  test('sendOtp failure sets error state', () async {
    when(mockRepo.sendOtp('123'))
        .thenThrow(const ServerFailure('Invalid phone number format'));

    final success = await controller.sendOtp('123');

    expect(success, isFalse);
    expect(container.read(authControllerProvider).status, AuthStatus.error);
    expect(container.read(authControllerProvider).errorMessage, 'Invalid phone number format');
  });

  test('verifyOtp success saves tokens and sets authenticated', () async {
    const authResult = AuthResult(
      accessToken: 'mock_jwt_token_header.payload.signature',
      refreshToken: 'mock_refresh_token',
      sessionId: 'mock-session-id',
      userId: 1,
      phoneNumber: '9999999999',
      name: 'Test User',
      role: 'customer',
    );

    when(mockStorage.getDeviceId()).thenAnswer((_) async => null);
    when(mockStorage.saveDeviceId(any)).thenAnswer((_) async => {});
    when(mockRepo.verifyOtp(
      phoneNumber: '9999999999',
      otpCode: '123456',
      deviceId: anyNamed('deviceId'),
      deviceName: anyNamed('deviceName'),
      deviceType: anyNamed('deviceType'),
      appVersion: anyNamed('appVersion'),
    )).thenAnswer((_) async => authResult);
    when(mockStorage.saveToken('mock_jwt_token_header.payload.signature'))
        .thenAnswer((_) async => {});
    when(mockStorage.saveRefreshToken('mock_refresh_token'))
        .thenAnswer((_) async => {});
    when(mockStorage.saveSessionId('mock-session-id'))
        .thenAnswer((_) async => {});
    when(mockStorage.setGuestMode(false)).thenAnswer((_) async => {});

    final success = await controller.verifyOtp('9999999999', '123456');

    expect(success, isTrue);
    expect(container.read(authControllerProvider).status, AuthStatus.authenticated);
    verify(mockStorage.saveToken('mock_jwt_token_header.payload.signature')).called(1);
    verify(mockStorage.saveRefreshToken('mock_refresh_token')).called(1);
    verify(mockStorage.saveSessionId('mock-session-id')).called(1);
    verify(mockStorage.setGuestMode(false)).called(1);
  });

  test('Failed OTP verification sets error state', () async {
    when(mockStorage.getDeviceId()).thenAnswer((_) async => null);
    when(mockStorage.saveDeviceId(any)).thenAnswer((_) async => {});
    when(mockRepo.verifyOtp(
      phoneNumber: '9999999999',
      otpCode: '000000',
      deviceId: anyNamed('deviceId'),
      deviceName: anyNamed('deviceName'),
      deviceType: anyNamed('deviceType'),
      appVersion: anyNamed('appVersion'),
    )).thenThrow(const ServerFailure('Invalid OTP entered'));

    await controller.verifyOtp('9999999999', '000000');

    expect(container.read(authControllerProvider).status, AuthStatus.error);
    expect(container.read(authControllerProvider).errorMessage, 'Invalid OTP entered');
  });

  test('logout clears storage and sets unauthenticated', () async {
    when(mockStorage.getRefreshToken()).thenAnswer((_) async => null);
    when(mockStorage.getSessionId()).thenAnswer((_) async => null);
    when(mockStorage.clearAll()).thenAnswer((_) async => {});

    await controller.logout();

    expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    verify(mockStorage.clearAll()).called(1);
  });

  test('refreshAccessToken with valid refresh token updates token', () async {
    when(mockStorage.getRefreshToken()).thenAnswer((_) async => 'old-refresh');
    when(mockStorage.getDeviceId()).thenAnswer((_) async => 'dev-123');
    when(mockRepo.refreshToken('old-refresh', deviceId: 'dev-123'))
        .thenAnswer((_) async => 'new-access-token');
    when(mockStorage.saveToken('new-access-token')).thenAnswer((_) async => {});

    final success = await controller.refreshAccessToken();

    expect(success, isTrue);
    expect(container.read(authControllerProvider).status, AuthStatus.authenticated);
    verify(mockStorage.saveToken('new-access-token')).called(1);
  });

  test('refreshAccessToken with no refresh token sets unauthenticated', () async {
    when(mockStorage.getRefreshToken()).thenAnswer((_) async => null);

    final success = await controller.refreshAccessToken();

    expect(success, isFalse);
    expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
  });
}