import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/home_data.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/theme/app_theme.dart';

/// Provider that fetches nearby shops for a given 6-digit area pin code.
final shopsByPinProvider = FutureProvider.autoDispose
    .family<List<Shop>, String>((ref, pin) async {
      final apiClient = ref.watch(apiClientProvider);
      final data = await apiClient.get(
        ApiEndpoints.nearbyShops,
        queryParameters: {'pincode': pin},
        requiresAuth: false,
      );

      if (data is Map<String, dynamic> && data['shops'] is List) {
        return (data['shops'] as List)
            .map((e) => Shop.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    });

/// Shows shops near a manually-entered area pin code.
class SearchResultsByPinScreen extends ConsumerWidget {
  final String pin;

  const SearchResultsByPinScreen({super.key, required this.pin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopsAsync = ref.watch(shopsByPinProvider(pin));

    return Scaffold(
      appBar: AppBar(title: const Text('Shops near your pin')),
      body: shopsAsync.when(
        data: (shops) {
          if (shops.isEmpty) {
            return const Center(
              child: Text('No shops found for this pin code.'),
            );
          }
          return ListView.separated(
            itemCount: shops.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final shop = shops[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: NetworkImage(shop.imageUrl),
                ),
                title: Text(shop.name),
                subtitle: Text(
                  'Distance: ${shop.distance.toStringAsFixed(1)} km • '
                  'Rating: ${shop.rating.toStringAsFixed(1)}',
                ),
                trailing: shop.isVerified
                    ? const Icon(Icons.verified, color: AppColors.primary)
                    : null,
                onTap: () => context.push('/shop/${shop.id}'),
              );
            },
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }
}
