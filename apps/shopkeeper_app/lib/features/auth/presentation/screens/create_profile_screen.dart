import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/ui/app_section_header.dart';
import '../../../../core/ui/numeric_input.dart';
import '../../../profile/data/profile_repository.dart';
import '../../../shops/domain/capability_fields.dart';
import '../../../shops/domain/shop_models.dart'
    show kBusinessCategoryFallback,
         kBusinessTypes,
         resolveCategoryCapabilities;
import '../../../shops/presentation/controllers/capability_fields_controller.dart';
import '../../../shops/presentation/widgets/capability_fields_view.dart';
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
  /// Capability-driven field values, keyed by [CapabilityFieldSpec.key].
  ///
  /// Held here rather than in the shared view so the values survive the
  /// category changing: picking a different trade must re-render the FIELDS,
  /// not silently discard what was already typed for the one before.
  final Map<String, String> _capabilityValues = <String, String>{};
  bool _submitting = false;
  String? _error;

  // Categories and business types are NOT re-typed here. The central lists live
  // beside the other category data in `shop_models.dart`, pinned to the backend
  // registry by `business_category_test` and `business_type_vocabulary_test`;
  // a private copy is exactly what silently drifted before (it spelled the
  // combined type `Retail & Wholesale`, a string no narrowing rule matches).

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

      // 1b) Capability-driven fields. These need the shop to exist first (the
      //     endpoint is keyed by shop id), so they are a SECOND call rather
      //     than part of the create body.
      //
      //     A failure here is reported, not swallowed: the shop exists, and a
      //     shopkeeper who typed a service area must not be walked to the
      //     dashboard believing it was stored when the server never saw it.
      if (_capabilityValues.isNotEmpty) {
        final saved = await _saveCapabilityFields(shop.summary.id);
        if (!saved) {
          if (!mounted) return;
          setState(() {
            _submitting = false;
            _error =
                'Your shop was created, but its business details could not be '
                'saved. Please open your shop and try again.';
          });
          return;
        }
      }

      // 2) Update user profile with the full name (best-effort — shop creation
      //    already succeeded, so this must never block onboarding).
      final fullName = _fullName.text.trim();
      if (fullName.isNotEmpty) {
        try {
          await ref
              .read(profileRepositoryProvider)
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

  /// PUTs the capability-field values against the freshly created shop.
  ///
  /// Only NON-EMPTY values are sent. The backend validates against the keys
  /// its registry approves for this category and rejects the whole request on a
  /// refusal, so sending a key the server does not know fails the entire save
  /// rather than just that one field.
  Future<bool> _saveCapabilityFields(int shopId) async {
    try {
      final payload = <String, dynamic>{
        for (final entry in _capabilityValues.entries)
          if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
      };
      if (payload.isEmpty) return true;
      await ref.read(apiClientProvider).put(
            ApiEndpoints.shopCapabilityFields(shopId),
            body: payload,
          );
      return true;
    } catch (e) {
      debugPrint('[PROFILE] capability fields not saved: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    // The field set for the CURRENT trade, fetched from the backend once a
    // category exists. The server's list wins over the local table; the
    // controller falls back to the built-in one and marks the result offline.
    final capArg = (
      category: _category ?? '',
      businessType: _businessType,
    );
    final capState = ref.watch(capabilityFieldsProvider(capArg));
    final capFields =
        capState.asData?.value.fields ?? const <CapabilityFieldSpec>[];
    final capSet = resolveCategoryCapabilities(capArg.category, capArg.businessType);
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context).createProfileScreenCreateYourShopkeeperProfile),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _submitting
                ? null
                : () => ref.read(authControllerProvider.notifier).logout(),
            child: Text(appText(context).commonSignOut3),
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
                        Text(appText(context).commonWelcomeToHyperLocal,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                            appText(context).createProfileScreenSetUpYourShopTo,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: theme.colorScheme.outline)),
                        const SizedBox(height: 28),

                        // ── Identity ────────────────────────
                        _SectionLabel('Identity'),
                        TextFormField(
                          controller: _fullName,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: appText(context).commonFullName,
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
                          decoration: InputDecoration(
                            labelText: appText(context).commonEmail,
                            hintText: appText(context).createProfileScreenYouExampleCom,
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
                          decoration: InputDecoration(
                            labelText: appText(context).createProfileScreenContactNumberOptional,
                            hintText: appText(context).common9999999999,
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
                          decoration: InputDecoration(
                            labelText: appText(context).commonShopBusinessName,
                            hintText: appText(context).commonEGKiranaCorner,
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
                          decoration: InputDecoration(
                            labelText: appText(context).commonBusinessCategory,
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                          hint: Text(appText(context).commonSelectACategory),
                          items: [
                            for (final category in kBusinessCategoryFallback)
                              DropdownMenuItem(
                                value: category.code,
                                child: Text(category.displayLabel),
                              ),
                          ],
                          onChanged: (v) => setState(() => _category = v),
                          validator: (v) =>
                              v == null ? 'Please select a category' : null,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _businessType,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: appText(context).commonBusinessType,
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                          hint: Text(appText(context).commonSelectAType),
                          items: [
                            for (final t in kBusinessTypes)
                              DropdownMenuItem(value: t, child: Text(t)),
                          ],
                          onChanged: (v) => setState(() => _businessType = v),
                          validator: (v) =>
                              v == null ? 'Please select a business type' : null,
                        ),
                        const SizedBox(height: 16),
                        // Capability-driven fields. Nothing renders until a
                        // trade is chosen, which is the whole point: a hardware
                        // shop has no "service area" and should never be shown
                        // one, however the form is scrolled.
                        if (capFields.isNotEmpty) ...[
                          CapabilityFieldsView(
                            set: capSet,
                            fields: capFields,
                            values: _capabilityValues,
                            onChanged: (key, value) => setState(
                              () => _capabilityValues[key] = value,
                            ),
                            title: 'Business details',
                          ),
                          if (capState.asData?.value.isOffline ?? false) ...[
                            const SizedBox(height: 10),
                            _OfflineFieldsNotice(
                              onRetry: () => ref.invalidate(
                                capabilityFieldsProvider(
                                  (
                                    category: _category ?? '',
                                    businessType: _businessType,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _tagline,
                          textCapitalization: TextCapitalization.sentences,
                          maxLength: 120,
                          decoration: InputDecoration(
                            labelText: appText(context).commonTaglineOptional,
                            hintText: appText(context).createProfileScreenAShortDescriptionOfYour,
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
                      ? Row(
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
                            Text(appText(context).commonCreatingProfile,
                                style: TextStyle(fontSize: 16)),
                          ],
                        )
                      : Text(appText(context).commonCreateProfile,
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

/// Says out loud that the field list came from the built-in table, not the
/// server.
///
/// Without this the screen renders a complete-looking form from a fallback and
/// says nothing: a shopkeeper who fills in a service area and is walked to a
/// dashboard has no way to know the server never confirmed that category's
/// field set. The Retry is there because the fallback is a network state, and
/// networks come back.
class _OfflineFieldsNotice extends StatelessWidget {
  const _OfflineFieldsNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('capability-fields-offline-notice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing the last known fields for this category. These could '
              'not be confirmed with the server, so they may differ from what '
              'is actually required.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
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
