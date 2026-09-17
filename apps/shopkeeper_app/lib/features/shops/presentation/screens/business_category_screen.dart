import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/token_store.dart';
import '../../data/shop_repository.dart';
import '../../domain/shop_models.dart';
import '../controllers/shop_profile_controller.dart';
import '../widgets/shop_profile_shared.dart';

/// Business Category — what the shop is registered as, the backend-approved
/// catalogue of merchant categories, and the documents/steps each one
/// requires (fetched per tapped category — nothing is hard-coded).
///
/// A shop's category itself is set at registration and locked by verification,
/// so this screen is read-only by contract.
class BusinessCategoryScreen extends ConsumerStatefulWidget {
  const BusinessCategoryScreen({super.key});

  @override
  ConsumerState<BusinessCategoryScreen> createState() =>
      _BusinessCategoryScreenState();
}

class _BusinessCategoryScreenState
    extends ConsumerState<BusinessCategoryScreen> {
  List<MerchantCategoryOption>? _categories;
  String? _error;
  String? _selectedCode;
  CategoryRequirements? _requirements;
  bool _loadingRequirements = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (ref.read(shopProfileDetailProvider).status !=
          ShopProfileStatus.ready) {
        ref.read(shopProfileDetailProvider.notifier).load();
      }
      _loadCategories();
    });
  }

  Future<void> _loadCategories() async {
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null || !mounted) return;
    try {
      final categories =
          await ref.read(shopRepositoryProvider).listMerchantCategories(token);
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load the category catalogue.');
    }
  }

  Future<void> _openRequirements(MerchantCategoryOption option) async {
    setState(() {
      _selectedCode = option.code;
      _requirements = null;
      _loadingRequirements = true;
    });
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null || !mounted) return;
    try {
      final requirements = await ref
          .read(shopRepositoryProvider)
          .getCategoryRequirements(token, option.code);
      if (!mounted) return;
      setState(() {
        _requirements = requirements;
        _loadingRequirements = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requirements = null;
        _loadingRequirements = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shopProfileDetailProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Business category')),
      body: SafeArea(
        child: ShopModuleBody(
          state: state,
          onRetry: () => ref.read(shopProfileDetailProvider.notifier).load(),
          builder: (context, detail) {
            final categories = _categories;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  key: const Key('shop-category-current'),
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Registered as',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.category_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                detail.categoryLabel,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The category is set at registration and verified by '
                          'the platform — changing it starts a new '
                          'verification, so contact support.',
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Approved business categories',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                // _catalogueCard continues below.
                if (_error != null)
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_off_outlined,
                            size: 18,
                            color: scheme.outline,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(fontSize: 12, color: scheme.outline),
                            ),
                          ),
                          TextButton(
                            onPressed: _loadCategories,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (categories == null)
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else
                  Card(
                    key: const Key('shop-category-list'),
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < categories.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            key: Key('shop-category-${categories[i].code}'),
                            dense: true,
                            leading: Icon(
                              _selectedCode == categories[i].code
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              size: 20,
                              color: _selectedCode == categories[i].code
                                  ? Theme.of(context).colorScheme.primary
                                  : scheme.outline,
                            ),
                            title: Text(
                              categories[i].name,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: categories[i].description == null
                                ? null
                                : Text(
                                    categories[i].description!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                            onTap: () => _openRequirements(categories[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_selectedCode != null) ...[
                  const SizedBox(height: 16),
                  _requirementsCard(context),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // _catalogueCard and _requirementsCard continue below.
  Widget _requirementsCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loadingRequirements) {
      return const Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final requirements = _requirements;
    if (requirements == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Could not load the requirements for this category.',
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ),
      );
    }
    return Card(
      key: const Key('shop-category-requirements'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              requirements.categoryName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (requirements.documents.isEmpty)
              Text(
                'No category-specific documents are required.',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              )
            else
              for (final doc in requirements.documents)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        doc.required
                            ? Icons.check_circle_outline
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: scheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          doc.required ? '${doc.label} (required)' : doc.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            Text(
              [
                if (requirements.requiresBankVerification)
                  'Bank verification',
                if (requirements.identityVerificationRequired)
                  'Identity verification',
                if (requirements.adminReviewRequired) 'Platform review',
              ].join(' · '),
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}