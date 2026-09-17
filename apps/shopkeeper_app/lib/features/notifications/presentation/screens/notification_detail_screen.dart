import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/notification_models.dart';
import '../controllers/notifications_controller.dart';

/// Full detail view for one notification, reached from the notification center
/// list (which passes the row through `state.extra`).
///
/// [notification] is nullable on purpose: the route can also be reached without
/// an `extra` (a cold-start deep link), and an unconditional cast would crash
/// the router instead of showing a friendly empty state.
class NotificationDetailScreen extends ConsumerStatefulWidget {
  const NotificationDetailScreen({super.key, this.notification});

  final ShopkeeperNotification? notification;

  @override
  ConsumerState<NotificationDetailScreen> createState() =>
      _NotificationDetailScreenState();
}

class _NotificationDetailScreenState
    extends ConsumerState<NotificationDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;
    final scheme = Theme.of(context).colorScheme;

    // No payload (the route was opened without an `extra`) — explain instead of
    // rendering an empty card.
    if (notification == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notification')),
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Open a notification from the Alerts tab to see its details.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    final typeLabel = notification.type.isNotEmpty
        ? notification.type.replaceAllMapped(
            RegExp(r'[A-Z]+'),
            (m) => '${m[0]![0]}${m[0]!.substring(1).toLowerCase()}',
          )
        : 'General';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification'),
        actions: [
          if (!notification.isRead)
            TextButton(
              onPressed: () {
                ref
                    .read(notificationsControllerProvider.notifier)
                    .markAsRead(notification.id);
              },
              child: const Text('Mark read'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          notificationIcon(notification.type),
                          size: 20,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          typeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      notification.title,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notification.body,
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      notificationTimeLabel(notification.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (notification.deepLink != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deep link',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.outline,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        notification.deepLink!,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: notification.deepLink!),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Deep link copied to clipboard'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy link'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
