import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/shop_profile_controller.dart';
import '../../domain/shop_models.dart';
import '../widgets/shop_profile_shared.dart';

/// Business Information — the read-only facts of the business: identity,
/// registered address, GSTIN, customer rating. Editable contact fields live on
/// the Edit Shop screen.
class BusinessInfoScreen extends ConsumerStatefulWidget {
  const BusinessInfoScreen({super.key});

  @override
  ConsumerState<BusinessInfoScreen> createState() =>
      _BusinessInfoScreenState();
}

class _BusinessInfoScreenState extends ConsumerState<BusinessInfoScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (ref.read(shopProfileDetailProvider).status !=
          ShopProfileStatus.ready) {
        ref.read(shopProfileDetailProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shopProfileDetailProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Business information')),
      body: SafeArea(
        child: ShopModuleBody(
          state: state,
          onRetry: () => ref.read(shopProfileDetailProvider.notifier).load(),
          builder: (context, detail) {
            final address = detail.address;
            final rating = detail.rating;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _FactsCard(
                  key: const Key('shop-info-identity'),
                  title: 'Identity',
                  rows: [
                    (
                      Icons.storefront_outlined,
                      'Shop name',
                      detail.summary.name,
                    ),
                    (
                      Icons.badge_outlined,
                      'Your role',
                      detail.summary.membership == 'owner'
                          ? 'Owner'
                          : 'Manager',
                    ),
                    (Icons.tag, 'Shop ID', '#${detail.summary.id}'),
                    (
                      Icons.event_available_outlined,
                      'Member since',
                      memberSinceLabel(detail.createdAt),
                    ),
                  ],
                ),
                // _addressCard continues below.
                const SizedBox(height: 16),
                _FactsCard(
                  key: const Key('shop-info-address'),
                  title: 'Registered address',
                  rows: [
                    if (address == null || !address.hasContent)
                      (
                        Icons.location_city_outlined,
                        'Address',
                        'No street address on record — customers navigate to '
                            'the shop pin.',
                      )
                    else ...[
                      (
                        Icons.location_city_outlined,
                        'Address',
                        address.formatted,
                      ),
                      if ((address.pincode ?? '').isNotEmpty)
                        (
                          Icons.markunread_mailbox_outlined,
                          'Pincode',
                          address.pincode!,
                        ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _FactsCard(
                  key: const Key('shop-info-compliance'),
                  title: 'Compliance',
                  rows: [
                    (
                      Icons.receipt_long_outlined,
                      'GSTIN',
                      (detail.gstin ?? '').trim().isEmpty
                          ? 'Not provided'
                          : detail.gstin!,
                    ),
                    (
                      Icons.verified_outlined,
                      'Verification',
                      humanizeCode(detail.verification.status),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _FactsCard(
                  key: const Key('shop-info-rating'),
                  title: 'Customer rating',
                  rows: [
                    (
                      rating >= 4
                          ? Icons.star
                          : rating >= 3
                              ? Icons.star_half
                              : Icons.star_border,
                      'Rating',
                      '${rating.toStringAsFixed(1)} · ${detail.reviewCount} '
                          '${detail.reviewCount == 1 ? 'review' : 'reviews'}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'These details come from your shop record. Use Edit shop '
                    'to change the contact fields.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A titled card of [ShopInfoRow]s — the module's read-only building block.
class _FactsCard extends StatelessWidget {
  const _FactsCard({super.key, required this.title, required this.rows});

  final String title;
  final List<(IconData, String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final (icon, label, value) in rows)
              ShopInfoRow(icon: icon, label: label, value: value),
          ],
        ),
      ),
    );
  }
}

/// `12 Jan 2026` from the server's ISO string; the raw value when it cannot
/// be parsed (never an invented date).
String memberSinceLabel(String? createdAt) {
  if (createdAt == null || createdAt.isEmpty) return '—';
  final parsed = DateTime.tryParse(createdAt);
  if (parsed == null) return createdAt;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
}