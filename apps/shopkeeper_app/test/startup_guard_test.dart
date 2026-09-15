import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/auth/firebase_auth_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/screens/splash_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/data/insights_repository.dart';

import 'fakes.dart';

/// ROUTE GUARD LOGIC — startup / splash behaviour.
///
/// The startup chain: Flutter init → Firebase init → session check
/// (stored `/auth/me` → device Firebase state → ID token → `/firebase-login`)
/// → route accordingly. Requirements:
///
///  * Home must NEVER render before the account state is known.
///  * No route flickering: a TRANSIENT startup failure (offline / backend
///    5xx) HOLDS the splash with a Retry instead of flicking to Welcome —
///    being offline is NOT the same as being signed out.
///  * A definitive rejection (401) still lands on Welcome.
ProviderContainer startupContainer({
  AuthSession? session,
  Object? restoreError,
}) {
  final repo = FakeAuthRepository()..submitError = restoreError;
  if (session != null) repo.restoreResult = session;
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
      insightsRepositoryProvider.overrideWithValue(FakeInsightsRepo()),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      firebaseAuthServiceProvider.overrideWithValue(FakeFirebaseAuthService()),
      selectedShopProvider.overrideWith(
        () => SelectedShopOverride(
          (session == null || session.shops.isEmpty) ? null : session.shops.first,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> pumpStartupApp(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ShopkeeperApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offline startup HOLDS splash with Retry — no Welcome flicker',
      (tester) async {
    await pumpStartupApp(
      tester,
      startupContainer(restoreError: const SocketException('offline')),
    );

    // Splash is still showing (with the retry affordance), NOT Welcome.
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);
  });

  testWidgets('backend 5xx at startup also HOLDS splash (transient, not sign-out)',
      (tester) async {
    await pumpStartupApp(
      tester,
      startupContainer(
        restoreError: const ApiException(statusCode: 500, message: 'boom'),
      ),
    );

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);
  });

  testWidgets('Retry after the transient failure heals → Dashboard',
      (tester) async {
    final container = startupContainer(
      restoreError: const SocketException('offline'),
    );
    await pumpStartupApp(tester, container);

    // The backend "comes back": the stored session is now restorable.
    container.read(authRepositoryProvider) as FakeAuthRepository
      ..submitError = null
      ..restoreResult = makeSession();

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('definitive 401 rejection → Welcome (signed out), no Retry',
      (tester) async {
    await pumpStartupApp(
      tester,
      startupContainer(
        restoreError: const ApiException(statusCode: 401, message: 'expired'),
      ),
    );

    expect(find.text('Retry'), findsNothing);
    expect(find.byType(DashboardScreen), findsNothing);
  });

  testWidgets('"Sign in instead" escape hatch → Welcome without wiping tokens',
      (tester) async {
    final container = startupContainer(
      session: makeSession(),
      restoreError: const SocketException('offline'),
    );
    await pumpStartupApp(tester, container);

    await tester.tap(find.text('Sign in instead'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsNothing);
    expect(find.byType(DashboardScreen), findsNothing);
    // The stored session stays intact for the next successful startup.
    final repo = container.read(authRepositoryProvider) as FakeAuthRepository;
    expect(repo.restoreResult, isNotNull);
  });
}
