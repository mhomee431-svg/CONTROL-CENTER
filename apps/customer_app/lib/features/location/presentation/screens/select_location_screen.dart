import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/location_repository.dart';
import '../../domain/models/saved_address.dart';
import '../../domain/models/user_location.dart';
import '../controllers/location_controller.dart';

/// "Find Products Around You" — the single place the customer picks where
/// they are searching from.
///
/// Offers exactly four ways in: **Use Current Location**, **Choose on Map**,
/// **Enter Area/Address** and **Choose Saved Address**, plus a recent-locations
/// strip. Location permission is requested *only* when the customer taps
/// "Use Current Location" — opening this screen never prompts.
///
/// The app never claims a fix is exact: the selected location carries the
/// device's reported accuracy and it is shown verbatim. Shop distances come
/// from the backend, which is the only place they are computed.
class SelectLocationScreen extends ConsumerStatefulWidget {
  const SelectLocationScreen({super.key});

  @override
  ConsumerState<SelectLocationScreen> createState() =>
      _SelectLocationScreenState();
}

class _SelectLocationScreenState extends ConsumerState<SelectLocationScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<UserLocation> _results = [];
  List<SavedAddress> _savedAddresses = [];
  List<UserLocation> _recentLocations = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadSupportingData);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Loads saved addresses + recents. Neither is allowed to fail the screen.
  Future<void> _loadSupportingData() async {
    final controller = ref.read(locationControllerProvider.notifier);
    final addresses = await controller.loadSavedAddresses();
    final recents = await controller.loadRecentLocations();
    if (!mounted) return;
    setState(() {
      _savedAddresses = addresses;
      _recentLocations = recents;
    });
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _useCurrentLocation() async {
    await ref
        .read(locationControllerProvider.notifier)
        .fetchCurrentLocation(force: true);
    if (!mounted) return;
    await _loadSupportingData();
  }

  Future<void> _chooseOnMap() async {
    await context.push('/map-picker');
    if (!mounted) return;
    await _loadSupportingData();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _isSearching = true);
    final results = await ref
        .read(locationRepositoryProvider)
        .searchManualLocations(query.trim());
    if (!mounted) return;
    setState(() {
      _results = results;
      _isSearching = false;
    });
  }

  Future<void> _selectManual(UserLocation location) async {
    await ref
        .read(locationControllerProvider.notifier)
        .setManualLocation(location);
    if (!mounted) return;
    await _loadSupportingData();
  }

  Future<void> _selectSaved(SavedAddress address) async {
    await ref
        .read(locationControllerProvider.notifier)
        .selectSavedAddress(address);
    if (!mounted) return;
    await _loadSupportingData();
  }

  void _continue() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  static IconData _iconForLabel(String label) => switch (label.toLowerCase()) {
    'home' => Icons.home_outlined,
    'work' || 'office' => Icons.work_outline,
    _ => Icons.place_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(locationControllerProvider);
    final selected = locationState.location;
    final canContinue = selected != null && selected.hasValidCoordinates;
    final isLoading = locationState.status == LocationStatus.loading;

    return Scaffold(
      appBar: AppBar(title: const Text('Find Products Around You')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            if (selected != null && selected.hasValidCoordinates)
              _LocationPreview(
                location: selected,
                onOpenMap: () => context.push('/map-picker'),
              ),
            if (isLoading) const _DetectingBanner(),

            // ── Option 1: current location (the only permission prompt) ──
            _OptionTile(
              tileKey: const Key('useCurrentLocationOption'),
              icon: Icons.my_location,
              title: 'Use Current Location',
              subtitle: isLoading
                  ? 'Detecting…'
                  : 'Let the device find where you are',
              trailing: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : null,
              onTap: isLoading ? null : _useCurrentLocation,
            ),
            _LocationProblemNotice(state: locationState),

            // ── Option 2: map ──
            _OptionTile(
              tileKey: const Key('chooseOnMapOption'),
              icon: Icons.map_outlined,
              title: 'Choose on Map',
              subtitle: 'Drop a pin at the spot you want',
              onTap: _chooseOnMap,
            ),

            // ── Option 3: manual area search ──
            _OptionTile(
              tileKey: const Key('enterAreaOption'),
              icon: Icons.search,
              title: 'Enter Area/Address',
              subtitle: 'Search by city, area or PIN code',
              onTap: () => FocusScope.of(context).requestFocus(),
            ),
            TextField(
              key: const Key('areaSearchField'),
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Search for your area…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _results = []);
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (_isSearching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else
              ..._results.map(
                (location) => ListTile(
                  key: Key(
                    'areaResult_${location.latitude}_${location.longitude}',
                  ),
                  leading: const Icon(Icons.place_outlined),
                  title: Text(location.city.isEmpty ? 'Area' : location.city),
                  subtitle: Text(
                    [
                      location.state,
                      location.pincode,
                    ].where((part) => part.isNotEmpty).join(' - '),
                  ),
                  onTap: () => _selectManual(location),
                ),
              ),

            // ── Option 4: saved addresses ──
            _SectionHeading(
              title: 'Choose Saved Address',
              actionLabel: 'Manage',
              onAction: () => context.push('/profile/addresses'),
            ),
            if (_savedAddresses.isEmpty)
              const _HintCard(
                message:
                    'No saved addresses yet. Pick a location, then save it as '
                    'Home, Work or Other.',
              )
            else
              ..._savedAddresses.map(
                (address) => ListTile(
                  key: Key('savedAddressOption_${address.id}'),
                  leading: Icon(
                    _iconForLabel(address.label),
                    color: AppColors.primary,
                  ),
                  title: Text(address.label),
                  subtitle: Text(
                    address.location.displayAddress.isEmpty
                        ? 'Saved location'
                        : address.location.displayAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: address.isSelected
                      ? const Icon(Icons.check_circle, color: AppColors.primary)
                      : const Icon(Icons.chevron_right),
                  onTap: () => _selectSaved(address),
                ),
              ),

            // ── Recent locations ──
            if (_recentLocations.isNotEmpty) ...[
              const _SectionHeading(title: 'Recent Locations'),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _recentLocations.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final recent = _recentLocations[index];
                    return ActionChip(
                      key: Key('recentLocation_$index'),
                      avatar: const Icon(Icons.history, size: 18),
                      label: Text(
                        recent.city.isNotEmpty
                            ? recent.city
                            : recent.displayLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => _selectManual(recent),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.lg),
            // ── Primary CTA ──
            ElevatedButton.icon(
              key: const Key('continueButton'),
              onPressed: canContinue ? _continue : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact preview of the selected point with the **device-reported**
/// accuracy. This is a deliberately lightweight map-style preview; the real
/// interactive map lives in the map picker, which this card opens.
class _LocationPreview extends StatelessWidget {
  const _LocationPreview({required this.location, required this.onOpenMap});

  final UserLocation location;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    final captured = location.capturedAt;
    return Container(
      key: const Key('locationPreview'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFFE8F0FE), Color(0xFFF8FAFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onOpenMap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: AppColors.error,
                    size: 36,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          location.displayLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        if (location.displayAddress.isNotEmpty)
                          Text(
                            location.displayAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.open_in_full, size: 18),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Accuracy is reported exactly as the device gave it — the app never
          // claims a precision it does not have.
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  location.isLowAccuracy ? Icons.info_outline : Icons.gps_fixed,
                  size: 14,
                  color: location.isLowAccuracy
                      ? AppColors.error
                      : AppColors.secondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    location.accuracySummary,
                    key: const Key('accuracySummary'),
                    style: TextStyle(
                      fontSize: 11,
                      color: location.isLowAccuracy
                          ? AppColors.error
                          : AppColors.textMuted,
                    ),
                  ),
                ),
                if (captured != null)
                  Text(
                    _formatTime(captured),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return 'at $hour:$minute';
  }
}

/// Banner shown while a GPS fix is in flight.
class _DetectingBanner extends StatelessWidget {
  const _DetectingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('detectingBanner'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
          ),
          SizedBox(width: AppSpacing.sm),
          Text('Finding your location…', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// Explains *why* detection failed and always keeps a permission-free way
/// forward available.
class _LocationProblemNotice extends StatelessWidget {
  const _LocationProblemNotice({required this.state});

  final LocationState state;

  @override
  Widget build(BuildContext context) {
    final (message, hint) = switch (state.status) {
      LocationStatus.permissionDenied => (
        'Location permission denied.',
        'Allow it to use GPS, or pick an area / map point instead.',
      ),
      LocationStatus.permissionPermanentlyDenied => (
        'Location permission is blocked.',
        'Enable it in your device settings, or pick an area instead.',
      ),
      LocationStatus.serviceDisabled => (
        'Location services (GPS) are turned off.',
        'Turn GPS on, or pick an area / map point instead.',
      ),
      LocationStatus.error => (
        state.errorMessage ?? 'Could not detect your location.',
        'You can still choose an area, a map point or a saved address.',
      ),
      _ => (null, null),
    };

    if (message == null || hint == null) return const SizedBox.shrink();

    return Container(
      key: const Key('locationProblemNotice'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_off, size: 16, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the four primary ways to choose a location.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: tileKey,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: AppColors.textMuted,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              key: Key('sectionAction_$title'),
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('emptyAddressesHint'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
