import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/map_route.dart';
import '../controllers/map_picker_controller.dart';

/// Zomato-style "pin drop" map screen.
///
/// A full-screen [GoogleMap] with a fixed custom marker pin at the exact
/// center of the viewport. Dragging the map moves the pin; on camera-idle
/// the center coordinate is reverse-geocoded (Google Geocoding API) into a
/// full address incl. pincode, shown in the bottom sheet. From there the
/// customer can draw a driving-route polyline (Directions API) or hand the
/// destination over to the native Google Maps app (`google.navigation:`).
class MapPickerScreen extends ConsumerStatefulWidget {
  const MapPickerScreen({super.key});

  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  /// Fallback camera: Patna city center (primary launch market). Only used
  /// until the cached/silent GPS location resolves.
  static const CameraPosition _defaultCamera = CameraPosition(
    target: LatLng(25.5941, 85.1376),
    zoom: 15,
  );

  static const double _userZoom = 16.0;
  static const Color _routeColor = Color(0xFF1A73E8);

  GoogleMapController? _mapController;

  /// Latest camera pose reported by `onCameraMove`; consumed by
  /// `onCameraIdle` to know which point the center pin sits on.
  CameraPosition? _lastCameraPosition;
  bool _centeredOnUser = false;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _centerOnUserLocation();
  }

  void _onCameraMove(CameraPosition position) {
    _lastCameraPosition = position;
  }

  void _onCameraIdle() {
    final position = _lastCameraPosition;
    if (position == null) return;
    ref
        .read(mapPickerControllerProvider.notifier)
        .onPinMoved(
          MapLatLng(position.target.latitude, position.target.longitude),
        );
  }

  /// Frames the camera on the resolved user location exactly once.
  Future<void> _centerOnUserLocation() async {
    if (_centeredOnUser) return;
    final user = ref.read(mapPickerControllerProvider).userLocation;
    if (user == null || !user.hasValidCoordinates) return;
    _centeredOnUser = true;
    try {
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(user.latitude, user.longitude),
          _userZoom,
        ),
      );
    } catch (_) {
      // Map may already be gone (fast navigation); the default camera
      // position is a usable fallback.
    }
  }

  Set<Polyline> _buildRoutePolylines(MapRoute? route) {
    if (route == null || route.points.isEmpty) return const {};
    return {
      Polyline(
        polylineId: const PolylineId('pinned_route'),
        points: [for (final p in route.points) LatLng(p.latitude, p.longitude)],
        color: _routeColor,
        width: 6,
        jointType: JointType.round,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mapPickerControllerProvider);

    ref.listen<MapPickerState>(mapPickerControllerProvider, (previous, next) {
      // Auto-refresh: frame the camera as soon as the (silent) GPS ping
      // or cached-location restore resolves a usable position.
      if (!_centeredOnUser && next.userLocation != null) {
        _centerOnUserLocation();
      }
      final error = next.errorMessage;
      if (error != null && error != previous?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error)));
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: _defaultCamera,
              mapType: MapType.normal,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              compassEnabled: true,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: true,
              onMapCreated: _onMapCreated,
              onCameraMove: _onCameraMove,
              onCameraIdle: _onCameraIdle,
              polylines: _buildRoutePolylines(state.route),
            ),
          ),
          // Fixed custom marker pin at the exact center of the screen.
          const IgnorePointer(child: _CenterPin()),
          if (state.isGeocoding) const _ResolvingAddressChip(),
          _buildRoutePill(context, state),
          _buildTopBar(context),
          _buildAddressSheet(context, state),
        ],
      ),
    );
  }

  /// Small dismissible pill summarizing the drawn route.
  Widget _buildRoutePill(BuildContext context, MapPickerState state) {
    final route = state.route;
    if (route == null || route.points.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 16,
      right: 16,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.route, size: 18, color: _routeColor),
                    const SizedBox(width: 8),
                    Text(
                      '${route.distanceLabel} • ${route.durationLabel}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    IconButton(
                      tooltip: 'Clear route',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => ref
                          .read(mapPickerControllerProvider.notifier)
                          .clearRoute(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Material(
                color: surfaceColor,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              const Spacer(),
              Material(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(24),
                elevation: 2,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Choose your location',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom sheet showing the reverse-geocoded address + pincode of the
  /// pinned point, plus the route / navigation / confirm actions.
  Widget _buildAddressSheet(BuildContext context, MapPickerState state) {
    final pincode = state.pincodeLabel;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 12,
                offset: Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.addressLabel,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        _buildPincodeRow(pincode, state.isGeocoding),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.hasPinnedPoint && !state.isRouteLoading
                          ? () => ref
                                .read(mapPickerControllerProvider.notifier)
                                .loadDrivingRoute()
                          : null,
                      icon: state.isRouteLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.route),
                      label: const Text('Get Directions'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: state.hasPinnedPoint
                          ? () => ref
                                .read(mapPickerControllerProvider.notifier)
                                .launchNavigation()
                          : null,
                      icon: const Icon(Icons.navigation),
                      label: const Text('Start Direction'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: state.hasPinnedPoint
                      ? () async {
                          await ref
                              .read(mapPickerControllerProvider.notifier)
                              .confirmLocation();
                          if (context.mounted) context.pop();
                        }
                      : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Confirm Location'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pincode chip + "Getting address..." spinner row.
  Widget _buildPincodeRow(String? pincode, bool isGeocoding) {
    return Row(
      children: [
        if (pincode != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Pincode $pincode',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (isGeocoding)
          const Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
              SizedBox(width: 6),
              Text(
                'Getting address...',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
      ],
    );
  }
}

/// The fixed custom pin rendered over the exact center of the map.
///
/// The tip of the pin sits on the true map-center coordinate: the icon is
/// shifted down so its bottom point lands on the viewport center.
class _CenterPin extends StatelessWidget {
  const _CenterPin();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Shifts the icon down by 22px (44/2 within a centered column) so
          // the tip of the pin lands exactly on the map-center coordinate.
          Padding(
            padding: EdgeInsets.only(top: 44),
            child: Icon(
              Icons.location_on,
              size: 48,
              color: Color.fromARGB(255, 77, 2, 2),
              shadows: [
                Shadow(
                  color: Colors.black38,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny "resolving address" chip shown under the center pin while the
/// Geocoding API call is in flight.
class _ResolvingAddressChip extends StatelessWidget {
  const _ResolvingAddressChip();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.translate(
        offset: const Offset(0, 44),
        child: Material(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  'Resolving address...',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
