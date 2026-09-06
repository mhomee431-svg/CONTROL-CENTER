import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../data/location_service.dart';

/// Full-screen map where the user taps/drags to pick a shop entrance.
/// Returns a [PickedLocation] with lat/long and reverse-geocoded address.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, this.initialLocation});

  final LatLng? initialLocation;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapController;
  LatLng? _picked;
  bool _loadingAddress = false;

  LatLng get _center =>
      widget.initialLocation ?? const LatLng(25.5941, 85.1376); // Patna fallback

  void _onTap(LatLng position) => setState(() => _picked = position);

  Future<void> _confirm() async {
    if (_picked == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap on the map to pick a location')),
      );
      return;
    }
    setState(() => _loadingAddress = true);
    final address =
        await LocationService.instance.reverseGeocode(_picked!.latitude, _picked!.longitude);
    if (!mounted) return;
    Navigator.of(context).pop(address ??
        PickedLocation(latitude: _picked!.latitude, longitude: _picked!.longitude));
  }

  Future<void> _goToMyLocation() async {
    final status = await LocationService.instance.resolvePermission();
    if (!status.granted || !status.serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enable location services to continue')),
        );
      }
      return;
    }
    final acquisition = await LocationService.instance.acquireBestLocation();
    final best = acquisition.best;
    if (best == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get your location')),
        );
      }
      return;
    }
    final latLng = LatLng(best.latitude, best.longitude);
    setState(() => _picked = latLng);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 17));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick shop location'),
        actions: [
          TextButton.icon(
            onPressed: _loadingAddress ? null : _confirm,
            icon: const Icon(Icons.check),
            label: const Text('Confirm'),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 14),
            onMapCreated: (c) => _mapController = c,
            onTap: _onTap,
            markers: _picked == null
                ? {}
                : {
                    Marker(
                      markerId: const MarkerId('picked'),
                      position: _picked!,
                      draggable: true,
                      onDragEnd: (pos) => _onTap(pos),
                    ),
                  },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
          ),
          if (_picked != null)
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lat: ${_picked!.latitude.toStringAsFixed(6)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        'Lng: ${_picked!.longitude.toStringAsFixed(6)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (_loadingAddress)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goToMyLocation,
        icon: const Icon(Icons.my_location),
        label: const Text('My Location'),
      ),
    );
  }
}