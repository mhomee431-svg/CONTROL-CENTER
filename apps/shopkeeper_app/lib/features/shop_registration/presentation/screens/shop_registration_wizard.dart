import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/ui/numeric_input.dart';
import '../../../auth/domain/auth_methods.dart';
import '../../../auth/domain/auth_models.dart';
import '../../controllers/shop_registration_controller.dart';
import '../../data/document_picker_service.dart';
import '../../domain/shop_registration_state.dart';
import '../widgets/registration_widgets.dart';
import '../widgets/shop_location_details.dart';

/// The complete "Register Your Shop" wizard — a single screen that hosts all
/// five steps with animated transitions. Back navigation and entered data are
/// preserved because the whole wizard shares one [ShopRegistrationController].
class ShopRegistrationWizard extends ConsumerStatefulWidget {
  const ShopRegistrationWizard({super.key});

  @override
  ConsumerState<ShopRegistrationWizard> createState() =>
      _ShopRegistrationWizardState();
}

class _ShopRegistrationWizardState
    extends ConsumerState<ShopRegistrationWizard> {
  final _name = TextEditingController();
  final _gstin = TextEditingController();
  final _udyam = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();
  final _landmark = TextEditingController();
  final _description = TextEditingController();
  final _website = TextEditingController();
  final _social = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [
      _name,
      _gstin,
      _udyam,
      _address,
      _city,
      _state,
      _pincode,
      _landmark,
      _description,
      _website,
      _social,
    ]) {
      c.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    final controller = ref.read(shopRegistrationControllerProvider.notifier);
    controller.setShopName(_name.text);
    controller.setGstin(_gstin.text);
    controller.setUdyam(_udyam.text);
    controller.setAddressLine(_address.text);
    controller.setCity(_city.text);
    controller.setStateName(_state.text);
    controller.setPincode(_pincode.text);
    controller.setLandmark(_landmark.text);
    controller.setDescription(_description.text);
    controller.setWebsite(_website.text);
    controller.setSocialMedia(_social.text);
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _gstin,
      _udyam,
      _address,
      _city,
      _state,
      _pincode,
      _landmark,
      _description,
      _website,
      _social,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shopRegistrationControllerProvider);
    _syncControllersFromState(state);

    return Scaffold(
      backgroundColor: RegistrationColors.pageBg,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: switch (state.step) {
            RegistrationStep.welcome => _WelcomeStep(
              key: const ValueKey('welcome'),
              onGetStarted: () => ref
                  .read(shopRegistrationControllerProvider.notifier)
                  .startBusinessInfo(),
            ),
            RegistrationStep.businessInfo => _BusinessInfoStep(
              key: const ValueKey('business'),
              state: state,
              name: _name,
              gstin: _gstin,
              udyam: _udyam,
              onBack: _back,
              onNext: _nextFromBusinessInfo,
            ),
            RegistrationStep.location => _LocationStep(
              key: const ValueKey('location'),
              state: state,
              address: _address,
              city: _city,
              stateName: _state,
              pincode: _pincode,
              landmark: _landmark,
              onBack: _back,
              onNext: _nextFromLocation,
            ),
            RegistrationStep.documents => _DocumentsStep(
              key: const ValueKey('documents'),
              state: state,
              description: _description,
              website: _website,
              social: _social,
              onBack: _back,
              onNext: _nextFromDocuments,
            ),
            RegistrationStep.review => _ReviewStep(
              key: const ValueKey('review'),
              state: state,
              onBack: _back,
              onEditBusiness: () => ref
                  .read(shopRegistrationControllerProvider.notifier)
                  .editBusinessInfo(),
              onEditLocation: () => ref
                  .read(shopRegistrationControllerProvider.notifier)
                  .editLocation(),
              onEditDocuments: () => ref
                  .read(shopRegistrationControllerProvider.notifier)
                  .editDocuments(),
              onSubmit: _submit,
              onDismissError: () => ref
                  .read(shopRegistrationControllerProvider.notifier)
                  .clearSubmitError(),
            ),
            RegistrationStep.success => _SuccessStep(
              key: const ValueKey('success'),
              state: state,
              // OTP is FUTURE scope — the SAME `kEnabledAuthMethods`
              // chokepoint the Welcome / Sign-in screens consult. While the
              // method is disabled the success timeline must not advertise a
              // phone-OTP verification, so that row is simply not built.
              showPhoneOtpStep: ref.watch(
                isAuthMethodEnabledProvider(AuthMethod.phoneOtp),
              ),
            ),
          },
        ),
      ),
    );
  }

  /// Push external state changes (geocoding auto-fill) into text fields only
  /// when they differ — preserves cursor position and focus.
  void _syncControllersFromState(ShopRegistrationState state) {
    _sync(_address, state.addressLine);
    _sync(_city, state.city);
    _sync(_state, state.stateName);
    _sync(_pincode, state.pincode);
    _sync(_landmark, state.landmark);
    _sync(_description, state.description);
    _sync(_website, state.website);
    _sync(_social, state.socialMedia);
  }

  void _sync(TextEditingController c, String value) {
    if (c.text != value) c.text = value;
  }

  void _back() => ref.read(shopRegistrationControllerProvider.notifier).back();

  void _nextFromBusinessInfo() {
    final error = ref
        .read(shopRegistrationControllerProvider.notifier)
        .nextFromBusinessInfo();
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _nextFromLocation() {
    final error = ref
        .read(shopRegistrationControllerProvider.notifier)
        .nextFromLocation();
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _nextFromDocuments() =>
      ref.read(shopRegistrationControllerProvider.notifier).nextFromDocuments();

  Future<void> _submit() async {
    await ref.read(shopRegistrationControllerProvider.notifier).submit();
  }
}

// ── Screen 1 — Welcome ──────────────────────────────────────────────────────

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(RegistrationSpacing.screenPadding),
      children: [
        const SizedBox(height: 12),
        const _HeroIllustration(),
        const SizedBox(height: 28),
        Text(
          appText(context).commonRegisterYourShop,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: RegistrationColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          appText(context).shopRegistrationWizardJoinOurPlatformAndBring,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.5,
            color: RegistrationColors.textSecondary,
          ),
        ),
        const SizedBox(height: 28),
        _BenefitCard(
          icon: Icons.visibility_outlined,
          title: appText(context).commonMoreVisibility,
          body: appText(context)
              .shopRegistrationWizardDiscoverabilityByNearbyCustomers,
        ),
        const SizedBox(height: 12),
        _BenefitCard(
          icon: Icons.dashboard_outlined,
          title: appText(context).commonEasyManagement,
          body: appText(context)
              .shopRegistrationWizardHandleProductsOrdersInventoryAnd,
        ),
        const SizedBox(height: 12),
        _BenefitCard(
          icon: Icons.verified_user_outlined,
          title: appText(context).commonSecureTrusted,
          body: appText(context)
              .shopRegistrationWizardVerifiedBusinessesCreateASafer,
        ),
        const SizedBox(height: 32),
        PrimaryButton(
          label: appText(context).commonGetStarted,
          icon: Icons.arrow_forward,
          onPressed: onGetStarted,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => context.go(Routes.login),
            child: Text(
              appText(context).shopRegistrationWizardAlreadyHaveAnAccountLogin,
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _HeroIllustration extends StatelessWidget {
  const _HeroIllustration();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Passly Biz logo + wordmark (single asset) with the illustrated hero
    // as a fallback if the asset is missing.
    return Image.asset(
      'assets/images/passly_biz_named.png',
      // Brand mark only — this step's own heading carries the meaning, so the
      // logo stays out of the screen-reader order instead of adding noise.
      excludeFromSemantics: true,
      height: 150,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Container(
        height: 150,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(RegistrationSpacing.cardRadius),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.storefront, size: 64, color: scheme.primary),
            Positioned(
              top: 18,
              right: 40,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: AppShadows.inkAmbient, blurRadius: 6),
                  ],
                ),
                child: Icon(Icons.location_on, size: 22, color: scheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(RegistrationSpacing.cardRadius),
        border: Border.all(color: RegistrationColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(
                RegistrationSpacing.fieldRadius,
              ),
            ),
            child: Icon(icon, size: 22, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: RegistrationColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: RegistrationColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Screen 2 — Business Information ──────────────────────────────────────────

class _BusinessInfoStep extends StatelessWidget {
  const _BusinessInfoStep({
    super.key,
    required this.state,
    required this.name,
    required this.gstin,
    required this.udyam,
    required this.onBack,
    required this.onNext,
  });

  final ShopRegistrationState state;
  final TextEditingController name;
  final TextEditingController gstin;
  final TextEditingController udyam;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final categoryError = state.attempted
        ? ShopRegistrationValidators.category(state.category)
        : null;
    final typeError = state.attempted
        ? ShopRegistrationValidators.businessType(state.businessType)
        : null;

    return Column(
      children: [
        const StepProgressIndicator(step: RegistrationStep.businessInfo),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(RegistrationSpacing.screenPadding),
            children: [
              RegisterStepHeader(
                title: appText(context).commonRegisterYourShop,
                subtitle: appText(context)
                    .shopRegistrationWizardTellUsAboutYourShop,
                onBack: onBack,
              ),
              const SizedBox(height: RegistrationSpacing.sectionGap),
              FormFieldCard(
                controller: name,
                label: appText(context).commonShopBusinessName2,
                placeholder: appText(context)
                    .shopRegistrationWizardEGSharmaMedicalStore,
                icon: Icons.store_outlined,
                textCapitalization: TextCapitalization.words,
                validator: ShopRegistrationValidators.shopName,
              ),
              const SizedBox(height: RegistrationSpacing.fieldGap),
              _CategoryField(state: state, error: categoryError),
              const SizedBox(height: RegistrationSpacing.fieldGap),
              _BusinessTypeField(state: state, error: typeError),
              const SizedBox(height: RegistrationSpacing.fieldGap),
              FormFieldCard(
                controller: gstin,
                label: appText(context).commonGSTINOptional,
                placeholder: appText(context).commonEnterGSTIN,
                icon: Icons.receipt_long_outlined,
                textCapitalization: TextCapitalization.characters,
                validator: ShopRegistrationValidators.gstin,
              ),
              const SizedBox(height: RegistrationSpacing.fieldGap),
              FormFieldCard(
                controller: udyam,
                label: appText(context)
                    .shopRegistrationWizardUdyamMSMENumberOptional,
                placeholder: appText(context).commonEnterUdyamNumber,
                icon: Icons.badge_outlined,
                textCapitalization: TextCapitalization.characters,
                validator: ShopRegistrationValidators.udyam,
              ),
              const SizedBox(height: RegistrationSpacing.sectionGap),
              PrimaryButton(
                label: appText(context).commonNext,
                icon: Icons.arrow_forward,
                onPressed: onNext,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryField extends StatelessWidget {
  const _CategoryField({required this.state, required this.error});

  final ShopRegistrationState state;
  final String? error;

  Future<void> _openPicker(BuildContext context) async {
    final controller = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(shopRegistrationControllerProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RegistrationSpacing.cardRadius),
        ),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                appText(context).commonSelectBusinessCategory,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            const Divider(height: 1),
            if (state.categoriesLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              )
            else
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: state.categories.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final option = state.categories[i];
                    final selected = state.category?.code == option.code;
                    return ListTile(
                      leading: Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: selected
                            ? Theme.of(ctx).colorScheme.primary
                            : RegistrationColors.textSecondary,
                      ),
                      title: Text(
                        option.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: option.description == null
                          ? null
                          : Text(
                              option.description!,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: RegistrationColors.textSecondary,
                              ),
                            ),
                      onTap: () {
                        controller.pickCategory(option);
                        Navigator.of(ctx).pop();
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = state.category;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Business Category',
          button: true,
          child: InkWell(
            onTap: state.categoriesLoading ? null : () => _openPicker(context),
            borderRadius: BorderRadius.circular(
              RegistrationSpacing.fieldRadius,
            ),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(
                minHeight: RegistrationSpacing.fieldHeight,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(
                  RegistrationSpacing.fieldRadius,
                ),
                border: Border.all(
                  color: error != null
                      ? scheme.error
                      : RegistrationColors.border,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.category_outlined,
                    size: 20,
                    color: RegistrationColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      selected?.name ?? 'Select business category',
                      style: TextStyle(
                        fontSize: 15,
                        color: selected == null
                            ? RegistrationColors.textSecondary
                            : RegistrationColors.textPrimary,
                      ),
                    ),
                  ),
                  if (state.categoriesLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(
                      Icons.expand_more,
                      size: 22,
                      color: RegistrationColors.textSecondary,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error!, style: TextStyle(fontSize: 12.5, color: scheme.error)),
        ],
      ],
    );
  }
}

class _BusinessTypeField extends StatelessWidget {
  const _BusinessTypeField({required this.state, required this.error});

  final ShopRegistrationState state;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropdownButtonFormField<String>(
      initialValue: state.businessType,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: appText(context).commonBusinessType2,
        prefixIcon: const Icon(Icons.business_center_outlined, size: 20),
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: RegistrationSpacing.fieldGap,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RegistrationSpacing.fieldRadius),
          borderSide: const BorderSide(color: RegistrationColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RegistrationSpacing.fieldRadius),
          borderSide: const BorderSide(color: RegistrationColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RegistrationSpacing.fieldRadius),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RegistrationSpacing.fieldRadius),
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
      ),
      items: [
        for (final type in kBusinessTypes)
          DropdownMenuItem(value: type, child: Text(type)),
      ],
      onChanged: (v) => ProviderScope.containerOf(
        context,
        listen: false,
      ).read(shopRegistrationControllerProvider.notifier).setBusinessType(v),
      validator: (v) => error,
    );
  }
}

// ── Screen 3 — Shop Location ─────────────────────────────────────────────────

class _LocationStep extends StatelessWidget {
  const _LocationStep({
    super.key,
    required this.state,
    required this.address,
    required this.city,
    required this.stateName,
    required this.pincode,
    required this.landmark,
    required this.onBack,
    required this.onNext,
  });

  final ShopRegistrationState state;
  final TextEditingController address;
  final TextEditingController city;
  final TextEditingController stateName;
  final TextEditingController pincode;
  final TextEditingController landmark;
  final VoidCallback onBack;
  final VoidCallback onNext;

  /// Whether the blue "my location" layer may be drawn: it needs the location
  /// grant, which manual mode exists precisely because it is missing.
  bool get _showsDeviceLocationLayer => switch (state.locationStatus) {
    RegistrationLocationStatus.locating ||
    RegistrationLocationStatus.adjustingAccuracy => true,
    RegistrationLocationStatus.ready => !state.locationManual,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StepProgressIndicator(step: RegistrationStep.location),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(RegistrationSpacing.screenPadding),
            children: [
              RegisterStepHeader(
                title: appText(context).commonShopLocation,
                subtitle: appText(context)
                    .shopRegistrationWizardAddYourShopLocationFor,
                onBack: onBack,
              ),
              const SizedBox(height: RegistrationSpacing.sectionGap),
              SizedBox(
                height: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    RegistrationSpacing.cardRadius,
                  ),
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: state.pin ?? const LatLng(25.5941, 85.1376),
                          zoom: state.pin == null ? 4 : 17,
                        ),
                        markers: state.pin == null
                            ? {}
                            : {
                                Marker(
                                  markerId: const MarkerId('shop_pin'),
                                  position: state.pin!,
                                  draggable: true,
                                  onDragEnd: (position) =>
                                      ProviderScope.containerOf(
                                            context,
                                            listen: false,
                                          )
                                          .read(
                                            shopRegistrationControllerProvider
                                                .notifier,
                                          )
                                          .movePin(position),
                                ),
                              },
                        onTap: (latLng) =>
                            ProviderScope.containerOf(context, listen: false)
                                .read(
                                  shopRegistrationControllerProvider.notifier,
                                )
                                .movePin(latLng),
                        // The blue-dot layer needs the location grant: on for a
                        // GPS-backed pin, off in manual mode (where the
                        // permission is exactly what is missing).
                        myLocationEnabled: _showsDeviceLocationLayer,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: RegistrationAccuracyChip(
                          accuracyMeters:
                              (state.pinAdjusted || state.locationManual)
                              ? null
                              : state.accuracyMeters,
                        ),
                      ),
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: FloatingActionButton.small(
                          heroTag: 'gps',
                          onPressed: () =>
                              ProviderScope.containerOf(context, listen: false)
                                  .read(
                                    shopRegistrationControllerProvider.notifier,
                                  )
                                  .acquireLocation(),
                          child: const Icon(Icons.my_location),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (state.locationManual) ...[
                const SizedBox(height: 8),
                Text(
                  appText(context).shopRegistrationWizardNoGPSFixTapThe,
                  style: TextStyle(
                    fontSize: 12,
                    color: RegistrationColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ShopLocationDetails(
                state: state,
                onAdjust: (position) =>
                    ProviderScope.containerOf(context, listen: false)
                        .read(shopRegistrationControllerProvider.notifier)
                        .movePin(position),
                onConfirmDrift: () =>
                    ProviderScope.containerOf(context, listen: false)
                        .read(shopRegistrationControllerProvider.notifier)
                        .confirmPinDrift(),
              ),
              const SizedBox(height: 12),
              _LocationActions(
                locationStatus: state.locationStatus,
                controllerState: state,
              ),
              const SizedBox(height: RegistrationSpacing.sectionGap),
              FormFieldCard(
                controller: address,
                label: appText(context).commonAddress,
                placeholder: appText(context).commonShopNoStreetArea,
                icon: Icons.home_outlined,
                validator: ShopRegistrationValidators.address,
              ),
              const SizedBox(height: RegistrationSpacing.fieldGap),
              Row(
                children: [
                  Expanded(
                    child: FormFieldCard(
                      controller: city,
                      label: appText(context).commonCity,
                      placeholder: appText(context).commonCity,
                      icon: Icons.location_city_outlined,
                      validator: ShopRegistrationValidators.city,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FormFieldCard(
                      controller: stateName,
                      label: appText(context).commonState,
                      placeholder: appText(context).commonState,
                      icon: Icons.map_outlined,
                      validator: ShopRegistrationValidators.stateName,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RegistrationSpacing.fieldGap),
              Row(
                children: [
                  Expanded(
                    child: FormFieldCard(
                      controller: pincode,
                      label: appText(context).commonPincode,
                      placeholder: appText(context).common6DigitPincode,
                      icon: Icons.pin_drop_outlined,
                      keyboardType: TextInputType.number,
                      // Indian pincodes are exactly six digits — letters and
                      // a seventh digit are blocked at the keystroke.
                      inputFormatters: NumericInput.whole(maxLength: 6),
                      maxLength: 6,
                      validator: ShopRegistrationValidators.pincode,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FormFieldCard(
                      controller: landmark,
                      label: appText(context).commonLandmarkOptional,
                      placeholder: appText(context).shopRegistrationWizardNear,
                      icon: Icons.near_me_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RegistrationSpacing.sectionGap),
              PrimaryButton(
                label: appText(context).commonNext,
                icon: Icons.arrow_forward,
                onPressed: onNext,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocationActions extends StatelessWidget {
  const _LocationActions({
    required this.locationStatus,
    required this.controllerState,
  });

  final RegistrationLocationStatus locationStatus;
  final ShopRegistrationState controllerState;

  @override
  Widget build(BuildContext context) {
    final notifier = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(shopRegistrationControllerProvider.notifier);
    if (locationStatus == RegistrationLocationStatus.requestingPermission ||
        locationStatus == RegistrationLocationStatus.locating ||
        locationStatus == RegistrationLocationStatus.adjustingAccuracy) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(appText(context).shopRegistrationWizardGettingLocation),
          ],
        ),
      );
    }
    if (locationStatus == RegistrationLocationStatus.permissionDenied ||
        locationStatus == RegistrationLocationStatus.permissionBlocked) {
      final blocked =
          locationStatus == RegistrationLocationStatus.permissionBlocked;
      return RegistrationErrorCard(
        key: const Key('registration_location_permission_card'),
        icon: Icons.lock_outline,
        message: blocked
            ? 'Location permission is blocked for this app. Allow it in your '
                  'phone settings, or place your shop pin on the map below.'
            : 'Permission denied. Allow location access, then retry, or select '
                  'your shop location on the map below.',
        // A blocked permission cannot be asked again — the system settings are
        // the only way back, so the primary action changes with the state.
        retryLabel: blocked ? 'Open System Settings' : 'Allow Location',
        onRetry: blocked
            ? () => notifier.openSystemSettings()
            : () => notifier.acquireLocation(),
        extraActions: [
          RegistrationErrorAction(
            key: const Key('registration_choose_on_map'),
            label: 'Choose Location on Map',
            onPressed: () {
              notifier.useManualLocation();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    appText(context).shopRegistrationWizardTapTheMapToPlace,
                  ),
                ),
              );
            },
          ),
          RegistrationErrorAction(
            key: const Key('registration_enter_address'),
            label: 'Enter Address Manually',
            onPressed: () {
              notifier.useManualLocation();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    appText(context)
                        .shopRegistrationWizardTypeYourAddressBelowThen,
                  ),
                ),
              );
            },
          ),
        ],
      );
    }
    if (locationStatus == RegistrationLocationStatus.serviceDisabled) {
      return RegistrationErrorCard(
        key: const Key('registration_location_services_card'),
        icon: Icons.location_off_outlined,
        message: 'Location services are turned off. Please enable GPS and try again.',
        // The permission is fine — only the device switch can be turned on.
        retryLabel: 'Turn On GPS',
        onRetry: () => notifier.openDeviceLocationSettings(),
        extraActions: [
          RegistrationErrorAction(
            key: const Key('registration_choose_on_map'),
            label: 'Choose Location on Map',
            onPressed: () {
              notifier.useManualLocation();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    appText(context).shopRegistrationWizardTapTheMapToPlace,
                  ),
                ),
              );
            },
          ),
          RegistrationErrorAction(
            key: const Key('registration_enter_address'),
            label: 'Enter Address Manually',
            onPressed: () {
              notifier.useManualLocation();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    appText(context)
                        .shopRegistrationWizardTypeYourAddressBelowThen,
                  ),
                ),
              );
            },
          ),
        ],
      );
    }
    if (locationStatus == RegistrationLocationStatus.error) {
      return RegistrationErrorCard(
        key: const Key('registration_location_error_card'),
        message:
            controllerState.locationError ?? 'Could not get your location.',
        onRetry: () => notifier.retryLocation(),
        extraActions: [
          RegistrationErrorAction(
            key: const Key('registration_choose_on_map'),
            label: 'Choose Location on Map',
            onPressed: () {
              notifier.useManualLocation();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    appText(context).shopRegistrationWizardTapTheMapToPlace,
                  ),
                ),
              );
            },
          ),
        ],
      );
    }
    if (controllerState.locationManual) {
      return PrimaryButton(
        key: const Key('registration_place_pin_on_map'),
        label: controllerState.pin == null
            ? 'Place Pin on the Map'
            : 'Confirm Location and Continue',
        icon: controllerState.pin == null ? Icons.map_outlined : Icons.check,
        loading: controllerState.reverseGeocoding,
        loadingLabel: 'Detecting address…',
        onPressed: () async {
          if (controllerState.pin == null) {
            // Manual mode: GPS is unavailable by choice, so never re-run the
            // permission flow behind the shopkeeper's back.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  appText(context).shopRegistrationWizardTapTheMapToPlace,
                ),
              ),
            );
            return;
          }
          await notifier.confirmPinAndReverseGeocode();
        },
      );
    }
    return PrimaryButton(
      label: controllerState.pin == null
          ? 'Get Current Location'
          : 'Confirm Location and Continue',
      icon: Icons.my_location,
      loading: controllerState.reverseGeocoding,
      loadingLabel: 'Detecting address…',
      onPressed: () async {
        if (controllerState.pin == null) {
          await notifier.acquireLocation();
        } else {
          await notifier.confirmPinAndReverseGeocode();
        }
      },
    );
  }
}

// ---- Screen 4 -- Documents and Additional Information ----

class _DocumentsStep extends StatefulWidget {
  const _DocumentsStep({
    super.key,
    required this.state,
    required this.description,
    required this.website,
    required this.social,
    required this.onBack,
    required this.onNext,
  });

  final ShopRegistrationState state;
  final TextEditingController description;
  final TextEditingController website;
  final TextEditingController social;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  State<_DocumentsStep> createState() => _DocumentsStepState();
}

class _DocumentsStepState extends State<_DocumentsStep> {
  Future<PickedFile?> _pick(PickSource source, DocumentSlot slot) {
    final picker = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(documentPickerProvider);
    return picker.pick(
      source: source,
      mediaCategory: slot.requirement.mediaCategory,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return Column(
      children: [
        const StepProgressIndicator(step: RegistrationStep.documents),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(RegistrationSpacing.screenPadding),
            children: [
              RegisterStepHeader(
                title: appText(context)
                    .shopRegistrationWizardDocumentsAndAdditionalInfo,
                subtitle: appText(
                  context,
                ).shopRegistrationWizardUploadRequiredDocumentsForVerification,
                onBack: widget.onBack,
              ),
              const SizedBox(height: RegistrationSpacing.sectionGap),
              if (state.submitError != null) ...[
                RegistrationErrorCard(
                  message: state.submitError!,
                  onRetry: () {
                    ProviderScope.containerOf(context, listen: false)
                        .read(shopRegistrationControllerProvider.notifier)
                        .clearSubmitError();
                    widget.onNext();
                  },
                ),
                const SizedBox(height: 12),
              ],
              if (state.requirementsLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                for (final slot in state.slotList) ...[
                  DocumentUploadCard(
                    key: ValueKey(slot.requirement.key),
                    slot: slot,
                    onPick: (source) =>
                        ProviderScope.containerOf(context, listen: false)
                            .read(shopRegistrationControllerProvider.notifier)
                            .pickDocument(
                              slot.requirement.key,
                              source,
                              (s) => _pick(s, slot),
                            ),
                    onRemove: () =>
                        ProviderScope.containerOf(context, listen: false)
                            .read(shopRegistrationControllerProvider.notifier)
                            .removeDocument(slot.requirement.key),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              const SizedBox(height: 8),
              const SectionHeader(title: 'Additional Information'),
              const SizedBox(height: 12),
              FormFieldCard(
                controller: widget.description,
                label: appText(context).commonBusinessDescription,
                placeholder: appText(context)
                    .shopRegistrationWizardTellCustomersAboutYourShop,
                icon: Icons.description_outlined,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: RegistrationSpacing.fieldGap),
              Row(
                children: [
                  Expanded(
                    child: _TimeField(
                      label: appText(context).commonOpeningTime,
                      initial: state.openTime,
                      onPicked: (v) =>
                          ProviderScope.containerOf(context, listen: false)
                              .read(shopRegistrationControllerProvider.notifier)
                              .setOpenTime(v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimeField(
                      label: appText(context).commonClosingTime,
                      initial: state.closeTime,
                      onPicked: (v) =>
                          ProviderScope.containerOf(context, listen: false)
                              .read(shopRegistrationControllerProvider.notifier)
                              .setCloseTime(v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RegistrationSpacing.fieldGap),
              FormFieldCard(
                controller: widget.website,
                label: appText(context).commonWebsiteOptional,
                placeholder: appText(context).shopRegistrationWizardHttps,
                icon: Icons.public,
              ),
              const SizedBox(height: RegistrationSpacing.fieldGap),
              FormFieldCard(
                controller: widget.social,
                label: appText(context).commonSocialMediaOptional,
                placeholder: appText(context)
                    .shopRegistrationWizardInstagramFacebookLink,
                icon: Icons.alternate_email,
              ),
              const SizedBox(height: RegistrationSpacing.sectionGap),
              PrimaryButton(
                label: appText(context).commonReviewDetails,
                icon: Icons.visibility_outlined,
                onPressed: widget.onNext,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.initial,
    required this.onPicked,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onPicked;

  static String _format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay _parse(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 9;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return TimeOfDay(
      hour: h.clamp(0, 23).toInt(),
      minute: m.clamp(0, 59).toInt(),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parse(initial),
      helpText: label,
    );
    if (picked != null) onPicked(_format(picked));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: () => _pick(context),
        borderRadius: BorderRadius.circular(RegistrationSpacing.fieldRadius),
        child: Container(
          height: RegistrationSpacing.fieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(
              RegistrationSpacing.fieldRadius,
            ),
            border: Border.all(color: RegistrationColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.schedule,
                size: 20,
                color: RegistrationColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: RegistrationColors.textSecondary,
                      ),
                    ),
                    Text(
                      initial,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.expand_more,
                size: 20,
                color: RegistrationColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Screen 4b -- Shop Details Review ----

/// Final review before submission: every entered detail, grouped, with
/// per-section "Edit" jumps back into the pipeline. Submission happens ONLY
/// from here — the documents step forwards to this screen instead.
class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    super.key,
    required this.state,
    required this.onBack,
    required this.onEditBusiness,
    required this.onEditLocation,
    required this.onEditDocuments,
    required this.onSubmit,
    required this.onDismissError,
  });

  final ShopRegistrationState state;
  final VoidCallback onBack;
  final VoidCallback onEditBusiness;
  final VoidCallback onEditLocation;
  final VoidCallback onEditDocuments;
  final VoidCallback onSubmit;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final submitting = state.isSubmitting;
    final category = state.category;
    final pin = state.pin;

    String orDash(String? v) =>
        (v == null || v.trim().isEmpty) ? '—' : v.trim();

    return ListView(
      padding: const EdgeInsets.all(RegistrationSpacing.screenPadding),
      children: [
        Row(
          children: [
            IconButton(
              // Accessible name for the icon-only back control.
              tooltip: appText(context).commonBack5,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                appText(context).commonReviewYourDetails,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: RegistrationSpacing.sectionGap),
        _ReviewSection(
          title: appText(context).commonBusinessInformation,
          onEdit: onEditBusiness,
          rows: [
            ('Shop name', orDash(state.shopName)),
            ('Category', category?.name ?? '—'),
            ('Business type', orDash(state.businessType)),
            ('GSTIN', orDash(state.gstin)),
            ('Udyam', orDash(state.udyam)),
          ],
        ),
        const SizedBox(height: RegistrationSpacing.sectionGap),
        _ReviewSection(
          title: appText(context).commonLocation,
          onEdit: onEditLocation,
          rows: [
            ('Address', orDash(state.addressLine)),
            ('City', orDash(state.city)),
            ('State', orDash(state.stateName)),
            ('Pincode', orDash(state.pincode)),
            ('Landmark', orDash(state.landmark)),
            (
              'Map pin',
              pin == null
                  ? 'Not placed — required'
                  : 'Lat ${pin.latitude.toStringAsFixed(5)}, '
                        'Lng ${pin.longitude.toStringAsFixed(5)}',
            ),
          ],
        ),
        const SizedBox(height: RegistrationSpacing.sectionGap),
        _ReviewSection(
          title: appText(context).commonAdditionalInformation,
          onEdit: onEditDocuments,
          rows: [
            ('Description', orDash(state.description)),
            (
              'Open hours',
              '${orDash(state.openTime)} – ${orDash(state.closeTime)}',
            ),
            ('Website', orDash(state.website)),
            ('Social media', orDash(state.socialMedia)),
          ],
        ),
        const SizedBox(height: RegistrationSpacing.sectionGap),
        _ReviewDocuments(state: state),
        const SizedBox(height: RegistrationSpacing.sectionGap),
        if (state.submitError != null) ...[
          Card(
            color: scheme.errorContainer,
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.error_outline, color: scheme.error),
              title: Text(
                state.submitError!,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
              trailing: IconButton(
                // Accessible name for the icon-only dismiss control.
                tooltip: appText(context).commonDismiss,
                icon: const Icon(Icons.close),
                onPressed: onDismissError,
              ),
            ),
          ),
          const SizedBox(height: RegistrationSpacing.fieldGap),
        ],
        PrimaryButton(
          label: appText(context).commonSubmitRegistration,
          icon: Icons.check_circle_outline,
          loading: submitting,
          loadingLabel: switch (state.submitPhase) {
            SubmitPhase.uploadingDocuments => 'Uploading documents …',
            SubmitPhase.creatingShop => 'Submitting registration …',
            SubmitPhase.savingHours => 'Saving hours …',
            SubmitPhase.attachingDocuments => 'Attaching documents …',
            _ => 'Please wait …',
          },
          onPressed: submitting ? null : onSubmit,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// One grouped card of the review: title + per-row Edit affordance.
class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.title,
    required this.rows,
    required this.onEdit,
  });

  final String title;
  final List<(String, String)> rows;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(appText(context).commonEdit),
                ),
              ],
            ),
          ),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Documents summary: each requirement with its picked/uploaded state.
class _ReviewDocuments extends StatelessWidget {
  const _ReviewDocuments({required this.state});

  final ShopRegistrationState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    appText(context).commonDocuments,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    final container = ProviderScope.containerOf(
                      context,
                      listen: false,
                    );
                    container
                        .read(shopRegistrationControllerProvider.notifier)
                        .editDocuments();
                  },
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(appText(context).commonEdit),
                ),
              ],
            ),
          ),
          for (final slot in state.slotList)
            ListTile(
              dense: true,
              leading: Icon(
                slot.isUploaded
                    ? Icons.check_circle
                    : (slot.hasFile
                          ? Icons.description
                          : Icons.radio_button_off),
                size: 20,
                color: slot.isUploaded
                    ? AppColors.success
                    : scheme.onSurfaceVariant,
              ),
              title: Text(
                slot.requirement.label,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: slot.pickedName != null
                  ? Text(
                      slot.pickedName!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    )
                  : null,
              trailing: Text(
                slot.isUploaded
                    ? 'Uploaded'
                    : (slot.hasFile ? 'Selected' : 'Not provided'),
                style: TextStyle(
                  fontSize: 12,
                  color: slot.isUploaded
                      ? AppColors.success
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---- Screen 5 -- Registration Submitted / Success ----

class _SuccessStep extends StatelessWidget {
  const _SuccessStep({
    super.key,
    required this.state,
    this.showPhoneOtpStep = false,
  });

  final ShopRegistrationState state;

  /// Whether the "OTP Verification" timeline row is built at all.
  ///
  /// FALSE in the MVP: phone OTP is FUTURE scope (`kEnabledAuthMethods` holds
  /// Google only), and the auth override forbids placing OTP in the CURRENT
  /// visible flow. The row comes back by itself when the method is re-enabled —
  /// there is no second switch to remember.
  final bool showPhoneOtpStep;

  @override
  Widget build(BuildContext context) {
    final requirements = state.requirements;
    return ListView(
      padding: const EdgeInsets.all(RegistrationSpacing.screenPadding),
      children: [
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              color: RegistrationColors.successSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              size: 48,
              color: RegistrationColors.success,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          appText(context).commonRegistrationSubmitted,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: RegistrationColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          appText(context).shopRegistrationWizardYourShopRegistrationHasBeen,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.5,
            color: RegistrationColors.textSecondary,
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader(title: 'Verification Timeline'),
        const SizedBox(height: 12),
        if (showPhoneOtpStep)
          _TimelineItem(
            icon: Icons.phone_android_outlined,
            title: appText(context).commonOTPVerification,
            done: requirements?.phoneOtpRequired ?? true,
          ),
        _TimelineItem(
          icon: Icons.description_outlined,
          title: appText(context).commonDocumentVerification,
          done: true,
        ),
        if (requirements?.requiresBankVerification ?? true)
          _TimelineItem(
            icon: Icons.account_balance_outlined,
            title: appText(context).commonBankVerification,
            done: false,
          ),
        _TimelineItem(
          icon: Icons.approval_outlined,
          title: appText(context).commonApproval,
          done: false,
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: RegistrationColors.successSoft,
            borderRadius: BorderRadius.circular(
              RegistrationSpacing.fieldRadius,
            ),
          ),
          child: Text(
            appText(context).shopRegistrationWizardYouWillGetANotification,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: RegistrationColors.success,
            ),
          ),
        ),
        const SizedBox(height: 28),
        PrimaryButton(
          label: appText(context).commonGoToDashboard,
          icon: Icons.dashboard_outlined,
          onPressed: () => context.go(Routes.dashboard),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            // `'/'` is not a registered route (go_router has no home at the
            // root), so this button used to do nothing at all. Send the
            // shopkeeper to the real Home route instead.
            onPressed: () => context.go(Routes.dashboard),
            child: Text(appText(context).commonBackToHome),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.icon,
    required this.title,
    required this.done,
  });

  final IconData icon;
  final String title;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 22,
            color: done
                ? RegistrationColors.success
                : RegistrationColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: done
                  ? RegistrationColors.textPrimary
                  : RegistrationColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
