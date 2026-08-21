import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/notifications_controller.dart';
import '../../domain/models/app_notification.dart';
import '../../../../core/theme/app_theme.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsControllerProvider);
    final controller = ref.read(notificationsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (notifications.isNotEmpty) ...[
            TextButton(
              onPressed: () => controller.markAllAsRead(),
              child: const Text('Mark all read'),
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear All',
              onPressed: () => controller.clearAll(),
            ),
          ]
        ],
      ),
      body: notifications.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 64, color: AppColors.textMuted),
                  SizedBox(height: AppSpacing.md),
                  Text('No notifications yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: AppSpacing.sm),
                  Text('We will notify you about orders and price updates.', style: TextStyle(color: AppColors.textMuted)),
                ],
              ),
            )
          : ListView.separated(
              itemCount: notifications.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = notifications[index];
                return ListTile(
                  tileColor: item.isRead ? null : AppColors.primary.withValues(alpha: 0.05),
                  leading: CircleAvatar(
                    backgroundColor: item.isRead ? Colors.grey.shade200 : AppColors.primary.withValues(alpha: 0.2),
                    child: Icon(
                      _getIcon(item.type),
                      color: item.isRead ? Colors.grey : AppColors.primary,
                      size: 20,
                    ),
                  ),
                  title: Text(item.title, style: TextStyle(fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold)),
                  subtitle: Text(item.body),
                  trailing: Text(
                    '${item.timestamp.hour}:${item.timestamp.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  onTap: () => controller.markAsRead(item.id),
                );
              },
            ),
    );
  }

  IconData _getIcon(NotificationType type) {
    switch (type) {
      case NotificationType.orderUpdate:
        return Icons.local_shipping_outlined;
      case NotificationType.priceAlert:
        return Icons.sell_outlined;
      case NotificationType.promotional:
        return Icons.campaign_outlined;
      case NotificationType.system:
        return Icons.notifications_outlined;
    }
  }
}