import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/shop_models.dart';
import '../controllers/shop_profile_controller.dart';
import '../widgets/shop_profile_shared.dart';

/// Shop Location — the pin customers navigate to. Shows the stored
/// coordinates and offers the controlled "use my current location" edit
/// (`PATCH /shopkeeper/shops/{id}/location`, the endpoint the backend audits).
class ShopLocationScreen extends ConsumerStatefulWidget {
  const ShopLocationScreen({super.key});

  @override
  ConsumerState<ShopLocationScreen> createState() => _ShopLocationScreenState();
}

class _ShopLocationScreenState extends ConsumerState<ShopLocationScreen> {
  String? _lastSnackbarMessage;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(shopLocationProvider.notifier).load());
  }

  /// Opens the phone settings page that unblocks the last failure: this app's
  /// permission page, or the device location-services page.
  Future<void> _openSettings({required bool forLocationServices}) async {
    final service = ref.read(shopLocationServiceProvider);
    final opened = forLocationServices
        ? await service.openLocationSettings()
        : await service.openAppSettings();
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Could not open your phone settings from here.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shopLocationProvider);
    final canEdit = shopCanEdit(ref);

    // Success / failure copy is surfaced exactly once per action.
    ref.listen<ShopLocationState>(shopLocationProvider, (prev, next) {
      final message = next.savedMessage ?? next.message;
      if (message != null && message != _lastSnackbarMessage) {
        _lastSnackbarMessage = message;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        if (next.savedMessage != null) {
          ref.read(shopLocationProvider.notifier).clearSavedMessage();
        }
      }
    });

    final detail = state.detail;

    return Scaffold(
      appBar: AppBar(title: const Text('Shop location')),
      body: SafeArea(
        child: switch (state.status) {
          ShopLocationStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          ShopLocationStatus.error => _LocationErrorView(
            message: state.message,
            onRetry: () => ref.read(shopLocationProvider.notifier).load(),
          ),
          ShopLocationStatus.ready ||
          ShopLocationStatus.saving => _LocationBody(
            detail: detail,
            canEdit: canEdit,
            saving: state.isSaving,
            needsSettings: state.needsSettings,
            needsLocationServices: state.needsLocationServices,
            onOpenSettings: _openSettings,
          ),
        },
      ),
    );
  }
}

class _LocationErrorView extends StatelessWidget {
  const _LocationErrorView({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message ?? 'Could not load the shop location.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.outline),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('shop-location-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// The ready view: the stored pin (or the no-pin empty state) and the
/// controlled GPS update action.
class _LocationBody extends ConsumerWidget {
  const _LocationBody({
    required this.detail,
    required this.canEdit,
    required this.saving,
    required this.needsSettings,
    required this.needsLocationServices,
    required this.onOpenSettings,
  });

  final ShopDetail? detail;
  final bool canEdit;
  final bool saving;

  /// The last update failed because the app's location permission is blocked.
  final bool needsSettings;

  /// The last update failed because the device's location services are off.
  final bool needsLocationServices;

  /// Opens the settings page that fixes whichever of the two applies.
  final Future<void> Function({required bool forLocationServices})
      onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          key: const Key('shop-location-card'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: detail?.hasLocation ?? false
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Stored shop pin',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ShopInfoRow(
                        icon: Icons.explore_outlined,
                        label: 'Coordinates',
                        value: detail?.coordinatesLabel ?? '',
                      ),
                      ShopInfoRow(
                        icon: Icons.map_outlined,
                        label: 'Latitude',
                        value: detail?.latitude?.toStringAsFixed(6) ?? '',
                      ),
                      ShopInfoRow(
                        icon: Icons.map_outlined,
                        label: 'Longitude',
                        value: detail?.longitude?.toStringAsFixed(6) ?? '',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Customers see your shop on the map at this pin. Keep '
                        'it on your shop entrance, not the street corner.',
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.location_off_outlined,
                            size: 20,
                            color: scheme.outline,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'No pin stored yet',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Without a pin customers cannot find your shop on the '
                        'map. Stand at or near the shop and save your current '
                        'location.',
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
        // A blocked permission / switched-off GPS cannot be fixed by tapping the
        // update button again: send the shopkeeper to the exact settings page.
        if (needsSettings || needsLocationServices) ...[
          Card(
            key: const Key('shop-location-permission-notice'),
            margin: EdgeInsets.zero,
            color: scheme.errorContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    needsSettings
                        ? 'Location permission is blocked for this app'
                        : 'Location services are turned off',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    needsSettings
                        ? 'Allow the app to use your location in the phone '
                            'settings, then try again.'
                        : 'Turn GPS on in the phone settings, then try again.',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('shop-location-open-settings'),
                    onPressed: () => onOpenSettings(
                      forLocationServices: needsLocationServices,
                    ),
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(
                      needsSettings
                          ? 'Open System Settings'
                          : 'Turn On Location Services',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Update the pin',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'The app reads your device GPS a few times, keeps the most '
                  'accurate fix and asks the server to replace the stored '
                  'pin. Every change is audited.',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('shop-location-update'),
                  onPressed: canEdit && !saving
                      ? () => ref
                            .read(shopLocationProvider.notifier)
                            .useCurrentLocation()
                      : null,
                  icon: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_outlined),
                  label: Text(
                    detail?.hasLocation ?? false
                        ? 'Use my current location'
                        : 'Save my current location',
                  ),
                ),
                if (!canEdit) ...[
                  const SizedBox(height: 8),
                  const ShopPermissionNotice(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
