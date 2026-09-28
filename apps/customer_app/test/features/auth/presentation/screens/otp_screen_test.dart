import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/core/error/failures.dart';
import 'package:hyperlocal_app/core/storage/secure_storage_service.dart';
import 'package:hyperlocal_app/features/auth/domain/auth_repository.dart';
import 'package:hyperlocal_app/features/auth/presentation/screens/otp_screen.dart';

/// In-memory storage — only the members the auth service touches are real,
/// the rest fall back to `noSuchMethod`.
class _FakeStorage implements SecureStorageService {
  final Map<String, String> values = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<String?> getToken() async => values['auth_token'];

  @override
  Future<void> saveToken(String token) async => values['auth_token'] = token;

  @override
  Future<String?> getRefreshToken() async => values['refresh_token'];

  @override
  Future<void> saveRefreshToken(String refreshToken) async =>
      values['refresh_token'] = refreshToken;

  @override
  Future<String?> getSessionId() async => values['session_id'];

  @override
  Future<void> saveSessionId(String sessionId) async =>
      values['session_id'] = sessionId;

  @override
  Future<String?> getDeviceId() async => values['device_id'];

  @override
  Future<void> saveDeviceId(String deviceId) async =>
      values['device_id'] = deviceId;

  @override
  Future<void> setGuestMode(bool isGuest) async =>
      values['is_guest'] = isGuest.toString();

  @override
  Future<bool> isGuestMode() async => values['is_guest'] == 'true';

  @override
  Future<void> clearAll() async => values.clear();
}

/// Configurable repository fake — records calls and throws the failure the
/// test asks for, mirroring the real repository's error contract.
class _FakeAuthRepo implements AuthRepository {
  Object? sendError;
  Object? verifyError;
  int sendCalls = 0;
  int verifyCalls = 0;

  @override
  Future<void> sendOtp(String phoneNumber) async {
    sendCalls++;
    final error = sendError;
    if (error != null) throw error;
  }

  @override
  Future<AuthResult> verifyOtp({
    required String phoneNumber,
    required String otpCode,
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? appVersion,
  }) async {
    verifyCalls++;
    final error = verifyError;
    if (error != null) throw error;
    return const AuthResult(
      accessToken: 'jwt',
      refreshToken: 'refresh',
      sessionId: 'session-1',
      phoneNumber: '+919999999999',
    );
  }

  @override
  Future<AuthResult> register({
    required String phoneNumber,
    required String otpCode,
    required String name,
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? appVersion,
  }) => throw UnimplementedError();

  @override
  Future<AuthResult> signInWithGoogle({
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? appVersion,
  }) => throw UnimplementedError();

  @override
  Future<AuthResult> refreshToken(String refreshToken, {String? deviceId}) =>
      throw UnimplementedError();

  @override
  Future<void> logout({
    String? refreshToken,
    String? sessionId,
    bool revokeAll = false,
  }) async {}
}

Future<void> _pumpOtpScreen(
  WidgetTester tester, {
  required _FakeAuthRepo repo,
  required _FakeStorage storage,
}) async {
  final router = GoRouter(
    initialLocation: '/otp',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
      GoRoute(
        path: '/otp',
        builder: (_, _) =>
            const OtpVerificationScreen(phoneNumber: '+919999999999'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        secureStorageProvider.overrideWithValue(storage),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

TextButton _resendButton(WidgetTester tester) =>
    tester.widget<TextButton>(find.byType(TextButton));

void main() {
  late _FakeAuthRepo repo;
  late _FakeStorage storage;

  setUp(() {
    repo = _FakeAuthRepo();
    storage = _FakeStorage();
  });

  testWidgets('resend is locked behind the 60s countdown, then unlocks', (
    tester,
  ) async {
    await _pumpOtpScreen(tester, repo: repo, storage: storage);

    expect(find.text('Resend OTP in 60s'), findsOneWidget);
    expect(_resendButton(tester).onPressed, isNull);

    await tester.pump(const Duration(seconds: 59));
    expect(find.text('Resend OTP in 1s'), findsOneWidget);
    expect(_resendButton(tester).onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend OTP'), findsOneWidget);
    expect(_resendButton(tester).onPressed, isNotNull);
  });

  testWidgets('resend re-requests the OTP and restarts the countdown', (
    tester,
  ) async {
    await _pumpOtpScreen(tester, repo: repo, storage: storage);

    await tester.pump(const Duration(seconds: 60));
    expect(_resendButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('Resend OTP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.sendCalls, 1);
    expect(find.text('Resend OTP in 60s'), findsOneWidget);
    expect(_resendButton(tester).onPressed, isNull);
    expect(find.text('A new OTP has been sent.'), findsOneWidget);
  });

  testWidgets('wrong OTP shows the friendly message and clears the field', (
    tester,
  ) async {
    repo.verifyError = const InvalidOtpFailure();
    await _pumpOtpScreen(tester, repo: repo, storage: storage);

    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verify & Login'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.verifyCalls, 1);
    expect(
      find.text('Invalid OTP entered. Please check and try again.'),
      findsOneWidget,
    );
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('expired OTP unlocks resend immediately', (tester) async {
    repo.verifyError = const ExpiredOtpFailure();
    await _pumpOtpScreen(tester, repo: repo, storage: storage);

    expect(_resendButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verify & Login'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('This OTP has expired. Please request a new one.'),
      findsOneWidget,
    );
    expect(find.text('Resend OTP'), findsOneWidget);
    expect(_resendButton(tester).onPressed, isNotNull);
  });

  testWidgets('network failure surfaces the sanitized connectivity message', (
    tester,
  ) async {
    repo.verifyError = const NetworkFailure();
    await _pumpOtpScreen(tester, repo: repo, storage: storage);

    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verify & Login'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No internet connection'), findsOneWidget);
    final verify = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(verify.onPressed, isNotNull);
  });

  testWidgets('successful verification navigates home', (tester) async {
    await _pumpOtpScreen(tester, repo: repo, storage: storage);

    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verify & Login'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('HOME'), findsOneWidget);
  });
}
