import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../data/location_accuracy_config.dart';
import '../../domain/location_capture_state.dart';
import '../controllers/location_capture_controller.dart';
import '../../../../core/permissions/widgets/permission_prompt_view.dart';
import '../../../../core/theme/app_colors.dart';

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
    final device = state.deviceReading;
    // Map-only capture (no GPS fix): there is no device reading to report, and
    // the pin is the one the shopkeeper placed — recorded as MANUAL, never
    // dressed up as a GPS fix.
    final capturedAt = device?.timestamp ?? DateTime.now();
    final mapOnly = state.mapOnly || device == null;
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
      accuracyMeters: state.accuracyMeters,
      capturedAt: capturedAt,
      addressText: state.effectiveAddressText,
      city: state.address?.city,
      state: state.address?.state,
      pincode: state.address?.pincode,
      integrityStatus: device == null
          ? 'UNKNOWN'
          : (device.isMock ? 'SUSPICIOUS' : 'NORMAL'),
      locationSource: mapOnly ? 'MANUAL' : 'GPS',
    ));
  }

  /// Location permission denied — or blocked, which is NOT the same thing:
  /// a plain denial can be asked again ("Allow Location"), while a permanent
  /// denial can only be changed in the system settings. Both states offer the
  /// two fallbacks that need no permission at all.
  PermissionPromptView _permissionDeniedView(LocationCaptureState state) {
    final blocked = state.permissionBlocked;
    return PermissionPromptView(
      icon: blocked ? Icons.lock_outline : Icons.location_searching,
      title: blocked
          ? 'Location permission is blocked'
          : 'Location permission needed',
      message: blocked
          ? 'Location access is turned off for this app, so your shop pin '
              'cannot be found automatically.'
          : 'Location permission is required to accurately add your shop.',
      bullets: blocked
          ? const [
              'Open your phone Settings > Apps > Passly Business',
              'Open Permissions > Location and choose "Allow"',
              'Return to the app and tap "Allow Location" again',
            ]
          : const [],
      primary: PermissionPromptAction(
        key: const Key('location_permission_primary'),
        label: blocked ? 'Open System Settings' : 'Allow Location',
        icon: blocked ? Icons.settings_outlined : Icons.my_location,
        onPressed: blocked
            ? () => _openPhoneSettings(forLocationServices: false)
            : () => ref
                .read(locationCaptureControllerProvider.notifier)
                .startCapture(),
      ),
      fallbacks: [
        PermissionPromptAction(
          key: const Key('location_choose_on_map'),
          label: 'Choose Location on Map',
          icon: Icons.map_outlined,
          onPressed: _chooseOnMap,
        ),
        PermissionPromptAction(
          key: const Key('location_enter_manually'),
          label: 'Enter Address Manually',
          icon: Icons.edit_location_alt_outlined,
          onPressed: _enterManually,
        ),
      ],
    );
  }

  /// "Choose Location on Map" — the fallback that needs neither permission nor
  /// GPS: the shopkeeper places the shop pin on the map by hand.
  void _chooseOnMap() {
    ref.read(locationCaptureControllerProvider.notifier).startMapOnlyCapture();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Tap the map to place your shop pin.'),
      ));
  }

  /// "Enter Address Manually" — this screen only sets the PIN; the wizard owns
  /// the address fields, so the shopkeeper is returned there.
  void _enterManually() {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Enter your shop address in the form.'),
      ));
  }

  /// Opens the phone settings page that unblocks the current state: the app's
  /// permission page, or the device location-services page.
  Future<void> _openPhoneSettings({required bool forLocationServices}) async {
    final controller = ref.read(locationCaptureControllerProvider.notifier);
    final opened = forLocationServices
        ? await controller.openDeviceLocationSettings()
        : await controller.openSystemSettings();
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Could not open your phone settings from here.'),
    ));
  }

  /// GPS switched off at device level: the permission is fine, the hardware is
  /// off, and only the system location settings can turn it back on.
  PermissionPromptView _serviceDisabledView() => PermissionPromptView(
        icon: Icons.location_off_outlined,
        title: 'Location services are off',
        message:
            'Location services are turned off. Please enable GPS and try again.',
        bullets: const [
          'Open your phone Settings > Location and turn it on',
          'Then return here and tap "Try Again"',
        ],
        primary: PermissionPromptAction(
          key: const Key('location_turn_on_gps'),
          label: 'Turn On Location Services',
          icon: Icons.location_on_outlined,
          onPressed: () => _openPhoneSettings(forLocationServices: true),
        ),
        fallbacks: [
          PermissionPromptAction(
            key: const Key('location_retry'),
            label: 'Try Again',
            icon: Icons.refresh,
            onPressed: () => ref
                .read(locationCaptureControllerProvider.notifier)
                .startCapture(),
          ),
          PermissionPromptAction(
            key: const Key('location_choose_on_map'),
            label: 'Choose Location on Map',
            icon: Icons.map_outlined,
            onPressed: _chooseOnMap,
          ),
          PermissionPromptAction(
            key: const Key('location_enter_manually'),
            label: 'Enter Address Manually',
            icon: Icons.edit_location_alt_outlined,
            onPressed: _enterManually,
          ),
        ],
      );

  /// Acquisition failed (timeout, no usable fix, signal lost) — retry, or place
  /// the pin by hand.
  PermissionPromptView _errorView(LocationCaptureState state) =>
      PermissionPromptView(
        icon: Icons.error_outline,
        title: 'Unable to get location',
        message: state.errorMessage ??
            'Check your GPS signal and connection, then try again.',
        primary: PermissionPromptAction(
          key: const Key('location_retry'),
          label: 'Try Again',
          icon: Icons.refresh,
          onPressed: () =>
              ref.read(locationCaptureControllerProvider.notifier).acquire(),
        ),
        fallbacks: [
          PermissionPromptAction(
            label: 'Choose Location on Map',
            icon: Icons.map_outlined,
            onPressed: _chooseOnMap,
          ),
          PermissionPromptAction(
            label: 'Enter Address Manually',
            icon: Icons.edit_location_alt_outlined,
            onPressed: _enterManually,
          ),
        ],
      );

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
          _AcquiringView(
            state: state,
            onManual: () => Navigator.of(context).pop(),
            onChooseOnMap: _chooseOnMap,
          ),
        LocationCaptureStatus.locationPermissionDenied =>
          _permissionDeniedView(state),
        LocationCaptureStatus.locationServiceDisabled =>
          _serviceDisabledView(),
        LocationCaptureStatus.error => _errorView(state),
        LocationCaptureStatus.locationReady ||
        LocationCaptureStatus.locationPoorAccuracy ||
        LocationCaptureStatus.reverseGeocoding ||
        LocationCaptureStatus.readyForConfirmation =>
          _MapConfirmView(
            state: state,
            adjusting: _adjusting,
            onToggleAdjust: () => setState(() => _adjusting = !_adjusting),
            onTapMap: _onTapMap,
            // Re-runs the full pre-flight, so a revoked permission or a disabled
            // GPS service is reported honestly instead of silently aborting.
            onRetry: () => ref
                .read(locationCaptureControllerProvider.notifier)
                .startCapture(),
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
  const _AcquiringView({
    required this.state,
    required this.onManual,
    required this.onChooseOnMap,
  });

  final LocationCaptureState state;
  final VoidCallback onManual;

  /// Fallback while searching: place the pin on the map instead of waiting for
  /// a GPS fix.
  final VoidCallback onChooseOnMap;

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
                    ? 'Getting location... Improving accuracy'
                    : 'Getting location...',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'GPS accuracy is an estimate, not a guarantee.',
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
              const SizedBox(height: 24),
              // Don't force waiting on a weak/unavailable GPS fix.
              OutlinedButton.icon(
                key: const Key('location_choose_on_map_acquiring'),
                onPressed: onChooseOnMap,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Choose Location on Map'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onManual,
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: const Text('Enter Location Manually'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Permission denied / GPS off / generic failure — every one of these states is
/// rendered by the shared [PermissionPromptView] so the same situation never
/// looks different on two screens. The manual paths (`Choose Location on Map`,
/// `Enter Address Manually`) are offered from the screen's state machine.
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
  const _AccuracyChip({
    required this.accuracyMeters,
    required this.tier,
    this.label,
  });

  final double? accuracyMeters;
  final AccuracyTier tier;

  /// Overrides the derived text (map-only mode has no radius to report at all).
  final String? label;

  Color get _color => switch (tier) {
        AccuracyTier.excellent => AppColors.qualityBest,
        AccuracyTier.good => AppColors.qualityGood,
        AccuracyTier.acceptable => AppColors.qualityFair,
        AccuracyTier.weak => AppColors.qualityPoor,
        AccuracyTier.poor => AppColors.qualityBad,
        AccuracyTier.unknown => AppColors.qualityUnknown,
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
            label ??
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

  /// Where the GPS fix was taken — null in map-only mode, where no fix exists.
  LatLng? get _deviceLatLng {
    final device = state.deviceReading;
    return device == null ? null : LatLng(device.latitude, device.longitude);
  }

  /// Map centre when there is neither a fix nor a pin yet: the middle of the
  /// country, zoomed out, so any shop can be reached by panning.
  static const LatLng _overviewCenter = LatLng(20.5937, 78.9629);

  Set<Marker> get _markers => {
        // DEVICE LOCATION — where the GPS fix was taken (blue). Absent in
        // map-only mode, because there is no fix to show.
        if (_deviceLatLng != null)
          Marker(
            markerId: const MarkerId('device_location'),
            position: _deviceLatLng!,
            infoWindow: const InfoWindow(title: 'Your device location'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure),
          ),
        // SHOP PIN — the shop entrance the keeper confirms (red, draggable).
        if (state.shopPin != null)
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
    final hasFix = _deviceLatLng != null;
    final center = state.shopPin ?? _deviceLatLng ?? _overviewCenter;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Row(
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    state.mapOnly ? 'Place your shop pin' : 'Location found',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const Spacer(),
                Text(
                  state.mapOnly
                      ? 'No GPS fix — pin placed by hand'
                      : 'Location accuracy — '
                          '${LocationAccuracyConfig.accuracyLabel(state.accuracyMeters)}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: center,
                    zoom: hasFix || state.shopPin != null
                        ? LocationAccuracyConfig.initialMapZoom
                        : LocationAccuracyConfig.overviewMapZoom,
                  ),
                  markers: _markers,
                  // The blue-dot layer needs the location grant; in map-only
                  // mode the permission is exactly what is missing, so it stays
                  // off instead of throwing.
                  myLocationEnabled: state.permission?.granted ?? false,
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
                        tier: state.tier,
                        label: state.mapOnly
                            ? 'Accuracy unknown — no GPS fix'
                            : null,
                      ),
                      const Spacer(),
                      FloatingActionButton.small(
                        heroTag: 'recenter',
                        onPressed: onRetry,
                        child: const Icon(Icons.my_location),
                      ),
                    ],
                  ),
                ),
                if (state.mapOnly && !adjusting)
                  Positioned(
                    bottom: 12,
                    left: 12,
                    right: 12,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          state.shopPin == null
                              ? 'Tap the map to place your shop pin.'
                              : 'Drag the pin or tap the map to correct your '
                                  'shop entrance.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
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

  /// Device GPS fix — `null` in map-only mode.
  final LatLng? deviceLatLng;
  final bool poor;
  final VoidCallback onRetry;
  final VoidCallback onToggleAdjust;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Local for null-promotion (public final fields do not promote).
    final fix = deviceLatLng;
    final pin = state.shopPin;
    return Flexible(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (poor) ...[
              Card(
                color: AppColors.error.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Your location is not accurate enough. '
                    'Move closer to your shop for better accuracy.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.error),
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
            Text(
              fix == null
                  ? 'Shop pin (placed by hand — no GPS fix)'
                  : 'Device location vs shop pin',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (fix != null)
                  '📍 Device GPS: ${fix.latitude.toStringAsFixed(6)}, '
                      '${fix.longitude.toStringAsFixed(6)}',
                if (pin != null)
                  '🏪 Shop pin: ${pin.latitude.toStringAsFixed(6)}, '
                      '${pin.longitude.toStringAsFixed(6)}'
                else
                  '🏪 Shop pin: not placed yet — tap the map',
              ].join('\n'),
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
              if (state.mapOnly) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('location_try_gps_again'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Use my current location instead'),
                ),
              ],
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




