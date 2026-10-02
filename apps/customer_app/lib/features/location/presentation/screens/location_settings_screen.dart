import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../profile/presentation/controllers/addresses_controller.dart';
import '../../domain/models/location_permission_status.dart';
import '../../domain/models/saved_address.dart';
import '../../domain/models/user_location.dart';
import '../controllers/location_controller.dart';

/// Dedicated location settings screen.
///
/// ── Permission ownership ──────────────────────────────────────────────────
/// This screen reads the location grant from [locationRepositoryProvider] (via
/// [LocationController]), NOT from the app-wide `PermissionService`. That
/// separation is deliberate and documented in `permission_service.dart`:
/// `geolocator` owns the location grant, and two owners for one permission is
/// how an app ends up asking twice. Everything location-related here therefore
/// goes through the one repository that already owns it.
///
/// ── What this screen deliberately does NOT do ─────────────────────────────
/// There is no "disable location" master switch. The existing
/// `AppSettings.locationEnabled` flag is a *discovery* preference ("should I
/// auto-detect for you"), and presenting it as a permission control would
/// imply the app can revoke a grant it does not own. Turning location access
/// off is done in the OS settings, which this screen links to when needed.
class LocationSettingsScreen extends ConsumerStatefulWidget {
  const LocationSettingsScreen({super.key});

  @override
  ConsumerState<LocationSettingsScreen> createState() =>
      _LocationSettingsScreenState();
}

class _LocationSettingsScreenState
    extends ConsumerState<LocationSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Hydrate the saved location + permission status from storage on open so
    // the screen never shows a blank "unknown" that it could have filled in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(locationControllerProvider.notifier).loadSavedLocation(),
      );
      // `read` on an AsyncNotifierProvider BUILDS it and returns the value
      // synchronously — it is not a Future, so it must not be handed to
      // `unawaited` (which expects a Future<void>?). Reading is exactly what
      // triggers the load; the screen just watches the result.
      ref.read(addressesControllerProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(locationControllerProvider);
    final location = locationState.location;
    final addressesAsync = ref.watch(addressesControllerProvider);
    final defaultAddress = _defaultAddress(addressesAsync.value);

    return Scaffold(
      appBar: AppBar(title: const Text('Location')),
      body: ListView(
        children: [
          // -- Current location --
          const _SectionLabel('Current location'),
          _CurrentLocationCard(location: location, state: locationState),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('locationUseCurrentButton'),
                    onPressed:
                        locationState.isRefreshing ||
                            locationState.status == LocationStatus.loading
                        ? null
                        : () => _useCurrentLocation(context),
                    icon: locationState.isRefreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: const Text('Use current location'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('locationPickOnMapButton'),
                    onPressed: () => context.push('/map-picker'),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Pick on map'),
                  ),
                ),
              ],
            ),
          ),

          // -- Default address --
          const _SectionLabel('Default address'),
          ListTile(
            key: const Key('locationDefaultAddressTile'),
            leading: const Icon(Icons.home_outlined),
            title: const Text('Default address'),
            subtitle: Text(
              defaultAddress == null
                  ? addressesAsync.hasError
                        ? 'Could not load your addresses'
                        : 'No default address set'
                  : '${defaultAddress.label} — '
                        '${_shortAddress(defaultAddress.location)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/addresses'),
          ),
          ListTile(
            key: const Key('locationManageAddressesTile'),
            leading: const Icon(Icons.edit_location_alt_outlined),
            title: const Text('Manage addresses'),
            subtitle: Text(switch (addressesAsync.value?.length) {
              null => 'Add, edit or remove saved places',
              final count =>
                '$count saved ${count == 1 ? 'address' : 'addresses'}',
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/addresses'),
          ),
          const Divider(indent: AppSpacing.md),

          // -- Permission status --
          const _SectionLabel('Location permission'),
          _PermissionTile(
            status: locationState.permissionStatus,
            onAllow: () => _requestPermission(context),
            onOpenSettings: () => _openSystemSettings(context),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  /// The saved address flagged as the default, if any.
  SavedAddress? _defaultAddress(List<SavedAddress>? addresses) {
    if (addresses == null || addresses.isEmpty) return null;
    for (final address in addresses) {
      if (address.isSelected) return address;
    }
    return null;
  }

  /// One-line address for a settings subtitle. Falls back to raw coordinates
  /// when reverse geocoding never produced text, so the row is never blank.
  String _shortAddress(UserLocation location) {
    final text = location.displayAddress;
    if (text.isNotEmpty) return text;
    return '${location.latitude.toStringAsFixed(4)}, '
        '${location.longitude.toStringAsFixed(4)}';
  }

  /// Detects GPS, asks for permission if needed, and adopts the fix.
  ///
  /// Takes a [BuildContext] rather than reading `context` so the messenger is
  /// captured *before* the await, and so the linter's async-gap analysis has a
  /// context it can actually verify is still mounted (`context.mounted`, not the
  /// unrelated `mounted` on the State).
  Future<void> _useCurrentLocation(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(locationControllerProvider.notifier)
        .fetchCurrentLocation(force: true);
    if (!context.mounted) return;

    final state = ref.read(locationControllerProvider);
    if (state.status == LocationStatus.success) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Using your current location.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    // A permanent denial cannot be fixed by asking again, so send the
    // customer straight to the OS rather than showing a dead-end message.
    if (state.status == LocationStatus.permissionPermanentlyDenied) {
      final opened = await ref
          .read(locationControllerProvider.notifier)
          .openSystemLocationSettings();
      if (!opened && context.mounted) {
        _showMessage(context, 'Could not open your device settings.');
      }
      return;
    }
    _showMessage(
      context,
      state.errorMessage ?? 'Could not get your current location.',
    );
  }

  Future<void> _requestPermission(BuildContext context) async {
    final status = await ref
        .read(locationControllerProvider.notifier)
        .requestLocationPermission();
    if (!context.mounted) return;
    if (status == LocationPermissionStatus.granted) {
      // Permission is live — immediately prove it by fetching a fix rather
      // than leaving a granted chip with no location behind it.
      await _useCurrentLocation(context);
    } else {
      _showMessage(context, 'Location permission was not granted.');
    }
  }

  Future<void> _openSystemSettings(BuildContext context) async {
    final opened = await ref
        .read(locationControllerProvider.notifier)
        .openSystemLocationSettings();
    if (!opened && context.mounted) {
      _showMessage(context, 'Could not open your device settings.');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

/// The "where am I right now" summary card.
class _CurrentLocationCard extends StatelessWidget {
  const _CurrentLocationCard({required this.location, required this.state});

  final UserLocation? location;
  final LocationState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFix = location != null;

    // Accuracy is shown verbatim from the model, which never claims precision
    // the device did not report.
    final accuracy = hasFix ? location!.accuracySummary : null;
    final source = hasFix
        ? (location!.isManual ? 'Chosen manually' : 'From your device')
        : _emptyReason(state);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      color: AppColors.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(
              hasFix ? Icons.place : Icons.location_off_outlined,
              color: hasFix ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasFix
                        ? (location!.displayAddress.isEmpty
                              ? location!.displayLabel
                              : location!.displayAddress)
                        : 'No location set yet',
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    hasFix
                        ? '$source • $accuracy'
                        : 'Pick one below to see shops near you',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _emptyReason(LocationState state) => switch (state.status) {
    LocationStatus.permissionDenied ||
    LocationStatus.permissionPermanentlyDenied => 'Location permission needed',
    LocationStatus.serviceDisabled => 'Turn on GPS to find nearby shops',
    _ => 'Pick one below to see shops near you',
  };
}

/// Reports the location grant and offers the ONE action that can actually

/// change it.
///
/// A permanently denied grant is a dead end for in-app prompts: the OS will
/// not show a dialog again, so the only way forward is the system settings
/// page. This tile sends the customer straight there instead of offering a
/// "Allow" button that would do nothing.
class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.status,
    required this.onAllow,
    required this.onOpenSettings,
  });

  final LocationPermissionStatus status;
  final VoidCallback onAllow;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final (label, color, action, actionKey) = switch (status) {
      LocationPermissionStatus.granted => (
        'Allowed',
        AppColors.secondary,
        null,
        null,
      ),
      LocationPermissionStatus.denied => (
        'Not allowed',
        AppColors.textMuted,
        onAllow,
        'permissionAllowButton',
      ),
      LocationPermissionStatus.permanentlyDenied => (
        'Blocked',
        AppColors.error,
        onOpenSettings,
        'permissionOpenSettingsButton',
      ),
      LocationPermissionStatus.restricted => (
        'Restricted',
        AppColors.error,
        null,
        null,
      ),
      LocationPermissionStatus.unknown => (
        'Checking…',
        AppColors.textMuted,
        onAllow,
        'permissionAllowButton',
      ),
    };

    final explanation = switch (status) {
      LocationPermissionStatus.granted =>
        'Hyperlocal can use your location to show nearby shops',
      LocationPermissionStatus.denied =>
        'Allow location access to see shops around you',
      LocationPermissionStatus.permanentlyDenied =>
        'Location is blocked. Turn it back on in your device settings',
      LocationPermissionStatus.restricted =>
        'Location access is restricted on this device',
      LocationPermissionStatus.unknown =>
        'We could not read the permission status',
    };

    return ListTile(
      key: const Key('locationPermissionTile'),
      leading: Icon(Icons.shield_outlined, color: color),
      title: const Text('Location permission'),
      subtitle: Text(explanation),
      trailing: action == null
          ? _StatusChip(label: label, color: color)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusChip(label: label, color: color),
                const SizedBox(width: AppSpacing.xs),
                TextButton(
                  key: Key(actionKey!),
                  onPressed: action,
                  child: Text(
                    status == LocationPermissionStatus.permanentlyDenied
                        ? 'Settings'
                        : 'Allow',
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
