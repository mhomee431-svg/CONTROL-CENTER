import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../data/location_accuracy_config.dart';
import '../../domain/location_capture_state.dart';
import '../controllers/location_capture_controller.dart';

/// "Add Your Shop" location capture — mobile-first, ride-app style.
///
/// Pops a [CapturedShopLocation] on success; pops `null` when the shopkeeper
/// chooses manual entry. DEVICE LOCATION and SHOP PIN are shown separately.
class LocationCaptureScreen extends ConsumerStatefulWidget {
  const LocationCaptureScreen({super.key, this.shopName});

  /// Shop name shown on the final confirmation card (optional).
  final String? shopName;

  @override
  ConsumerState<LocationCaptureScreen> createState() =>
      _LocationCaptureScreenState();
}

class _LocationCaptureScreenState extends ConsumerState<LocationCaptureScreen> {
  bool _adjusting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref
        .read(locationCaptureControllerProvider.notifier)
        .startCapture());
  }

  Future<void> _confirm() async {
    final controller = ref.read(locationCaptureControllerProvider.notifier);
    await controller.confirmLocation();
    if (!mounted) return;
    final state = ref.read(locationCaptureControllerProvider);
    if (state.status != LocationCaptureStatus.readyForConfirmation) return;

    final pin = state.shopPin!;
    final device = state.deviceReading!;
    final addressSummary = (state.effectiveAddressText?.isNotEmpty ?? false)
        ? state.effectiveAddressText!
        : 'Lat ${pin.latitude.toStringAsFixed(6)}, '
            'Lng ${pin.longitude.toStringAsFixed(6)}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm shop location'),
        content: Text(
          '${widget.shopName == null ? '' : 'Shop: ${widget.shopName}\n\n'}'
          'Accuracy: ${LocationAccuracyConfig.accuracyLabel(state.accuracyMeters)}\n\n'
          '$addressSummary\n\n'
          'Save this as your shop entrance location?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    Navigator.of(context).pop(CapturedShopLocation(
      latitude: pin.latitude,
      longitude: pin.longitude,
      accuracyMeters: state.accuracyMeters ?? 0,
      capturedAt: device.timestamp,
      addressText: state.effectiveAddressText,
      city: state.address?.city,
      state: state.address?.state,
      pincode: state.address?.pincode,
      integrityStatus: device.isMock ? 'SUSPICIOUS' : 'NORMAL',
    ));
  }

  /// Warns when the pin drifted far from the device GPS fix.
  Future<bool> _checkDriftBeforePlacing(LatLng pin) async {
    final state = ref.read(locationCaptureControllerProvider);
    final drift = state.pinDriftMeters ?? 0;
    if (drift <= LocationAccuracyConfig.pinDriftWarningMeters) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Different location detected'),
        content: Text(
          'Your selected shop location is ${(drift / 1000).toStringAsFixed(1)} km '
          'away from your current GPS location.\n\n'
          'Are you sure this is your shop?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                ref
                    .read(locationCaptureControllerProvider.notifier)
                    .confirmPinDrift();
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Confirm')),
        ],
      ),
    );
    return ok == true;
  }

  void _onTapMap(LatLng latLng) async {
    final controller = ref.read(locationCaptureControllerProvider.notifier);
    controller.moveShopPin(latLng);
    if (!await _checkDriftBeforePlacing(latLng)) {
      final device = ref.read(locationCaptureControllerProvider).deviceReading;
      if (device != null) {
        controller.moveShopPin(LatLng(device.latitude, device.longitude));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(locationCaptureControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Add Your Shop')),
      body: switch (state.status) {
        LocationCaptureStatus.initial ||
        LocationCaptureStatus.requestingPermission ||
        LocationCaptureStatus.fetchingLocation ||
        LocationCaptureStatus.improvingAccuracy =>
          _AcquiringView(state: state),
        LocationCaptureStatus.locationPermissionDenied => _BlockedView(
            icon: Icons.lock_outline,
            message:
                'Location permission is required to accurately add your shop.',
            onRetry: () => ref
                .read(locationCaptureControllerProvider.notifier)
                .startCapture(),
            retryLabel: 'Allow Location',
            onManual: () => Navigator.of(context).pop(),
          ),
        LocationCaptureStatus.locationServiceDisabled => _BlockedView(
            icon: Icons.location_off_outlined,
            message:
                'Location services are turned off. Please enable GPS and try again.',
            onRetry: () => ref
                .read(locationCaptureControllerProvider.notifier)
                .startCapture(),
            retryLabel: 'Try Again',
            onManual: () => Navigator.of(context).pop(),
          ),
        LocationCaptureStatus.error => _BlockedView(
            icon: Icons.error_outline,
            message: state.errorMessage ?? 'Something went wrong.',
            onRetry: () =>
                ref.read(locationCaptureControllerProvider.notifier).acquire(),
            retryLabel: 'Try Again',
            onManual: () => Navigator.of(context).pop(),
          ),
        LocationCaptureStatus.locationReady ||
        LocationCaptureStatus.locationPoorAccuracy ||
        LocationCaptureStatus.reverseGeocoding ||
        LocationCaptureStatus.readyForConfirmation =>
          _MapConfirmView(
            state: state,
            adjusting: _adjusting,
            onToggleAdjust: () => setState(() => _adjusting = !_adjusting),
            onTapMap: _onTapMap,
            onRetry: () =>
                ref.read(locationCaptureControllerProvider.notifier).acquire(),
            onConfirm: _confirm,
          ),
        LocationCaptureStatus.saving ||
        LocationCaptureStatus.success =>
          const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// "Fetching your location…" / "Improving location accuracy…" view with the
/// best-practice checklist. No map here — the map only appears once ready.
class _AcquiringView extends StatelessWidget {
  const _AcquiringView({required this.state});

  final LocationCaptureState state;

  @override
  Widget build(BuildContext context) {
    final improving =
        state.status == LocationCaptureStatus.improvingAccuracy;
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 24),
              Text(
                improving
                    ? 'Improving location accuracy…'
                    : 'Fetching your location…',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Getting your precise location…',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              _AccuracyChip(
                  accuracyMeters: state.accuracyMeters, tier: state.tier),
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('For best accuracy:',
                    style: theme.textTheme.titleSmall),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ChecklistItem('Turn on GPS'),
                    _ChecklistItem('Enable Precise Location'),
                    _ChecklistItem('Stand near your shop entrance'),
                    _ChecklistItem('Keep the phone outdoors if possible'),
                    _ChecklistItem('Wait for accuracy to improve'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Permission denied / GPS off / generic failure — never crashes, never
/// fabricates coordinates, always offers a manual path.
class _BlockedView extends StatelessWidget {
  const _BlockedView({
    required this.icon,
    required this.message,
    required this.onRetry,
    required this.retryLabel,
    required this.onManual,
  });

  final IconData icon;
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.my_location),
              label: Text(retryLabel),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onManual,
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: const Text('Enter Location Manually'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.check_circle,
              size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Live accuracy indicator — shows the REAL radius, never "100% accurate".
class _AccuracyChip extends StatelessWidget {
  const _AccuracyChip({required this.accuracyMeters, required this.tier});

  final double? accuracyMeters;
  final AccuracyTier tier;

  Color get _color => switch (tier) {
        AccuracyTier.excellent => Colors.green,
        AccuracyTier.good => Colors.lightGreen,
        AccuracyTier.acceptable => Colors.orange,
        AccuracyTier.weak => Colors.deepOrange,
        AccuracyTier.poor => Colors.red,
        AccuracyTier.unknown => Colors.blueGrey,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gps_fixed, size: 14, color: _color),
          const SizedBox(width: 6),
          Text(
            '${LocationAccuracyConfig.tierLabel(tier)} — '
            '${LocationAccuracyConfig.accuracyLabel(accuracyMeters)}',
            style: TextStyle(
                color: _color, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Map + shop entrance pin + address preview + confirmation actions.
class _MapConfirmView extends StatelessWidget {
  const _MapConfirmView({
    required this.state,
    required this.adjusting,
    required this.onToggleAdjust,
    required this.onTapMap,
    required this.onRetry,
    required this.onConfirm,
  });

  final LocationCaptureState state;
  final bool adjusting;
  final VoidCallback onToggleAdjust;
  final ValueChanged<LatLng> onTapMap;
  final VoidCallback onRetry;
  final VoidCallback onConfirm;

  LatLng get _deviceLatLng => LatLng(
      state.deviceReading!.latitude, state.deviceReading!.longitude);

  Set<Marker> get _markers => {
        // DEVICE LOCATION — where the GPS fix was taken (blue).
        Marker(
          markerId: const MarkerId('device_location'),
          position: _deviceLatLng,
          infoWindow: const InfoWindow(title: 'Your device location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure),
        ),
        // SHOP PIN — the shop entrance the keeper confirms (red, draggable).
        Marker(
          markerId: const MarkerId('shop_pin'),
          position: state.shopPin!,
          draggable: true,
          infoWindow: const InfoWindow(title: 'Shop entrance'),
          onDragEnd: onTapMap,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final poor = state.status == LocationCaptureStatus.locationPoorAccuracy;
    final center = state.shopPin ?? _deviceLatLng;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: center, zoom: 17),
                  markers: _markers,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  onTap: adjusting ? onTapMap : null,
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Row(
                    children: [
                      _AccuracyChip(
                          accuracyMeters: state.accuracyMeters,
                          tier: state.tier),
                      const Spacer(),
                      FloatingActionButton.small(
                        heroTag: 'recenter',
                        onPressed: onRetry,
                        child: const Icon(Icons.my_location),
                      ),
                    ],
                  ),
                ),
                if (adjusting)
                  Positioned(
                    bottom: 12,
                    left: 12,
                    right: 12,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          'Tap the map to place the pin at your shop ENTRANCE.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _BottomPanel(
            state: state,
            deviceLatLng: _deviceLatLng,
            poor: poor,
            onRetry: onRetry,
            onToggleAdjust: onToggleAdjust,
            onConfirm: onConfirm,
          ),
        ],
      ),
    );
  }
}

/// Scrollable bottom sheet: poor-accuracy actions, device-vs-shop coordinates,
/// editable detected address and the final confirm action.
class _BottomPanel extends ConsumerWidget {
  const _BottomPanel({
    required this.state,
    required this.deviceLatLng,
    required this.poor,
    required this.onRetry,
    required this.onToggleAdjust,
    required this.onConfirm,
  });

  final LocationCaptureState state;
  final LatLng deviceLatLng;
  final bool poor;
  final VoidCallback onRetry;
  final VoidCallback onToggleAdjust;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Flexible(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (poor) ...[
              Card(
                color: Colors.red.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Your location is not accurate enough. '
                    'Move closer to your shop for better accuracy.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.red.shade700),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onToggleAdjust,
                      icon: const Icon(Icons.edit_location_alt_outlined),
                      label: const Text('Adjust Pin'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Text('Device location vs shop pin',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 4),
            Text(
              '📍 Device GPS: '
              '${deviceLatLng.latitude.toStringAsFixed(6)}, '
              '${deviceLatLng.longitude.toStringAsFixed(6)}\n'
              '🏪 Shop pin: '
              '${state.shopPin!.latitude.toStringAsFixed(6)}, '
              '${state.shopPin!.longitude.toStringAsFixed(6)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text('Detected Address',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 4),
            TextFormField(
              initialValue: state.effectiveAddressText,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Detected address — you may correct the text',
              ),
              onChanged: (value) => ref
                  .read(locationCaptureControllerProvider.notifier)
                  .editAddressText(value),
            ),
            const SizedBox(height: 16),
            if (state.status == LocationCaptureStatus.reverseGeocoding)
              const Center(child: LinearProgressIndicator(minHeight: 2))
            else ...[
              FilledButton.icon(
                onPressed: state.canConfirm ? onConfirm : null,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Confirm Shop Location'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onToggleAdjust,
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: const Text('Adjust Pin'),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'GPS coordinates remain the primary location; '
              'the address is supporting information.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}




