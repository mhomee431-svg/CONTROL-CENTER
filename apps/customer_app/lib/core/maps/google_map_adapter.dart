import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'map_adapter.dart';

/// A pure, device-independent description of a Google Map scene.
///
/// Kept separate from the widget so marker/polyline/camera logic can be
/// unit-tested without a device or platform channel.
class GoogleMapScene {
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final CameraPosition initialCamera;

  /// Bounds enclosing every point; used to re-frame the camera once the
  /// map renders at a known viewport size.
  final LatLngBounds? bounds;

  GoogleMapScene({
    required this.markers,
    required this.polylines,
    required this.initialCamera,
    this.bounds,
  });

  /// Scene for the single customer → shop directions flow.
  ///
  /// Renders a "you are here" marker, a destination marker, and a dashed
  /// straight-line polyline as a visual direction hint. Turn-by-turn
  /// navigation is delegated to the external maps app (no extra API key).
  factory GoogleMapScene.forRoute({
    required double userLat,
    required double userLng,
    required double destLat,
    required double destLng,
    required String destName,
  }) {
    final userPoint = LatLng(userLat, userLng);
    final destPoint = LatLng(destLat, destLng);
    final rawBounds = _boundsFrom([userPoint, destPoint]);

    return GoogleMapScene(
      markers: {
        Marker(
          markerId: const MarkerId('user_location'),
          position: userPoint,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Your location'),
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: destPoint,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: destName),
        ),
      },
      polylines: {
        Polyline(
          polylineId: const PolylineId('directions_route'),
          points: [userPoint, destPoint],
          color: const Color(0xFF1E7FD6),
          width: 5,
          patterns: [PatternItem.dash(16), PatternItem.gap(8)],
        ),
      },
      initialCamera: _cameraFor(rawBounds, [userPoint, destPoint]),
      bounds: rawBounds,
    );
  }

  /// Scene for the search-results map (many shop markers around the user).
  factory GoogleMapScene.forShops({
    required double userLat,
    required double userLng,
    required List<MapMarkerInfo> shops,
  }) {
    final points = <LatLng>[LatLng(userLat, userLng)];
    final markers = <Marker>[
      Marker(
        markerId: const MarkerId('user_location'),
        position: points.first,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Your location'),
      ),
    ];
    for (var i = 0; i < shops.length; i++) {
      final shop = shops[i];
      final point = LatLng(shop.latitude, shop.longitude);
      points.add(point);
      markers.add(
        Marker(
          markerId: MarkerId('shop_$i'),
          position: point,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
          infoWindow: InfoWindow(title: shop.label, snippet: shop.subtitle),
        ),
      );
    }
    final rawBounds = _boundsFrom(points);
    return GoogleMapScene(
      markers: markers.toSet(),
      polylines: const {},
      initialCamera: _cameraFor(rawBounds, points),
      bounds: rawBounds,
    );
  }

  /// Builds one shop marker (reusable by the search map).
  static Marker shopMarker({
    required int index,
    required double latitude,
    required double longitude,
    required String label,
    String? subtitle,
  }) {
    return Marker(
      markerId: MarkerId('shop_$index'),
      position: LatLng(latitude, longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
      infoWindow: InfoWindow(title: label, snippet: subtitle),
    );
  }

  static LatLngBounds? _boundsFrom(Iterable<LatLng> points) {
    if (points.isEmpty) return null;
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points.skip(1)) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  static CameraPosition _cameraFor(LatLngBounds? bounds, List<LatLng> points) {
    if (bounds == null) {
      return const CameraPosition(target: LatLng(20.5937, 78.9629), zoom: 5);
    }
    final center = LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );
    final latSpan = bounds.northeast.latitude - bounds.southwest.latitude;
    final lngSpan = bounds.northeast.longitude - bounds.southwest.longitude;
    return CameraPosition(target: center, zoom: _zoomForSpan(latSpan, lngSpan));
  }

  /// Heuristic zoom that frames every point inside a phone-sized viewport.
  ///
  /// The map re-frames precisely via `CameraUpdate.newLatLngBounds` once
  /// rendered, so this only needs to be visually close.
  static double _zoomForSpan(double latSpan, double lngSpan) {
    final latDeg = math.max(latSpan.abs(), 0.0003);
    final lngDeg = math.max(lngSpan.abs(), 0.0003);
    final lngZoom = math.log(360 / lngDeg) / math.ln2;
    final latZoom = math.log(180 / latDeg) / math.ln2;
    final raw = math.min(lngZoom, latZoom) - 3.2;
    return raw.clamp(3.0, 19.0).toDouble();
  }
}

/// Real Google Maps implementation of [MapAdapter].
///
/// Uses the official `google_maps_flutter` SDK. The API key is injected at
/// build time (see `EnvConfig.mapsApiKey`, Android manifest placeholder, iOS
/// AppDelegate) and is **never** hardcoded in the repository.
class GoogleMapAdapter implements MapAdapter {
  const GoogleMapAdapter();

  @override
  Widget buildMap({
    required double userLat,
    required double userLng,
    required double destLat,
    required double destLng,
    required String destName,
  }) {
    return GoogleMapsView(
      scene: GoogleMapScene.forRoute(
        userLat: userLat,
        userLng: userLng,
        destLat: destLat,
        destLng: destLng,
        destName: destName,
      ),
    );
  }

  @override
  Widget buildShopsMap({
    required double userLat,
    required double userLng,
    required List<MapMarkerInfo> shops,
  }) {
    return GoogleMapsView(
      scene: GoogleMapScene.forShops(
        userLat: userLat,
        userLng: userLng,
        shops: shops,
      ),
    );
  }

  @override
  Widget buildLoading() {
    return Container(
      color: Colors.grey.shade200,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator.adaptive(),
            SizedBox(height: 16),
            Text('Loading map...'),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildError({required String message, VoidCallback? onRetry}) {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.map_outlined, size: 48, color: Colors.black45),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Stateful wrapper around the platform `GoogleMap` widget.
///
/// Re-frames the camera to the scene bounds once the platform view reports
/// its real viewport dimensions, and exposes the SDK's built-in location
/// controls ("my location" button / blue dot).
class GoogleMapsView extends StatefulWidget {
  final GoogleMapScene scene;

  const GoogleMapsView({super.key, required this.scene});

  @override
  State<GoogleMapsView> createState() => _GoogleMapsViewState();
}

class _GoogleMapsViewState extends State<GoogleMapsView> {
  GoogleMapController? _controller;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: GoogleMap(
        initialCameraPosition: widget.scene.initialCamera,
        mapType: MapType.normal,
        markers: widget.scene.markers,
        polylines: widget.scene.polylines,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        compassEnabled: true,
        zoomControlsEnabled: true,
        onMapCreated: _onMapCreated,
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    _frameCamera();
  }

  Future<void> _frameCamera() async {
    final bounds = widget.scene.bounds;
    final controller = _controller;
    if (controller == null || bounds == null) return;
    try {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
    } catch (_) {
      // Degenerate bounds can fail to animate; the initial camera pose is
      // already a usable fallback.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
