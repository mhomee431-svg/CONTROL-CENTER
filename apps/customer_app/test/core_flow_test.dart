import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_customer_app/app.dart';
import 'package:hyperlocal_customer_app/core/storage/secure_storage_service.dart';
import 'package:hyperlocal_customer_app/features/home/data/mock_home_repository.dart';
import 'package:hyperlocal_customer_app/features/home/domain/home_repository.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'core_flow_test.mocks.dart';

@GenerateMocks([SecureStorageService])
void main() {
  testWidgets(
    'App initializes, shows splash, and lands on Home for guest users (guest-first)',
    (WidgetTester tester) async {
      final mockStorage = MockSecureStorageService();
      when(mockStorage.getToken()).thenAnswer((_) async => null);
      when(mockStorage.getSessionId()).thenAnswer((_) async => null);
      when(mockStorage.getRefreshToken()).thenAnswer((_) async => null);
      when(mockStorage.getDeviceId()).thenAnswer((_) async => null);
      when(mockStorage.isGuestMode()).thenAnswer((_) async => false);
      when(mockStorage.read(key: 'user_saved_location')).thenAnswer((_) async => null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(mockStorage),
            // Avoid real HTTP in the widget test — the Home screen loads its
            // feed through this repository.
            homeRepositoryProvider.overrideWithValue(MockHomeRepository()),
          ],
          child: const HyperlocalApp(),
        ),
      );

      // Verify Splash Screen
      expect(find.text('Hyperlocal'), findsOneWidget);

      // Fast forward past the splash timer and auth check.
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Guest-first: no login wall — the customer lands on the Home shell.
      expect(find.text('Discover Local, Shop Local'), findsNothing);
      expect(find.text('Login with Phone'), findsNothing);
      expect(find.text('Continue as Guest'), findsNothing);
    },
  );
}