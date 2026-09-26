import 'package:flutter/material.dart';

/// Slim banner shown above the shell content whenever the device loses
/// connectivity. Renders nothing while online, so it can always stay mounted.
class OfflineBanner extends StatelessWidget {
  final bool isConnected;

  const OfflineBanner({super.key, required this.isConnected});

  @override
  Widget build(BuildContext context) {
    if (isConnected) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.wifi_off, size: 16, color: colors.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "You're offline — some content may be unavailable",
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
