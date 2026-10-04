import 'package:flutter/material.dart';
import '../../../../core/widgets/skeletons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/list_loading_view.dart';
import '../../../location/domain/models/saved_address.dart';
import '../../../location/presentation/controllers/location_controller.dart';
import '../controllers/addresses_controller.dart';

/// Address book: view / add / remove saved addresses and choose the
/// default one for discovery.
class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(addressesControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Addresses')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addAddressFab'),
        onPressed: () => _openAddSheet(context, ref),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add address'),
      ),
      body: addressesAsync.when(
        // A LIST of saved addresses. The FAB stays live during the load — adding
        // an address does not need the existing ones to have arrived.
        loading: () => ListLoadingView(
          message: 'Loading your addresses…',
          // `ListTile`s with a circular icon leading — the same silhouette the
          // loaded cards have, so nothing shifts when they arrive.
          shape: SkeletonRowShape.tile,
          onRetry: () =>
              ref.read(addressesControllerProvider.notifier).refresh(),
        ),
        error: (_, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.location_off_outlined,
                size: 64,
                color: AppColors.error,
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Couldn\'t load your addresses',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton.icon(
                key: const Key('addressesRetryButton'),
                onPressed: () =>
                    ref.read(addressesControllerProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
        data: (addresses) {
          if (addresses.isEmpty) {
            return const _EmptyAddressesView();
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              96,
            ),
            itemCount: addresses.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final address = addresses[index];
              return _AddressCard(
                address: address,
                onSetDefault: () async {
                  await ref
                      .read(addressesControllerProvider.notifier)
                      .setDefaultAddress(address.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '"${address.label}" is now your default address.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                onEdit: () => _openEditSheet(context, ref, address),
                onDelete: () => _confirmDelete(context, ref, address),
              );
            },
          );
        },
      ),
    );
  }

  void _openAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddAddressSheet(),
    );
  }

  /// Opens the same label sheet in edit mode, pre-filled with the current
  /// label. Coordinates are preserved unless the customer picks a new spot.
  void _openEditSheet(
    BuildContext context,
    WidgetRef ref,
    SavedAddress address,
  ) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddAddressSheet(
        existing: address,
        onSubmit: (label) async {
          final ok = await ref
              .read(addressesControllerProvider.notifier)
              .updateAddress(id: address.id, label: label);
          return ok;
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SavedAddress address,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove address'),
        content: Text('Remove "${address.label}" from your saved addresses?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmDeleteAddress'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(addressesControllerProvider.notifier)
          .removeAddress(address.id);
    }
  }
}

class _AddressCard extends StatelessWidget {
  final SavedAddress address;
  final VoidCallback onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AddressCard({
    required this.address,
    required this.onSetDefault,
    required this.onEdit,
    required this.onDelete,
  });

  IconData get _icon {
    switch (address.label.toLowerCase()) {
      case 'home':
        return Icons.home_outlined;
      case 'work':
      case 'office':
        return Icons.work_outline;
      default:
        return Icons.place_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = address.location.displayAddress.isNotEmpty
        ? address.location.displayAddress
        : '${address.location.latitude.toStringAsFixed(4)}, '
              '${address.location.longitude.toStringAsFixed(4)}';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: address.isSelected
              ? AppColors.primary.withValues(alpha: 0.5)
              : Colors.grey.shade300,
        ),
      ),
      child: ListTile(
        key: Key('address_${address.id}'),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: Icon(_icon, color: AppColors.primary, size: 22),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                address.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (address.isSelected) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Default',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'default') onSetDefault();
            if (value == 'edit') onEdit();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => [
            if (!address.isSelected)
              const PopupMenuItem(
                value: 'default',
                child: ListTile(
                  leading: Icon(Icons.star_outline),
                  title: Text('Set as default'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            const PopupMenuItem(
              key: Key('editAddressMenuItem'),
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Remove'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyAddressesView extends StatelessWidget {
  const _EmptyAddressesView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.location_off_outlined,
              size: 64,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'No saved addresses',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Save your frequent locations for faster discovery.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: () => context.push('/select-location'),
              icon: const Icon(Icons.my_location),
              label: const Text('Pick a location first'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that labels the current active location and saves it.
///
/// Also serves the edit flow: pass [existing] to pre-fill the label and route
/// the submit through [onSubmit] instead of creating a new address.
class _AddAddressSheet extends ConsumerStatefulWidget {
  const _AddAddressSheet({this.existing, this.onSubmit});

  final SavedAddress? existing;
  final Future<bool> Function(String label)? onSubmit;

  @override
  ConsumerState<_AddAddressSheet> createState() => _AddAddressSheetState();
}

class _AddAddressSheetState extends ConsumerState<_AddAddressSheet> {
  final _labelController = TextEditingController();
  String? _labelError;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) _labelController.text = existing.label;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      setState(() => _labelError = 'Please enter a label (e.g. Home, Work).');
      return;
    }
    if (label.length > 40) {
      setState(() => _labelError = 'Label is too long (max 40 characters).');
      return;
    }

    setState(() => _saving = true);

    // Edit mode: update the existing entry, coordinates preserved.
    final submit = widget.onSubmit;
    if (_isEditing && submit != null) {
      final ok = await submit(label);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.pop(context, ok);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? '"$label" updated.' : 'Could not update "$label".',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final saved = await ref
        .read(addressesControllerProvider.notifier)
        .addFromCurrentLocation(label);
    if (!mounted) return;
    Navigator.pop(context, saved);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? '"$label" saved to your addresses.'
              : 'Pick a location first, then save it as an address.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationControllerProvider).location;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Add address',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _isEditing
                ? 'Update the label for this address.'
                : location == null
                ? 'No location selected yet.'
                : location.displayAddress.isNotEmpty
                ? location.displayAddress
                : '${location.latitude.toStringAsFixed(4)}, '
                      '${location.longitude.toStringAsFixed(4)}',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if (!_isEditing && location == null) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                context.push('/select-location');
              },
              icon: const Icon(Icons.my_location),
              label: const Text('Choose a location'),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('addressLabelField'),
            controller: _labelController,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: 'Label (e.g. Home, Work)',
              errorText: _labelError,
              counterText: '',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_labelError != null) setState(() => _labelError = null);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton.icon(
            key: const Key('saveAddressButton'),
            // In edit mode the coordinates already exist, so the button is
            // always enabled; in add mode a location is required first.
            onPressed: (!_isEditing && location == null) || _saving
                ? null
                : _save,
            icon: Icon(_isEditing ? Icons.check : Icons.bookmark_add_outlined),
            label: Text(_isEditing ? 'Save changes' : 'Save address'),
          ),
        ],
      ),
    );
  }
}
