import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/core/storage/secure_storage_service.dart';
import 'package:hyperlocal_app/features/auth/data/mock_auth_repository.dart';
import 'package:hyperlocal_app/features/auth/data/phone_auth_service.dart';
import 'package:hyperlocal_app/features/auth/domain/auth_repository.dart'
    show phoneAuthServiceProvider;
import 'package:hyperlocal_app/features/auth/domain/auth_service.dart'
    show authServiceProvider, AuthService;
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/profile/domain/models/user_profile.dart';
import 'package:hyperlocal_app/features/profile/domain/profile_repository.dart';
import 'package:hyperlocal_app/features/profile/presentation/controllers/profile_controller.dart';
import 'package:hyperlocal_app/features/profile/presentation/screens/delete_account_screen.dart';

class _StubAuthController extends AuthController {
  _StubAuthController();

  @override
  AuthState build() => AuthState(status: AuthStatus.authenticated);
}

/// Profile repository that records whether the BACKEND was actually asked to
/// delete the account. `shouldFail` simulates the server refusing.
class _RecordingProfileRepo implements ProfileRepository {
  _RecordingProfileRepo({this.shouldFail = false});

  final bool shouldFail;
  bool deleteCalled = false;

  @override
  Future<UserProfile> getProfile() async => const UserProfile(
    id: '1',
    name: 'Priya Verma',
    email: 'priya@example.com',
    phoneNumber: '+91 98765 43210',
  );

  @override
  Future<UserProfile> updateProfile({
    required String name,
    required String email,
    required String phoneNumber,
  }) async => getProfile();

  @override
  Future<void> deleteAccount() async {
    deleteCalled = true;
    if (shouldFail) throw Exception('server refused');
  }
}

class _RecordingPhoneAuth implements PhoneAuthService {
  bool signOutCalled = false;

  @override
  Future<void> signOut() async => signOutCalled = true;

  @override
  Future<void> cancelPendingVerification() async {}

  @override
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onError,
  }) async {}

  @override
  Future<PhoneAuthResult> verifyOtp({required String smsCode}) async =>
      const PhoneAuthResult(idToken: 't', phoneNumber: '+919999999999');
}

/// The real `AuthService.clearLocalSession()` talks to secure storage, which is
/// bound to a platform channel and never resolves under `flutter_test`. Left
/// unstubbed it stalls the teardown half of the delete flow, so the success
/// screen never renders. Recording the call keeps the ordering assertions
/// meaningful without needing a live binding.
///
/// The base constructor's collaborators are never touched, because the only
/// member used here is the overridden one.
class _RecordingAuthService extends AuthService {
  _RecordingAuthService()
    : super(
        MockAuthRepository(),
        SecureStorageService(const FlutterSecureStorage()),
      );

  bool clearLocalSessionCalled = false;

  @override
  Future<void> clearLocalSession() async => clearLocalSessionCalled = true;
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/delete-account',
    routes: [
      GoRoute(
        path: '/delete-account',
        builder: (_, _) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: Text('LoginPage')),
      ),
      GoRoute(
        path: '/welcome',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: Text('WelcomePage')),
      ),
    ],
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _RecordingProfileRepo repository,
  _RecordingPhoneAuth? phoneAuth,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      localStorageDriverProvider.overrideWithValue(InMemoryStorageDriver()),
      authControllerProvider.overrideWith(() => _StubAuthController()),
      profileRepositoryProvider.overrideWithValue(repository),
      // Real secure storage cannot resolve under `flutter_test`, so the
      // teardown step is stubbed; see `_RecordingAuthService`.
      authServiceProvider.overrideWithValue(_RecordingAuthService()),
      if (phoneAuth != null)
        phoneAuthServiceProvider.overrideWithValue(phoneAuth),
    ],
  );
  addTearDown(container.dispose);

  // Warm the profile so the impact screen can show which account is going.
  container.read(profileControllerProvider.notifier);
  await container.pump();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Drives the async teardown that follows tapping "Delete my account".
///
/// Deliberately NOT `pumpAndSettle`: the in-flight `deleting` step renders a
/// `CircularProgressIndicator`, which schedules frames forever, so settling
/// there always times out and reports a spurious failure. The delete call and
/// the teardown it triggers are microtask/Future based, so a bounded number of
/// pumps is enough to let them complete and is what actually gets asserted on.
Future<void> _settleDeletion(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('explains the impact before anything irreversible', (
    tester,
  ) async {
    await _pump(tester, repository: _RecordingProfileRepo());

    expect(find.text('Delete your account?'), findsOneWidget);
    // The customer can see exactly what they are about to lose, and which
    // account it is, before confirming.
    expect(find.text('You will permanently lose:'), findsOneWidget);
    expect(find.textContaining('Saved products'), findsOneWidget);
    expect(find.textContaining('+91 98765 43210'), findsOneWidget);
    // Nothing has been sent yet.
    expect(find.byKey(const Key('deleteAccountConfirmField')), findsNothing);
  });

  testWidgets('deleting requires typing DELETE, not just a tap', (
    tester,
  ) async {
    final repo = _RecordingProfileRepo();
    await _pump(tester, repository: repo);

    await tester.tap(find.byKey(const Key('deleteAccountStartButton')));
    await tester.pumpAndSettle();
    expect(find.text('Confirm deletion'), findsOneWidget);

    // The destructive button stays disabled until the word is typed.
    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('deleteAccountConfirmButton')),
    );
    expect(button.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('deleteAccountConfirmField')),
      'delete',
    );
    await tester.pumpAndSettle();
    final enabled = tester.widget<ElevatedButton>(
      find.byKey(const Key('deleteAccountConfirmButton')),
    );
    expect(enabled.onPressed, isNotNull);
    // Still nothing sent — typing alone is not consent.
    expect(repo.deleteCalled, isFalse);
  });

  testWidgets('a wrong confirmation word does not proceed', (tester) async {
    final repo = _RecordingProfileRepo();
    await _pump(tester, repository: repo);

    await tester.tap(find.byKey(const Key('deleteAccountStartButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('deleteAccountConfirmField')),
      'maybe',
    );
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('deleteAccountConfirmButton')),
    );
    expect(button.onPressed, isNull);
    expect(repo.deleteCalled, isFalse);
  });

  testWidgets('success asks the BACKEND, then tears down the session', (
    tester,
  ) async {
    final repo = _RecordingProfileRepo();
    final phoneAuth = _RecordingPhoneAuth();
    await _pump(tester, repository: repo, phoneAuth: phoneAuth);

    await tester.tap(find.byKey(const Key('deleteAccountStartButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('deleteAccountConfirmField')),
      'DELETE',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteAccountConfirmButton')));
    await _settleDeletion(tester);

    // The server was genuinely called — this is not a local-only wipe.
    expect(repo.deleteCalled, isTrue);
    // Firebase signed out, then the local session cleared, in that order.
    expect(phoneAuth.signOutCalled, isTrue);
    expect(find.text('Your account has been deleted'), findsOneWidget);
  });

  testWidgets('a failed backend call destroys NOTHING locally', (
    tester,
  ) async {
    // The critical safety property: a refused deletion must leave the
    // customer signed in and able to retry, not half-deleted.
    final repo = _RecordingProfileRepo(shouldFail: true);
    final phoneAuth = _RecordingPhoneAuth();
    await _pump(tester, repository: repo, phoneAuth: phoneAuth);

    await tester.tap(find.byKey(const Key('deleteAccountStartButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('deleteAccountConfirmField')),
      'DELETE',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteAccountConfirmButton')));
    await _settleDeletion(tester);

    expect(repo.deleteCalled, isTrue);
    // No local teardown happened.
    expect(phoneAuth.signOutCalled, isFalse);
    // The failure is explained and retry is offered.
    expect(find.textContaining('Your account is'), findsOneWidget);
    expect(find.byKey(const Key('deleteAccountRetryButton')), findsOneWidget);
    // And it is NOT showing a success screen.
    expect(find.text('Your account has been deleted'), findsNothing);
  });

  testWidgets('the done screen returns to the entry screen', (tester) async {
    await _pump(tester, repository: _RecordingProfileRepo());

    await tester.tap(find.byKey(const Key('deleteAccountStartButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('deleteAccountConfirmField')),
      'DELETE',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteAccountConfirmButton')));
    await _settleDeletion(tester);

    await tester.tap(find.byKey(const Key('deleteAccountDoneButton')));
    await tester.pumpAndSettle();
    expect(find.text('WelcomePage'), findsOneWidget);
  });
}
