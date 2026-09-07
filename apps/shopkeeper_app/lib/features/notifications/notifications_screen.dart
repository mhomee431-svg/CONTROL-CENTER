import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifications screen for shopkeeper app.
///
/// Shows:
/// - Inventory alerts
/// - Order notifications
/// - Subscription updates
/// - POS sync status
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: Load notifications from backend
    final notifications = <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () {
              // TODO: Mark all as read
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You\'ll see inventory alerts and updates here',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: Icon(_getIcon(notification['type'])),
                    title: Text(notification['title'] ?? ''),
                    subtitle: Text(notification['body'] ?? ''),
                    trailing: Text(_formatTime(notification['created_at'])),
                    onTap: () {
                      // TODO: Navigate to relevant screen
                    },
                  ),
                );
              },
            ),
    );
  }

  IconData _getIcon(String? type) {
    return switch (type) {
      'INVENTORY_LOW' => Icons.inventory_2,
      'ORDER' => Icons.shopping_bag,
      'SUBSCRIPTION' => Icons.card_membership,
      'POS_SYNC' => Icons.sync,
      _ => Icons.notifications,
    };
  }

  String _formatTime(String? time) {
    if (time == null) return '';
    // TODO: Format time properly
    return time;
  }
}