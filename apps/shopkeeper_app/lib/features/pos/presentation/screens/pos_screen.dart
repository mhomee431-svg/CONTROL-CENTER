import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';

/// POS (Point of Sale) integration — connect, sync, and manage POS data.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  bool _isConnected = false;
  bool _isSyncing = false;
  String? _lastSyncTime;

  Future<void> _connectPos() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      _isConnected = true;
      _lastSyncTime = 'Just now';
    });
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('POS connected successfully')));
  }

  Future<void> _syncData() async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Connect POS first')));
      return;
    }
    setState(() => _isSyncing = true);
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    setState(() {
      _isSyncing = false;
      _lastSyncTime = 'Just now';
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sync complete — 42 products updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('POS integration')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusCard(scheme),
            const SizedBox(height: 16),
            Text('Sync history', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _buildSyncHistory(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.check_circle : Icons.cloud_off,
                  color: _isConnected ? AppTheme.verifiedGreen : scheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isConnected ? 'Connected' : 'Not connected',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (_lastSyncTime != null)
                        Text(
                          'Last sync: $_lastSyncTime',
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
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
                    onPressed: _isConnected ? null : _connectPos,
                    icon: const Icon(Icons.link),
                    label: Text(_isConnected ? 'Connected' : 'Connect POS'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSyncing ? null : _syncData,
                    icon: _isSyncing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(_isSyncing ? 'Syncing...' : 'Sync now'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncHistory(ColorScheme scheme) {
    final hasHistory = _isConnected && _lastSyncTime != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: hasHistory
          ? Column(
              children: const [
                _SyncHistoryTile(
                  time: 'Just now',
                  status: 'success',
                  detail: '42 products synced',
                ),
                Divider(height: 1),
                _SyncHistoryTile(
                  time: '2 hours ago',
                  status: 'success',
                  detail: '38 products synced',
                ),
                Divider(height: 1),
                _SyncHistoryTile(
                  time: 'Yesterday',
                  status: 'error',
                  detail: 'Connection timeout',
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No sync history yet.\nConnect your POS to start syncing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.outline),
                ),
              ),
            ),
    );
  }
}

class _SyncHistoryTile extends StatelessWidget {
  const _SyncHistoryTile({
    required this.time,
    required this.status,
    required this.detail,
  });

  final String time;
  final String status;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final isError = status == 'error';
    return ListTile(
      dense: true,
      leading: Icon(
        isError ? Icons.error_outline : Icons.check_circle,
        size: 20,
        color: isError
            ? Theme.of(context).colorScheme.error
            : AppTheme.verifiedGreen,
      ),
      title: Text(detail, style: const TextStyle(fontSize: 13)),
      trailing: Text(
        time,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
