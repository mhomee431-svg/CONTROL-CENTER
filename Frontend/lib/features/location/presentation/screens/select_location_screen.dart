import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../controllers/location_controller.dart';
import '../../domain/models/saved_address.dart';
import '../../domain/models/user_location.dart';
import '../../domain/location_repository.dart';
import '../../../../core/theme/app_theme.dart';

class SelectLocationScreen extends ConsumerStatefulWidget {
  const SelectLocationScreen({super.key});

  @override
  ConsumerState<SelectLocationScreen> createState() => _SelectLocationScreenState();
}

class _SelectLocationScreenState extends ConsumerState<SelectLocationScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<UserLocation> _results = [];
  List<SavedAddress> _savedAddresses = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    // Load saved addresses for the "Saved Addresses" section.
    Future.microtask(() async {
      final controller = ref.read(locationControllerProvider.notifier);
      final addresses = await controller.loadSavedAddresses();
      if (!mounted) return;
      setState(() => _savedAddresses = addresses);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    final repository = ref.read(locationRepositoryProvider);
    final results = await repository.searchManualLocations(query.trim());
    if (!mounted) return;
    setState(() {
      _results = results;
      _isSearching = false;
    });
  }

  void _selectLocation(UserLocation location) {
    ref.read(locationControllerProvider.notifier).setManualLocation(location);
    context.go('/');
  }

  void _selectSavedAddress(SavedAddress address) {
    ref.read(locationControllerProvider.notifier).selectSavedAddress(address);
    context.go('/');
  }

  void _useCurrentLocation() {
    ref.read(locationControllerProvider.notifier).fetchCurrentLocation(force: true);
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(locationControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Your Location'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Current location indicator
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.my_location, color: Colors.white),
                ),
                title: const Text(
                  'Use My Current Location',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  locationState.status == LocationStatus.success
                      ? locationState.location?.displayAddress ?? 'Tap to refresh'
                      : 'Tap to detect your location',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                trailing: locationState.status == LocationStatus.loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, color: AppColors.primary),
                onTap: _useCurrentLocation,
              ),
            ),
            const Divider(height: 1),

            // Saved addresses section
            if (_savedAddresses.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'Saved Addresses',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              ..._savedAddresses.map(
                (address) => ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Icon(Icons.location_city, color: Colors.white),
                  ),
                  title: Text(
                    address.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    address.location.displayAddress,
                    style: const TextStyle(color: AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: address.isSelected
                      ? const Icon(Icons.check_circle, color: AppColors.primary)
                      : const Icon(Icons.chevron_right),
                  onTap: () => _selectSavedAddress(address),
                ),
              ),
              const Divider(height: 1),
            ],

            // Search field
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                controller: _searchController,
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: 'Search for your city...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _search('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : _results.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final location = _results[index];
                            return ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: AppColors.primary,
                                child: Icon(Icons.location_city, color: Colors.white),
                              ),
                              title: Text(
                                location.city,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '${location.state} - ${location.pincode}',
                                style: const TextStyle(color: AppColors.textMuted),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _selectLocation(location),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_off, size: 64, color: AppColors.textMuted),
          SizedBox(height: AppSpacing.md),
          Text(
            'Search for your city',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            'Type a city name to find nearby shops',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}