import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/permissions/data/permission_service.dart';
import 'package:hyperlocal_app/core/permissions/permission_models.dart';
import 'package:hyperlocal_app/features/search/domain/barcode_validation.dart';
import 'package:hyperlocal_app/features/search/presentation/controllers/barcode_scanner_view_model.dart';

class _ThrowingPermissionService implements PermissionService {
  var shouldThrow = true;
  final inner = InMemoryPermissionService();

  @override
  Future<PermissionSnapshot> status(PermissionKind kind) async {
    if (shouldThrow) throw Exception('Platform status channel failure');
    return inner.status(kind);
  }

  @override
  Future<PermissionSnapshot> request(PermissionKind kind) async {
    if (shouldThrow) throw Exception('Platform request channel failure');
    return inner.request(kind);
  }

  @override
  Future<bool> openSystemSettings() async => inner.openSystemSettings();
}

void main() {
  group('BarcodeScannerViewModel permission states', () {
    test('initial state defaults to asking with busy true', () {
      final container = ProviderContainer(
        overrides: [
          permissionServiceProvider.overrideWithValue(
            InMemoryPermissionService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(barcodeScannerViewModelProvider);
      expect(state.permissionStatus, BarcodeCameraPermissionStatus.asking);
      expect(state.isBusy, isTrue);
      expect(state.scannedBarcode, isNull);
      expect(state.invalidBarcode, isNull);
      expect(state.errorMessage, isNull);
    });

    test(
      'state transitions to ready when permission is already granted',
      () async {
        final permissions = InMemoryPermissionService(
          statuses: {PermissionKind.camera: PermissionOutcome.granted},
        );
        final container = ProviderContainer(
          overrides: [permissionServiceProvider.overrideWithValue(permissions)],
        );
        addTearDown(container.dispose);

        final notifier = container.read(
          barcodeScannerViewModelProvider.notifier,
        );
        await notifier.checkPermission();

        final state = container.read(barcodeScannerViewModelProvider);
        expect(state.permissionStatus, BarcodeCameraPermissionStatus.ready);
        expect(state.isReady, isTrue);
        expect(state.isBusy, isFalse);
        expect(permissions.requestsFor(PermissionKind.camera), 0);
      },
    );

    test('state transitions to ready on unknown platform fallback', () async {
      final permissions = InMemoryPermissionService(
        statuses: {PermissionKind.camera: PermissionOutcome.unknown},
      );
      final container = ProviderContainer(
        overrides: [permissionServiceProvider.overrideWithValue(permissions)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(barcodeScannerViewModelProvider.notifier);
      await notifier.checkPermission();

      final state = container.read(barcodeScannerViewModelProvider);
      expect(state.permissionStatus, BarcodeCameraPermissionStatus.ready);
      expect(state.isBusy, isFalse);
    });

    test('state transitions to denied when prompt is refused', () async {
      final permissions = InMemoryPermissionService(
        requestOutcomes: {PermissionKind.camera: PermissionOutcome.denied},
      );
      final container = ProviderContainer(
        overrides: [permissionServiceProvider.overrideWithValue(permissions)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(barcodeScannerViewModelProvider.notifier);
      await notifier.requestPermission();

      final state = container.read(barcodeScannerViewModelProvider);
      expect(state.permissionStatus, BarcodeCameraPermissionStatus.denied);
      expect(state.isDenied, isTrue);
      expect(state.isBusy, isFalse);
    });

    test('state transitions to blocked when permanently denied', () async {
      final permissions = InMemoryPermissionService(
        statuses: {PermissionKind.camera: PermissionOutcome.permanentlyDenied},
      );
      final container = ProviderContainer(
        overrides: [permissionServiceProvider.overrideWithValue(permissions)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(barcodeScannerViewModelProvider.notifier);
      await notifier.checkPermission();

      final state = container.read(barcodeScannerViewModelProvider);
      expect(state.permissionStatus, BarcodeCameraPermissionStatus.blocked);
      expect(state.isBlocked, isTrue);
      expect(state.isBusy, isFalse);
    });
    test('openSystemSettings forwards to service', () async {
      final permissions = InMemoryPermissionService();
      final container = ProviderContainer(
        overrides: [permissionServiceProvider.overrideWithValue(permissions)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(barcodeScannerViewModelProvider.notifier);
      final result = await notifier.openSystemSettings();

      expect(result, isTrue);
      expect(permissions.openSettingsCalls, 1);
    });

    test(
      'recheckPermission transitions from blocked to ready on grant',
      () async {
        final permissions = InMemoryPermissionService(
          statuses: {
            PermissionKind.camera: PermissionOutcome.permanentlyDenied,
          },
        );
        final container = ProviderContainer(
          overrides: [permissionServiceProvider.overrideWithValue(permissions)],
        );
        addTearDown(container.dispose);

        final notifier = container.read(
          barcodeScannerViewModelProvider.notifier,
        );
        await notifier.checkPermission();
        expect(
          container.read(barcodeScannerViewModelProvider).permissionStatus,
          BarcodeCameraPermissionStatus.blocked,
        );

        // Customer toggles setting in OS Settings and returns
        permissions.setStatus(PermissionKind.camera, PermissionOutcome.granted);
        await notifier.recheckPermission();

        final state = container.read(barcodeScannerViewModelProvider);
        expect(state.permissionStatus, BarcodeCameraPermissionStatus.ready);
        expect(state.isBusy, isFalse);
      },
    );

    test('transitions to error when status check throws', () async {
      final service = _ThrowingPermissionService();
      final container = ProviderContainer(
        overrides: [permissionServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(barcodeScannerViewModelProvider.notifier);
      await notifier.checkPermission();

      final state = container.read(barcodeScannerViewModelProvider);
      expect(state.permissionStatus, BarcodeCameraPermissionStatus.error);
      expect(state.isError, isTrue);
      expect(state.isBusy, isFalse);
      // Was `contains('Platform status channel failure')`, which asserted the
      // leak this mapper exists to stop. The view model no longer renders
      // `e.toString()`, so the internal platform text must NOT appear.
      expect(state.errorMessage, isNotNull);
      expect(state.errorMessage, isNotEmpty);
      expect(
        state.errorMessage,
        isNot(contains('Platform status channel failure')),
      );
    });

    test('transitions to error when request throws', () async {
      final service = _ThrowingPermissionService();
      final container = ProviderContainer(
        overrides: [permissionServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(barcodeScannerViewModelProvider.notifier);
      await notifier.requestPermission();

      final state = container.read(barcodeScannerViewModelProvider);
      expect(state.permissionStatus, BarcodeCameraPermissionStatus.error);
      expect(state.isError, isTrue);
      expect(state.isBusy, isFalse);
      // See the sibling test: the raw platform text must not surface.
      expect(state.errorMessage, isNotEmpty);
      expect(
        state.errorMessage,
        isNot(contains('Platform request channel failure')),
      );
    });

    test('recovers from error state on retry', () async {
      final service = _ThrowingPermissionService();
      final container = ProviderContainer(
        overrides: [permissionServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(barcodeScannerViewModelProvider.notifier);
      await notifier.checkPermission();
      expect(
        container.read(barcodeScannerViewModelProvider).permissionStatus,
        BarcodeCameraPermissionStatus.error,
      );

      // Now service recovers and grants
      service.shouldThrow = false;
      service.inner.setStatus(PermissionKind.camera, PermissionOutcome.granted);
      await notifier.checkPermission();

      final state = container.read(barcodeScannerViewModelProvider);
      expect(state.permissionStatus, BarcodeCameraPermissionStatus.ready);
      expect(state.isBusy, isFalse);
      expect(state.errorMessage, isNull);
    });
  });
  group('BarcodeScannerViewModel flow and detection', () {
    test('onBarcodeDetected validates and sets valid barcode', () {
      final container = ProviderContainer(
        overrides: [
          permissionServiceProvider.overrideWithValue(
            InMemoryPermissionService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(barcodeScannerViewModelProvider.notifier);
      final handled = notifier.onBarcodeDetected('8901234567890');

      expect(handled, isTrue);
      final state = container.read(barcodeScannerViewModelProvider);
      expect(state.scannedBarcode, '8901234567890');
      expect(state.hasScannedBarcode, isTrue);
      expect(state.invalidBarcode, isNull);
    });

    test('onBarcodeDetected records invalid barcode reason', () {
      final container = ProviderContainer(
        overrides: [
          permissionServiceProvider.overrideWithValue(
            InMemoryPermissionService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(barcodeScannerViewModelProvider.notifier);
      // '123' is too short for retail barcode
      final handled = notifier.onBarcodeDetected('123');

      expect(handled, isTrue);
      final state = container.read(barcodeScannerViewModelProvider);
      expect(state.scannedBarcode, isNull);
      expect(state.hasInvalidBarcode, isTrue);
      expect(state.invalidBarcode?.code, '123');
      expect(state.invalidBarcode?.reason, BarcodeInvalidReason.invalidLength);
    });

    test(
      'onBarcodeDetected ignores duplicate detection while barcode is locked',
      () {
        final container = ProviderContainer(
          overrides: [
            permissionServiceProvider.overrideWithValue(
              InMemoryPermissionService(),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(
          barcodeScannerViewModelProvider.notifier,
        );
        expect(notifier.onBarcodeDetected('8901234567890'), isTrue);
        expect(notifier.onBarcodeDetected('8901234567891'), isFalse);

        expect(
          container.read(barcodeScannerViewModelProvider).scannedBarcode,
          '8901234567890',
        );
      },
    );

    test('onBarcodeDetected ignores empty raw string', () {
      final container = ProviderContainer(
        overrides: [
          permissionServiceProvider.overrideWithValue(
            InMemoryPermissionService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(barcodeScannerViewModelProvider.notifier);
      expect(notifier.onBarcodeDetected('   '), isFalse);
      expect(
        container.read(barcodeScannerViewModelProvider).hasScannedBarcode,
        isFalse,
      );
    });

    test('scanAnother clears scanned and invalid barcode states', () {
      final container = ProviderContainer(
        overrides: [
          permissionServiceProvider.overrideWithValue(
            InMemoryPermissionService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(barcodeScannerViewModelProvider.notifier);
      notifier.onBarcodeDetected('8901234567890');
      expect(
        container.read(barcodeScannerViewModelProvider).hasScannedBarcode,
        isTrue,
      );

      notifier.scanAnother();
      final state = container.read(barcodeScannerViewModelProvider);
      expect(state.scannedBarcode, isNull);
      expect(state.invalidBarcode, isNull);
      expect(state.hasScannedBarcode, isFalse);
    });

    test('setCameraError updates and reset restores default state', () {
      final container = ProviderContainer(
        overrides: [
          permissionServiceProvider.overrideWithValue(
            InMemoryPermissionService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(barcodeScannerViewModelProvider.notifier);
      notifier.setCameraError('Camera failed to start');
      expect(
        container.read(barcodeScannerViewModelProvider).errorMessage,
        'Camera failed to start',
      );

      notifier.reset();
      final resetState = container.read(barcodeScannerViewModelProvider);
      expect(resetState.errorMessage, isNull);
      expect(resetState.permissionStatus, BarcodeCameraPermissionStatus.asking);
    });
  });
}
