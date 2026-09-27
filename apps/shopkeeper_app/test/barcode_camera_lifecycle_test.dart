/// BARCODE CAMERA LIFECYCLE (spec §112).
///
/// "When leaving scanner: stop camera resources. When reopening: initialize
/// cleanly. Do not leave camera active in background."
///
/// The camera widget is a platform view, so the permission gate is stubbed to
/// DENIED and `MobileScanner` is never built — which is exactly the point:
/// every contract asserted here runs BEFORE the camera exists, so it is
/// provable without a device.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/permissions/data/permission_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/permissions/permission_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/barcode_scanner_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/data/barcode_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/domain/barcode_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/presentation/controllers/barcode_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';

import 'fakes.dart';

/// A repository whose lookup never answers, so `resolve()` leaves the scan
/// controller parked on `resolving` — the exact state a shopkeeper strands by
/// popping the scanner mid-lookup.
class _StallingRepo implements BarcodeRepository {
  final Completer<BarcodeResolution> gate = Completer<BarcodeResolution>();

  @override
  Future<BarcodeResolution> resolveBarcode(
    String barcode,
    int? shopId,
    String token,
  ) =>
      gate.future;

  @override
  Future<ShopProductItem> saveFromBarcode(
    int shopId,
    BarcodeSavePayload payload,
    String token,
  ) async =>
      throw UnimplementedError();
}

/// Pumps a host route that opens [BarcodeScannerScreen], after parking the
/// scan controller in a stale state (or not, when [seed] is null).
Future<ProviderContainer> openScanner(
  WidgetTester tester, {
  void Function(ProviderContainer c)? seed,
}) async {
  final permissions = InMemoryPermissionService()
    ..setStatus(PermissionKind.camera, PermissionOutcome.denied);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        permissionServiceProvider.overrideWithValue(permissions),
        barcodeRepositoryProvider.overrideWithValue(_StallingRepo()),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider
            .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
      ],
      child: const MaterialApp(
        home: _ScannerHost(),
      ),
    ),
  );

  final container =
      ProviderScope.containerOf(tester.element(find.text('open scanner')));
  seed?.call(container);

  await tester.tap(find.text('open scanner'));
  await tester.pumpAndSettle();
  return container;
}

class _ScannerHost extends StatelessWidget {
  const _ScannerHost();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BarcodeScannerScreen(),
              ),
            ),
            child: const Text('open scanner'),
          ),
        ),
      );
}

void main() {
  /// Parks the scan controller on `resolving` — a lookup that never answers.
  void leaveStuckResolving(ProviderContainer c) {
    // Not awaited: the completer never completes, so the controller stays on
    // `resolving` exactly as it would if the shopkeeper walked away.
    c.read(barcodeControllerProvider.notifier).resolve('8901234567890');
  }

  group('§112 — reopening the scanner initializes cleanly', () {
    testWidgets('a session left mid-resolve does not strand the next open',
        (tester) async {
      // Regression: the scan controller is container-scoped, so popping the
      // scanner mid-lookup left the status on `resolving`. The next open then
      // rendered a PERMANENT progress spinner over a working camera — the
      // shopkeeper could scan, but the AppBar claimed it was still busy.
      final container = await openScanner(tester, seed: leaveStuckResolving);
      // The reset is a microtask (Riverpod forbids provider writes during a
      // widget life-cycle), so let it land before asserting.
      await tester.pumpAndSettle();

      expect(
        container.read(barcodeControllerProvider).status,
        BarcodeScanStatus.idle,
        reason: 'a fresh scanning session must start from idle',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'no stranded spinner over the camera');
    });

    testWidgets('the camera-usable AppBar is restored on reopen', (tester) async {
      await openScanner(tester, seed: leaveStuckResolving);
      await tester.pumpAndSettle();

      // The manual-entry action is the camera-usable way out. It lives in the
      // AppBar as an IconButton, and while a stale `resolving` status was still
      // on the controller the AppBar swapped it for a spinner — which is what
      // stranded the shopkeeper. Assert the action is back, not a label.
      expect(find.byTooltip('Enter barcode manually'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('§112 — leaving the scanner releases the camera', () {
    testWidgets('popping the screen tears it down without throwing',
        (tester) async {
      await openScanner(tester);

      // Back out: dispose() runs and disposes the MobileScannerController. A
      // lifecycle mistake here surfaces as an uncaught exception, which is why
      // this asserts on takeException rather than on a widget.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'leaving the scanner must not throw');
      expect(find.text('open scanner'), findsOneWidget,
          reason: 'the host route is back on screen');
    });

    testWidgets('the scan controller survives the pop (reusable state)',
        (tester) async {
      // The controller is intentionally container-scoped, not screen-scoped:
      // it is what this file's first group proves gets RESET on the next open.
      final container = await openScanner(tester);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();

      expect(container.read(barcodeControllerProvider).status,
          BarcodeScanStatus.idle);
    });
  });
}

