import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/ui/app_section_header.dart';
import '../../../../core/ui/numeric_input.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../shops/presentation/controllers/shops_controller.dart';
import '../controllers/auth_controller.dart';

/// First-time Shopkeeper profile creation — shown after the very first Google
/// sign-in when the shopkeeper has no shop yet.
///
/// Google profile data (name, email) is prefilled and editable. The user can
/// only proceed once the required shop + identity fields are filled. On submit
/// the shop is created, the session is refreshed, and the app lands on the
/// Dashboard.
class CreateProfileScreen extends ConsumerStatefulWidget {
  const CreateProfileScreen({super.key});

  @override
  ConsumerState<CreateProfileScreen> createState() =>
      _CreateProfileScreenState();
}

class _CreateProfileScreenState extends ConsumerState<CreateProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _shopName = TextEditingController();
  final _email = TextEditingController();
  final _contactNumber = TextEditingController();
  final _tagline = TextEditingController();
  String? _category;
  String? _businessType;
  bool _submitting = false;
  String? _error;

  // Approved business categories (backend-driven codes, no Grocery/Food).
  static const _categories = <(String code, String label)>[
    ('PHARMACY_HEALTHCARE', 'Pharmacy & Healthcare'),
    ('BEAUTY_PERSONAL_CARE', 'Beauty & Personal Care'),
    ('FURNITURE_HOME_CARE', 'Furniture & Home Care'),
    ('HOUSEHOLD_GOODS', 'Household Goods'),
    ('SPORTS_FITNESS_OUTDOOR', 'Sports, Fitness & Outdoor'),
    ('BOOKS_MEDIA_STATIONERY', 'Books, Media & Stationery'),
    ('AUTOMOTIVE_PARTS_TOOLS', 'Automotive Parts & Tools'),
    ('HARDWARE', 'Hardware'),
    ('RESTAURANTS', 'Restaurants'),
    ('TRANSPORT', 'Transport'),
    ('PERSONAL_TRANSPORT_TRAVEL', 'Personal Transport / Personal Travel'),
  ];

  static const _businessTypes = <String>[
    'Retail',
    'Wholesale',
    'Retail + Wholesale',
    'Service',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    // Prefill Google profile data (editable by the user).
    final user = ref.read(authControllerProvider).user;
    if (user != null) {
      _fullName.text = user.name ?? '';
      _email.text = user.email ?? '';
    }
  }

  @override
  void dispose() {
    _fullName.dispose();
    _shopName.dispose();
    _email.dispose();
    _contactNumber.dispose();
    _tagline.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Prevent duplicate submissions — this screen must never fire two
    // concurrent create requests (double-tap safe).
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // 1) Create the shop THROUGH the shops layer (location/address are
      //    optional at this stage). The controller owns the POST contract,
      //    refreshes the authorized-shops list and selects the new business.
      final shopPayload = <String, dynamic>{
        'name': _shopName.text.trim(),
        'category': _category,
        'business_type': _businessType,
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone': _contactNumber.text.trim().isEmpty
            ? null
            : _contactNumber.text.trim(),
        if (_tagline.text.trim().isNotEmpty) 'tagline': _tagline.text.trim(),
      };

      final shop =
          await ref.read(shopsControllerProvider.notifier).registerShop(
                shopPayload,
              );
      if (shop == null) {
        // The controller already carries the backend's own message.
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = ref.read(shopsControllerProvider).errorMessage ??
              'Could not create your shop. Please retry.';
        });
        return;
      }

      // 2) Update user profile with the full name (best-effort — shop creation
      //    already succeeded, so this must never block onboarding).
      final fullName = _fullName.text.trim();
      if (fullName.isNotEmpty) {
        try {
          await ref
              .read(authRepositoryProvider)
              .updateProfile(name: fullName);
        } catch (_) {
          // Profile update is best-effort; shop creation already succeeded.
        }
      }

      // 3) Refresh auth state so profileComplete becomes true.
      await ref
          .read(authControllerProvider.notifier)
          .refreshAfterProfileCreate(shop.summary);

      if (!mounted) return;
      context.go(Routes.dashboard);
    } catch (e) {
      // Non-API failures: network timeout, DNS, parsing, etc.
      debugPrint('[PROFILE] create failed (non-API): $e');
      if (mounted) {
        final message = e.toString().contains('timeout')
            ? 'Connection timed out. Check your internet and try again.'
            : 'Could not create profile. Please try again.';
        setState(() {
          _submitting = false;
          _error = message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Your Shopkeeper Profile'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _submitting
                ? null
                : () => ref.read(authControllerProvider.notifier).logout(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 32 : 20,                        vertical: 20,
                      ),
                      children: [
                        Text('Welcome to HyperLocal!',
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                            'Set up your shop to start managing products and inventory.',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: theme.colorScheme.outline)),
                        const SizedBox(height: 28),

                        // ── Identity ────────────────────────
                        _SectionLabel('Identity'),
                        TextFormField(
                          controller: _fullName,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Please enter your name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText: 'you@example.com',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return 'Please enter your email';
                            if (!t.contains('@')) return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _contactNumber,
                          keyboardType: TextInputType.phone,
                          inputFormatters: NumericInput.phone(),
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Contact Number (optional)',
                            hintText: '99999 99999',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ── Business ───────────────────────
                        _SectionLabel('Business'),
                        TextFormField(
                          controller: _shopName,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Shop / Business Name',
                            hintText: 'e.g. Kirana Corner',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.storefront_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Please enter your shop name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _category,
                          // isExpanded prevents the long labels (e.g.
                          // "Personal Transport / Personal Travel") from
                          // overflowing the field's right edge.
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Business Category',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                          hint: const Text('Select a category'),
                          items: [
                            for (final (code, label) in _categories)
                              DropdownMenuItem(value: code, child: Text(label)),
                          ],
                          onChanged: (v) => setState(() => _category = v),
                          validator: (v) =>
                              v == null ? 'Please select a category' : null,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _businessType,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Business Type',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                          hint: const Text('Select a type'),
                          items: [
                            for (final t in _businessTypes)
                              DropdownMenuItem(value: t, child: Text(t)),
                          ],
                          onChanged: (v) => setState(() => _businessType = v),
                          validator: (v) =>
                              v == null ? 'Please select a business type' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _tagline,
                          textCapitalization: TextCapitalization.sentences,
                          maxLength: 120,
                          decoration: const InputDecoration(
                            labelText: 'Tagline (optional)',
                            hintText: 'A short description of your shop',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.tag_outlined),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(_error!,
                                style:
                                    TextStyle(color: theme.colorScheme.error)),
                          ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Sticky submit (stays above keyboard) ──────
              Container(
                padding: EdgeInsets.fromLTRB(
                    isWide ? 32 : 20, 12, isWide ? 32 : 20,
                    bottomInset > 0 ? 8 : 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                      top: BorderSide(color: theme.dividerColor)),
                ),
                // Height is a *minimum*, so the label can grow with the
                // system font scale instead of clipping (see TextScalePolicy).
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: _submitting
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('Creating Profile...',
                                style: TextStyle(fontSize: 16)),
                          ],
                        )
                      : const Text('Create Profile',
                          style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    // Shared section-title type so this screen's sections look like every
    // other screen's; only the surrounding gap is local.
    return AppSectionHeader(
      title: text,
      padding: const EdgeInsets.only(bottom: 10, top: 4),
    );
  }
}
