import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_providers.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/profile/data/profile_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/profile/presentation/controllers/profile_edit_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/profile/presentation/screens/edit_profile_screen.dart';

import 'fakes.dart';

/// Deterministic ApiClient: serves canned profile payloads, records updates.
class FakeProfileApi extends ApiClient {
  FakeProfileApi() : super(dio: Dio());

  Map<String, dynamic> profilePayload = {
    'id': 7,
    'name': 'Old Name',
    'email': 'old@example.com',
    'phone_number': '+919000000007',
    'avatar_url': null,
  };

  Object? putError;
  int getCalls = 0;
  int putCalls = 0;
  Map<String, dynamic>? lastBody;

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, String? token}) async {
    getCalls++;
    return Map<String, dynamic>.of(profilePayload);
  }

  @override
  Future<dynamic> put(String path, {Object? body, String? token}) async {
    putCalls++;
    if (putError != null) throw putError!;
    lastBody = (body as Map).cast<String, dynamic>();
    profilePayload = Map<String, dynamic>.of(profilePayload)..addAll(lastBody!);
    return Map<String, dynamic>.of(profilePayload);
  }
}

ProviderContainer makeContainer(FakeProfileApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> pumpWithOverrides(WidgetTester tester, FakeProfileApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token'),
        ),
        // The save path also refreshes the session name via /auth/me.
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository()..restoreResult = makeSession(),
        ),
      ],
      child: const MaterialApp(home: EditProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileRepository (GET/PUT /api/v1/profile)', () {
    test('fetch parses the backend profile payload', () async {
      final api = FakeProfileApi();
      final container = makeContainer(api);
      final repo = ProfileRepository(
        api,
        container.read(tokenStoreProvider),
      );
      final profile = await repo.fetchProfile();
      expect(api.getCalls, 1);
      expect(profile.id, 7);
      expect(profile.name, 'Old Name');
      expect(profile.phoneNumber, '+919000000007');
    });

    test('update sends only non-null fields (partial PUT)', () async {
      final api = FakeProfileApi();
      final container = makeContainer(api);
      final repo = ProfileRepository(
        api,
        container.read(tokenStoreProvider),
      );
      final updated = await repo.updateProfile(name: 'New Name');
      expect(api.putCalls, 1);
      expect(api.lastBody, {'name': 'New Name'});
      expect(updated.name, 'New Name');
    });
  });

  group('ProfileEditController', () {
    test('loads the profile into an editable ready state', () async {
      final container = makeContainer(FakeProfileApi());
      container.read(profileEditControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final state = container.read(profileEditControllerProvider);
      expect(state.status, ProfileEditStatus.ready);
      expect(state.name, 'Old Name');
      expect(state.email, 'old@example.com');
    });

    test('save rejects an invalid email without calling the API', () async {
      final api = FakeProfileApi();
      final container = makeContainer(api);
      final notifier = container.read(profileEditControllerProvider.notifier);
      notifier.setName('Ramesh Kumar');
      notifier.setEmail('not-an-email');
      final err = await notifier.save();
      expect(err, 'Enter a valid email address');
      expect(api.putCalls, 0);
    });

    test('save rejects an empty name without calling the API', () async {
      final api = FakeProfileApi();
      final container = makeContainer(api);
      final notifier = container.read(profileEditControllerProvider.notifier);
      notifier.setName('   ');
      final err = await notifier.save();
      expect(err, 'Name is required');
      expect(api.putCalls, 0);
    });

    test('successful save flips saved and stores the new name', () async {
      final api = FakeProfileApi();
      final container = makeContainer(api);
      final notifier = container.read(profileEditControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      notifier.setName('New Name');
      final err = await notifier.save();
      expect(err, isNull);
      expect(api.putCalls, 1);
      final state = container.read(profileEditControllerProvider);
      expect(state.saved, isTrue);
      expect(state.name, 'New Name');
    });

    test('API failure surfaces the message, saved stays false', () async {
      final api = FakeProfileApi()
        ..putError = const ApiException(statusCode: 422, message: 'Bad email');
      final container = makeContainer(api);
      final notifier = container.read(profileEditControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      notifier.setName('New Name');
      final err = await notifier.save();
      expect(err, 'Bad email');
      final state = container.read(profileEditControllerProvider);
      expect(state.saved, isFalse);
      expect(state.status, ProfileEditStatus.ready);
    });
  });

  group('EditProfileScreen', () {
    testWidgets('prefills, saves and pops on success', (tester) async {
      final api = FakeProfileApi();
      await pumpWithOverrides(tester, api);

      expect(find.text('Old Name'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Full name'), 'Brand New Name');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(api.putCalls, 1);
      expect(api.lastBody!['name'], 'Brand New Name');
      // The screen pops itself after a successful save.
      expect(find.byType(EditProfileScreen), findsNothing);
    });

    testWidgets('empty name shows a validation error and stays',
        (tester) async {
      final api = FakeProfileApi();
      await pumpWithOverrides(tester, api);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Full name'), '');
      await tester.tap(find.text('Save changes'));
      await tester.pump();

      expect(find.text('Name is required'), findsOneWidget);
      expect(find.byType(EditProfileScreen), findsOneWidget);
    });
  });
}
