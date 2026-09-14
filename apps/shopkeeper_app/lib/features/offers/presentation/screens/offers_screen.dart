import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/offers_controller.dart';
import '../widgets/offer_create_sheet.dart';

/// Offers management — active, expired, and create new offers.
class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key});

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _resetOfferSheet() =>
      ref.read(offersControllerProvider.notifier).reset();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offers & pricing'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Expired'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create offer',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const OfferCreateSheet(),
            ).whenComplete(_resetOfferSheet),
          ),
        ],
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _OffersList(status: 'active'),
            _OffersList(status: 'expired'),
          ],
        ),
      ),
    );
  }
}

class _OffersList extends StatelessWidget {
  const _OffersList({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    // Placeholder — in production this would fetch from a backend endpoint
    // that returns offers filtered by status. For now, show empty state.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              status == 'active'
                  ? Icons.local_offer_outlined
                  : Icons.history_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              status == 'active' ? 'No active offers' : 'No expired offers',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              status == 'active'
                  ? 'Create an offer to attract more customers'
                  : 'Expired offers will appear here',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            if (status == 'active') ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const OfferCreateSheet(),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Create offer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
