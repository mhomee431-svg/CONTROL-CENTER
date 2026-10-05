import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_text.dart';
import '../controllers/holiday_controller.dart';
import '../../domain/holiday_models.dart';

/// Holidays management block rendered inside ShopSettingsScreen.
///
/// Purely presentational: it watches [holidaysControllerProvider] (THE owner
/// of holiday state) and forwards intents — no local list copy, no logic.
/// It triggers the initial fetch on mount; the controller stays the single
/// source of truth for everything after that.
class HolidaysSection extends ConsumerStatefulWidget {
  const HolidaysSection({super.key, required this.canEdit});

  /// Mirrors the settings screen's edit permission for the shop.
  final bool canEdit;

  @override
  ConsumerState<HolidaysSection> createState() => _HolidaysSectionState();
}

class _HolidaysSectionState extends ConsumerState<HolidaysSection> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(holidaysControllerProvider.notifier).load());
  }

  bool get canEdit => widget.canEdit;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(holidaysControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(appText(context).commonHolidays,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            if (canEdit)
              IconButton(
                key: const Key('holidays-add'),
                tooltip: appText(context).commonAddAHoliday,
                icon: const Icon(Icons.event_available_outlined),
                onPressed: () => _pickDate(context, ref),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          appText(context).holidaysSectionDaysTheShopStaysClosed,
          style: TextStyle(fontSize: 12, color: scheme.outline),
        ),
        const SizedBox(height: 12),
        switch (state.status) {
          HolidaysStatus.loading => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          HolidaysStatus.error => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state.message ?? 'Something went wrong.',
                    style: TextStyle(color: scheme.error, fontSize: 13)),
                TextButton.icon(
                  onPressed: () =>
                      ref.read(holidaysControllerProvider.notifier).load(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(appText(context).commonRetry12),
                ),
              ],
            ),
          HolidaysStatus.noShop => const SizedBox.shrink(),
          HolidaysStatus.ready when state.items.isEmpty => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                appText(context).commonNoHolidaysScheduled,
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
            ),
          HolidaysStatus.ready => _buildLists(context, ref, state),
        },
      ],
    );
  }

  Widget _buildLists(
    BuildContext context,
    WidgetRef ref,
    HolidaysState state,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final upcoming = state.upcoming;
    final past = state.past;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final holiday in upcoming)
          _HolidayTile(
            holiday: holiday,
            canEdit: canEdit,
          ),
        if (past.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(appText(context).commonPast, style: TextStyle(fontSize: 12, color: scheme.outline)),
          for (final holiday in past)
            _HolidayTile(
              holiday: holiday,
              canEdit: canEdit,
              dimmed: true,
            ),
        ],
      ],
    );
  }

  Future<void> _pickDate(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked == null || !context.mounted) return;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _AddHolidaySheet(date: picked),
    );
  }
}

class _HolidayTile extends ConsumerWidget {
  const _HolidayTile({
    required this.holiday,
    required this.canEdit,
    this.dimmed = false,
  });

  final ShopHoliday holiday;
  final bool canEdit;
  final bool dimmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: Key('holiday-tile-${holiday.id}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        holiday.isRecurringYearly ? Icons.event_repeat : Icons.event_busy,
        color: dimmed ? scheme.outline : scheme.primary,
        size: 22,
      ),
      title: Text(
        holiday.dateLabel,
        style: TextStyle(
          fontSize: 14,
          decoration: dimmed ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: holiday.reason == null || holiday.reason!.isEmpty
          ? null
          : Text(holiday.reason!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: holiday.isRecurringYearly
          ? Text(appText(context).commonEveryYear,
              style: TextStyle(fontSize: 11, color: scheme.outline))
          : (canEdit
              ? IconButton(
                  key: Key('holiday-delete-${holiday.id}'),
                  tooltip: appText(context).commonRemoveHoliday,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () =>
                      _confirmRemoveHoliday(context, ref, holiday),
                )
              : null),
    );
  }
}

/// Asks before removing a holiday (spec §74 — a destructive action must
/// confirm and "explain impact clearly").
///
/// This is a real `DELETE`, not a toggle, and it is one tap on a dense list
/// where a stray finger lands easily. It also changes what CUSTOMERS see: the
/// date stops counting as a closure day and the shop is advertised as open
/// instead, so the confirmation says exactly that. Re-adding the holiday is
/// possible, but only if the shopkeeper notices the gap first — which is the
/// whole reason to ask.
Future<void> _confirmRemoveHoliday(
  BuildContext context,
  WidgetRef ref,
  ShopHoliday holiday,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remove this holiday?'),
      // Named, because the list behind is dense and two holidays can share a
      // label — the date is the only unambiguous identifier.
      content: Text(
        'Customers will stop seeing "${holiday.dateLabel}" as a closure day, '
        'and your shop will be shown as open on that date instead.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(appText(context).commonCancel),
        ),
        FilledButton(
          key: const Key('confirm_remove_holiday'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(appText(context).commonRemove),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(holidaysControllerProvider.notifier).remove(holiday.id);
}

/// Reason + recurrence capture after the date is picked.
class _AddHolidaySheet extends ConsumerStatefulWidget {
  const _AddHolidaySheet({required this.date});

  final DateTime date;

  @override
  ConsumerState<_AddHolidaySheet> createState() => _AddHolidaySheetState();
}

class _AddHolidaySheetState extends ConsumerState<_AddHolidaySheet> {
  final _reason = TextEditingController();
  bool _recurring = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final ok = await ref.read(holidaysControllerProvider.notifier).add(
          HolidayDraft(
            date: widget.date,
            reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
            recurringYearly: _recurring,
          ),
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = ref.read(holidaysControllerProvider).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _dateLabel(widget.date);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appText(context).holidaysSectionAddHolidayLabel(label),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              key: const Key('holiday-reason-field'),
              controller: _reason,
              maxLength: 255,
              decoration: InputDecoration(
                labelText: appText(context).commonReasonOptional,
                hintText: appText(context).holidaysSectionDiwaliStaffTraining,
              ),
            ),
            SwitchListTile(
              key: const Key('holiday-recurring-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(appText(context).commonRepeatsEveryYear),
              value: _recurring,
              onChanged: (v) => setState(() => _recurring = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13)),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('holiday-save'),
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.event_available),
                label: Text(appText(context).commonAddHoliday),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared date label, e.g. `12 Jan 2026` (matches the offer window style).
String _dateLabel(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}

