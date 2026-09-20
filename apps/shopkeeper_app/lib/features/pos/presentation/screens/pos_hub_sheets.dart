import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/pos_models.dart';
import '../../../../core/ui/numeric_input.dart';
import '../controllers/pos_controller.dart';

/// ── POS HUB SHEETS ───────────────────────────────────────────────────────
///
/// Two hub actions are dialogs rather than destinations: the terminal map and
/// the sync settings. Keeping them here keeps the hub screen readable.
///
/// Both sheets read and write ONLY through [posControllerProvider] — no local
/// copy of server state, so a save always re-reads the authoritative payload.

/// Opens the terminal map for the loaded connector.
Future<void> showPosTerminalsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _TerminalsSheet(),
  );
}

/// Opens the sync settings (cadence, pause/resume, conflict authority).
Future<void> showPosSyncSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _SyncSettingsSheet(),
  );
}

class _TerminalsSheet extends ConsumerStatefulWidget {
  const _TerminalsSheet();

  @override
  ConsumerState<_TerminalsSheet> createState() => _TerminalsSheetState();
}

class _TerminalsSheetState extends ConsumerState<_TerminalsSheet> {
  @override
  void initState() {
    super.initState();
    // The sheet is a view of server state: load it the moment it opens.
    Future<void>.microtask(
      () => ref.read(posControllerProvider.notifier).loadDevices(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pos = ref.watch(posControllerProvider);
    final integration = pos.integration;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.point_of_sale_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Terminals',
                    key: const Key('pos-terminals-title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Every till, scanner or tablet mapped to this connector.',
              style:
                  TextStyle(fontSize: 12, color: scheme.outline, height: 1.35),
            ),
            const SizedBox(height: 14),
            if (integration == null)
              Text('No connector yet.',
                  style: TextStyle(color: scheme.outline))
            else if (pos.devicesLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (pos.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No terminals mapped yet. Add the first one below.',
                  key: const Key('pos-terminals-empty'),
                  style: TextStyle(color: scheme.outline),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: pos.devices.length,
                  itemBuilder: (context, i) =>
                      _DeviceTile(device: pos.devices[i]),
                ),
              ),
            const SizedBox(height: 8),
            _AddTerminalForm(
              onSubmit: (identifier, name, type) => ref
                  .read(posControllerProvider.notifier)
                  .registerTerminal(
                    deviceIdentifier: identifier,
                    deviceName: name,
                    deviceType: type,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTerminalForm extends StatefulWidget {
  const _AddTerminalForm({required this.onSubmit});

  final Future<bool> Function(String identifier, String? name, String? type) onSubmit;

  @override
  State<_AddTerminalForm> createState() => _AddTerminalFormState();
}

class _AddTerminalFormState extends State<_AddTerminalForm> {
  final _identifier = TextEditingController();
  final _name = TextEditingController();
  String _type = 'POS_TERMINAL';
  bool _busy = false;
  String? _error;

  static const _types = <(String, String)>[
    ('POS_TERMINAL', 'Till'),
    ('SCANNER', 'Scanner'),
    ('TABLET', 'Tablet'),
  ];

  @override
  void dispose() {
    _identifier.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final identifier = _identifier.text.trim();
    if (identifier.isEmpty) {
      setState(() => _error = 'Enter the terminal id from your POS vendor.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final ok = await widget.onSubmit(
      identifier,
      _name.text.trim().isEmpty ? null : _name.text.trim(),
      _type,
    );
    if (!mounted) return;
    if (ok) { _identifier.clear(); _name.clear(); }
    setState(() {
      _busy = false;
      _error = ok ? null : 'The terminal could not be added. Please retry.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        Text('Add a terminal', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        TextField(
          key: const Key('pos-device-identifier'),
          controller: _identifier,
          enabled: !_busy,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Terminal id (from your POS vendor)',
            hintText: 'TILL-01',
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('pos-device-name'),
          controller: _name,
          enabled: !_busy,
          maxLength: 255,
          decoration: const InputDecoration(
            labelText: 'Name (optional)',
            hintText: 'Counter 1',
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          key: const Key('pos-device-type'),
          segments: [
            for (final (value, label) in _types)
              ButtonSegment(value: value, label: Text(label, textScaler: TextScaler.noScaling)),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error)),
        ],
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('pos-device-save'),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add terminal'),
        ),
      ],
    );
  }
}
class _SyncSettingsSheet extends ConsumerStatefulWidget {
  const _SyncSettingsSheet();

  @override
  ConsumerState<_SyncSettingsSheet> createState() => _SyncSettingsSheetState();
}

class _SyncSettingsSheetState extends ConsumerState<_SyncSettingsSheet> {
  final _batchSize = TextEditingController();
  String _inventoryAuthority = 'POS';
  String _priceAuthority = 'PLATFORM';
  bool _busy = false;
  String? _error;

  static const _intervals = <int, String>{
    15: 'Every 15 minutes',
    30: 'Every 30 minutes',
    60: 'Every hour',
    120: 'Every 2 hours',
    240: 'Every 4 hours',
  };

  @override
  void initState() {
    super.initState();
    // The pickers start at the backend defaults (FIELD_AUTHORITIES): stock
    // levels are authoritative at the till, pricing stays with the platform.
    // They are overrides, not a copy of server state: the backend deep-merges
    // whatever is sent, so untouched fields stay untouched.
    _batchSize.text = '';
  }

  Future<void> _toggleSync(bool enabled) async {
    final ok = await ref
        .read(posControllerProvider.notifier)
        .updateSchedule(syncEnabled: enabled);
    if (!mounted || ok) return;
    setState(() => _error = ref.read(posControllerProvider).message ??
        'Could not save the schedule. Please retry.');
  }

  Future<void> _changeInterval(int? minutes) async {
    if (minutes == null) return;
    final ok = await ref
        .read(posControllerProvider.notifier)
        .updateSchedule(intervalMinutes: minutes);
    if (!mounted || ok) return;
    setState(() => _error = ref.read(posControllerProvider).message ??
        'Could not save the schedule. Please retry.');
  }

  Future<void> _saveAuthorities() async {
    final batch = int.tryParse(_batchSize.text.trim());
    if (_batchSize.text.trim().isNotEmpty && (batch == null || batch < 1)) {
      setState(() => _error = 'Batch size must be a whole number of 1 or more.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final ok = await ref.read(posControllerProvider.notifier).updateSyncSettings(
      PosSyncSettings(
        batchSize: batch,
        fieldAuthorities: {
          'inventory': _inventoryAuthority,
          'price': _priceAuthority,
        },
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = ok ? null : 'The settings could not be saved. Please retry.';
    });
  }

  @override
  void dispose() {
    _batchSize.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final integration =
        ref.watch(posControllerProvider.select((s) => s.integration));

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.tune_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Sync settings',
                    key: const Key('pos-settings-title'),
                    style: theme.textTheme.titleMedium),
              ),
            ]),
            const SizedBox(height: 12),
            if (integration == null)
              Text('No connector yet.', style: TextStyle(color: scheme.outline))
            else ...[
              SwitchListTile(
                key: const Key('pos-settings-sync-enabled'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Background sync', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  integration.syncEnabled
                      ? 'Runs automatically on the schedule below'
                      : 'Paused - only manual syncs run',
                  style: const TextStyle(fontSize: 12),
                ),
                value: integration.syncEnabled,
                onChanged: _toggleSync,
              ),
              DropdownButtonFormField<int>(
                key: const Key('pos-settings-interval'),
                initialValue: integration.syncIntervalMinutes != null &&
                        _intervals.containsKey(integration.syncIntervalMinutes)
                    ? integration.syncIntervalMinutes
                    : 60,
                decoration: const InputDecoration(labelText: 'Sync every'),
                items: [
                  for (final entry in _intervals.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: _changeInterval,
              ),
              const Divider(height: 28),
              Text('When the same product disagrees',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'The till is usually the truth for stock levels; the platform '
                'keeps pricing, offers and MRP.',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
              const SizedBox(height: 12),
              _AuthorityPicker(
                fieldKey: const Key('pos-settings-inventory-authority'),
                label: 'Stock levels',
                value: _inventoryAuthority,
                onChanged: (v) => setState(() => _inventoryAuthority = v),
              ),
              const SizedBox(height: 12),
              _AuthorityPicker(
                fieldKey: const Key('pos-settings-price-authority'),
                label: 'Price and MRP',
                value: _priceAuthority,
                onChanged: (v) => setState(() => _priceAuthority = v),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('pos-settings-batch-size'),
                controller: _batchSize,
                keyboardType: TextInputType.number,
                inputFormatters: NumericInput.whole(maxLength: 5),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                decoration: const InputDecoration(
                  labelText: 'Records per batch (optional)',
                  hintText: '500',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error)),
              ],
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('pos-settings-save'),
                onPressed: _busy ? null : _saveAuthorities,
                child: _busy
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AuthorityPicker extends StatelessWidget {
  const _AuthorityPicker({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          key: fieldKey,
          segments: const [
            ButtonSegment(value: 'PLATFORM', label: Text('Platform')),
            ButtonSegment(value: 'POS', label: Text('This till')),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ],
    );
  }
}
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final PosDevice device;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: Key('pos-device-${device.id}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        device.isTerminal ? Icons.point_of_sale : Icons.qr_code_scanner,
        color: device.isActive ? scheme.primary : scheme.outline,
      ),
      title: Text(device.displayName, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        [
          device.deviceIdentifier,
          if (device.deviceType != null && device.deviceType!.isNotEmpty)
            device.deviceType!.toLowerCase().replaceAll('_', ' '),
          if (device.lastConnectedAt != null)
            'last seen ${device.lastConnectedAt}',
        ].join(' | '),
        style: const TextStyle(fontSize: 11),
      ),
      trailing: device.isActive
          ? Text('Active', style: TextStyle(fontSize: 11, color: scheme.primary))
          : Text('Inactive', style: TextStyle(fontSize: 11, color: scheme.outline)),
    );
  }
}