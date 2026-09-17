import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/shop_repository.dart';
import '../../domain/shop_models.dart';
import '../controllers/shop_profile_controller.dart';
import '../widgets/holidays_section.dart';
import '../widgets/shop_profile_shared.dart';

/// Operating Hours — the shop's weekly schedule (`GET/PUT
/// /shopkeeper/shops/{id}/hours`), the 24×7 switch (`PUT .../settings`) and
/// the holiday closures that override the week.
class OperatingHoursScreen extends ConsumerStatefulWidget {
  const OperatingHoursScreen({super.key});

  @override
  ConsumerState<OperatingHoursScreen> createState() =>
      _OperatingHoursScreenState();
}

class _OperatingHoursScreenState extends ConsumerState<OperatingHoursScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(shopHoursProvider.notifier).load();
      if (ref.read(shopProfileDetailProvider).status !=
          ShopProfileStatus.ready) {
        ref.read(shopProfileDetailProvider.notifier).load();
      }
    });
  }

  Future<void> _pickTime(ShopHourEntry entry, {required bool isOpen}) async {
    final current = (isOpen ? entry.openTime : entry.closeTime) ?? '09:00';
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      ),
    );
    if (picked == null) return;
    final label = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    ref.read(shopHoursProvider.notifier).updateEntry(
          isOpen ? entry.copyWith(openTime: label) : entry.copyWith(closeTime: label),
        );
  }

  Future<void> _toggle24x7(bool value) async {
    final shop = ref.read(selectedShopProvider);
    if (shop == null) return;
    try {
      await ref
          .read(shopRepositoryProvider)
          .updateSettings(
            shop.id,
            {'is_open_24x7': value},
            (await ref.read(tokenStoreProvider).readAccessToken())!,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? 'Marked open 24×7' : '24×7 turned off')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update failed. Please retry.')),
      );
    }
    await ref.read(shopProfileDetailProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final hoursState = ref.watch(shopHoursProvider);
    final detailState = ref.watch(shopProfileDetailProvider);
    final canEdit = shopCanEdit(ref);
    final scheme = Theme.of(context).colorScheme;

    // Surface validation / save messages exactly once.
    ref.listen<ShopHoursState>(shopHoursProvider, (prev, next) {
      final message = next.message;
      if (message != null && message != prev?.message) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        ref.read(shopHoursProvider.notifier).clearMessage();
      }
    });

    final detail = detailState.detail;

    return Scaffold(
      appBar: AppBar(title: const Text('Operating hours')),
      body: SafeArea(
        child: switch (hoursState.status) {
          ShopHoursStatus.loading ||
          ShopHoursStatus.error when hoursState.hours.isEmpty => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hoursState.message ?? 'Loading your operating hours…',
                    style: TextStyle(fontSize: 13, color: scheme.outline),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('shop-hours-retry'),
                    onPressed: () =>
                        ref.read(shopHoursProvider.notifier).load(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          _ => _HoursBody(
              detail: detail,
              canEdit: canEdit,
              saving: hoursState.saving,
              hours: hoursState.hours,
              onToggle24x7: _toggle24x7,
              onPickTime: _pickTime,
            ),
        },
      ),
    );
  }
}

/// The scrollable hours editor: 24×7 switch, the week and the save action.
class _HoursBody extends ConsumerWidget {
  const _HoursBody({
    required this.detail,
    required this.canEdit,
    required this.saving,
    required this.hours,
    required this.onToggle24x7,
    required this.onPickTime,
  });

  final ShopDetail? detail;
  final bool canEdit;
  final bool saving;
  final List<ShopHourEntry> hours;
  final ValueChanged<bool> onToggle24x7;
  final void Function(ShopHourEntry entry, {required bool isOpen}) onPickTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (detail != null) ...[
          Card(
            key: const Key('shop-hours-24x7'),
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('Open 24×7'),
              subtitle: const Text(
                'Ignore the weekly schedule below entirely.',
                style: TextStyle(fontSize: 12),
              ),
              value: detail!.isOpen24x7,
              onChanged: canEdit ? onToggle24x7 : null,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text('Weekly schedule', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          key: const Key('shop-hours-list'),
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < hours.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _DayRow(
                  entry: hours[i],
                  enabled: canEdit && !saving,
                  onToggleClosed: (closed) => ref
                      .read(shopHoursProvider.notifier)
                      .updateEntry(hours[i].copyWith(isClosed: closed)),
                  onPickTime: (isOpen) => onPickTime(hours[i], isOpen: isOpen),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        HolidaysSection(canEdit: canEdit),
        if (!canEdit) ...[
          const SizedBox(height: 8),
          const ShopPermissionNotice(),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('shop-hours-save'),
          onPressed: (canEdit && !saving)
              ? () => ref.read(shopHoursProvider.notifier).save()
              : null,
          icon: saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Save operating hours'),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'The whole week is saved in one request. Holiday closures '
            'override these times.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        ),
      ],
    );
  }
}

// _DayRow continues below.

/// One weekday: open/closed switch plus the two time fields.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.entry,
    required this.enabled,
    required this.onToggleClosed,
    required this.onPickTime,
  });

  final ShopHourEntry entry;
  final bool enabled;
  final ValueChanged<bool> onToggleClosed;
  final ValueChanged<bool> onPickTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: Key('shop-hours-day-${entry.dayOfWeek}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              entry.dayLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: entry.isClosed
                ? Text(
                    'Closed',
                    style: TextStyle(fontSize: 13, color: scheme.outline),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          key: Key('shop-hours-open-${entry.dayOfWeek}'),
                          onTap: enabled ? () => onPickTime(true) : null,
                          borderRadius: BorderRadius.circular(8),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Opens',
                              isDense: true,
                            ),
                            child: Text(
                              entry.openTime ?? '—',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          key: Key('shop-hours-close-${entry.dayOfWeek}'),
                          onTap: enabled ? () => onPickTime(false) : null,
                          borderRadius: BorderRadius.circular(8),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Closes',
                              isDense: true,
                            ),
                            child: Text(
                              entry.closeTime ?? '—',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          Switch(
            key: Key('shop-hours-closed-${entry.dayOfWeek}'),
            value: entry.isClosed,
            onChanged: enabled ? onToggleClosed : null,
          ),
        ],
      ),
    );
  }
}