import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/token_store.dart';
import '../../auth/presentation/controllers/selected_shop.dart';
import '../../media/data/media_repository.dart';
import '../../shops/data/shop_repository.dart';
import '../../shops/domain/location_capture_state.dart';
import '../../shops/domain/shop_models.dart';
import '../../shops/presentation/controllers/location_capture_controller.dart';
import '../../shops/presentation/controllers/shops_controller.dart';
import '../data/document_picker_service.dart';
import '../domain/shop_registration_state.dart';

/// Drives the whole "Register Your Shop" wizard.
///
/// The UI never talks to the network/location/picker layers directly: it
/// renders [ShopRegistrationState] and forwards events here. Location
/// acquisition is delegated to the EXISTING [locationCaptureControllerProvider]
/// (multi-reading GPS, accuracy tiers, drift confirmation, reverse geocoding)
/// — never re-implemented.
class ShopRegistrationController
    extends Notifier<ShopRegistrationState> {
  @override
  ShopRegistrationState build() {
    // Keep the wizard view-model in sync with the existing capture state
    // machine (drift, accuracy, pin) so the UI has ONE render source.
    ref.listen(locationCaptureControllerProvider, (_, next) {
      _syncLocationIntoWizard();
    });
    Future.microtask(loadCategories);
    return const ShopRegistrationState();
  }

  ShopRepository get _repo => ref.read(shopRepositoryProvider);
  MediaRepository get _media => ref.read(mediaRepositoryProvider);

  Future<String?> _token() =>
      ref.read(tokenStoreProvider).readAccessToken();

  // ── Categories & backend-driven requirements ────────────────────────────

  Future<void> loadCategories() async {
    state = state.copyWith(categoriesLoading: true, clearCategoriesError: true);
    try {
      final token = await _token();
      if (token == null) {
        throw const ApiException(message: 'Not signed in');
      }
      final categories = await _repo.listMerchantCategories(token);
      state = state.copyWith(
        categories: categories,
        categoriesLoading: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        categoriesLoading: false,
        categoriesError: _friendly(e, fallback: 'Could not load categories'),
      );
    } catch (_) {
      state = state.copyWith(
        categoriesLoading: false,
        categoriesError: 'Could not load categories',
      );
    }
  }

  /// Selecting a category immediately pulls its requirement contract from the
  /// backend (documents + verification steps) and rebuilds the document slots
  /// — category rules NEVER live in the UI.
  Future<void> selectCategory(MerchantCategoryOption option) async {
    state = state.copyWith(
      category: option,
      clearCategory: false,
      requirementsLoading: true,
      clearRequirementsError: true,
      attempted: false,
    );
    try {
      final token = await _token();
      if (token == null) {
        throw const ApiException(message: 'Not signed in');
      }
      final requirements = await _repo.getCategoryRequirements(
          token, option.code);
      state = state.copyWith(
        requirements: requirements,
        requirementsLoading: false,
        slots: _buildSlots(requirements),
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        requirementsLoading: false,
        requirementsError: _friendly(e,
            fallback: 'Could not load requirements for this category'),
      );
    } catch (_) {
      state = state.copyWith(
        requirementsLoading: false,
        requirementsError:
            'Could not load requirements for this category',
      );
    }
  }

  void retryRequirements() {
    final category = state.category;
    if (category != null) selectCategory(category);
  }

  /// Universal documents first, then the category-specific ones returned by
  /// the backend requirements API (e.g. Drug License, FSSAI, Driving License).
  Map<String, DocumentSlot> _buildSlots(CategoryRequirements? requirements) {
    final slots = <String, DocumentSlot>{};
    for (final requirement in kUniversalDocuments) {
      slots[requirement.key] = DocumentSlot(requirement: requirement);
    }
    for (final requirement in requirements?.documents ?? const []) {
      slots[requirement.key] = DocumentSlot(requirement: requirement);
    }
    return slots;
  }

  // ── Field setters (preserve entered data when navigating back) ──────────

  void setShopName(String v) => state = state.copyWith(shopName: v.trim());
  void setGstin(String v) => state = state.copyWith(gstin: v.toUpperCase());
  void setUdyam(String v) => state = state.copyWith(udyam: v.toUpperCase());
  void setBusinessType(String? v) => state = state.copyWith(businessType: v);
  void setAddressLine(String v) => state = state.copyWith(addressLine: v);
  void setCity(String v) => state = state.copyWith(city: v);
  void setStateName(String v) => state = state.copyWith(stateName: v);
  void setPincode(String v) => state = state.copyWith(pincode: v);
  void setLandmark(String v) => state = state.copyWith(landmark: v);
  void setDescription(String v) => state = state.copyWith(description: v);
  void setWebsite(String v) => state = state.copyWith(website: v.trim());
  void setSocialMedia(String v) =>
      state = state.copyWith(socialMedia: v.trim());

  /// Operating hours (HH:MM 24h) — persisted via PUT /shops/{id}/hours.
  void setOpenTime(String v) => state = state.copyWith(openTime: v);
  void setCloseTime(String v) => state = state.copyWith(closeTime: v);

  /// Category picker: selection happens in the bottom sheet; this applies it.
  void pickCategory(MerchantCategoryOption option) {
    if (state.category?.code == option.code) return;
    selectCategory(option);
  }

  // ── Step navigation with per-step local validation ───────────────────────

  /// Screen 1 → 2.
  void startBusinessInfo() =>
      state = state.copyWith(step: RegistrationStep.businessInfo);

  /// 2 → 3 (validates business information).
  String? nextFromBusinessInfo() {
    state = state.copyWith(attempted: true);
    final categoryError = ShopRegistrationValidators.category(state.category);
    if (categoryError != null) return categoryError;
    final typeError =
        ShopRegistrationValidators.businessType(state.businessType);
    if (typeError != null) return typeError;
    final gstinError = ShopRegistrationValidators.gstin(state.gstin);
    if (gstinError != null) return gstinError;
    final udyamError = ShopRegistrationValidators.udyam(state.udyam);
    if (udyamError != null) return udyamError;
    state = state.copyWith(
      step: RegistrationStep.location,
      attempted: false,
    );
    return null;
  }

  /// 3 → 4 (validates location + address fields).
  String? nextFromLocation() {
    state = state.copyWith(attempted: true);
    final pin = state.pin;
    if (pin == null ||
        !ShopRegistrationValidators.validLatitude(pin.latitude) ||
        !ShopRegistrationValidators.validLongitude(pin.longitude)) {
      return 'Get your current location or confirm the map pin first';
    }
    final addressError = ShopRegistrationValidators.address(state.addressLine);
    if (addressError != null) return addressError;
    final cityError = ShopRegistrationValidators.city(state.city);
    if (cityError != null) return cityError;
    final stateError = ShopRegistrationValidators.stateName(state.stateName);
    if (stateError != null) return stateError;
    final pincodeError = ShopRegistrationValidators.pincode(state.pincode);
    if (pincodeError != null) return pincodeError;
    // A pin moved far from the GPS fix must be explicitly confirmed first.
    if (state.needsPinDriftConfirmation) {
      return 'This pin is far from your GPS location. '
          'Confirm it is your shop entrance to continue.';
    }
    state = state.copyWith(
      step: RegistrationStep.documents,
      attempted: false,
    );
    return null;
  }

  /// Any step back to the previous one (entered data is preserved in state).
  void back() {
    switch (state.step) {
      case RegistrationStep.businessInfo:
        state = state.copyWith(step: RegistrationStep.welcome);
      case RegistrationStep.location:
        state = state.copyWith(step: RegistrationStep.businessInfo);
      case RegistrationStep.documents:
        state = state.copyWith(step: RegistrationStep.location);
      case RegistrationStep.review:
        state = state.copyWith(step: RegistrationStep.documents);
      case RegistrationStep.welcome || RegistrationStep.success:
        break;
    }
  }

  /// 4 → 5 (documents → review). Documents are the last optional inputs;
  /// the final review shows every entered detail before submission.
  void nextFromDocuments() {
    state = state.copyWith(step: RegistrationStep.review);
  }

  /// Review step "Edit" affordances — jump back to a specific step. All
  /// entered data is preserved in state; the user re-enters the pipeline
  /// through the normal Next buttons (→ review again before submit).
  void editBusinessInfo() {
    state = state.copyWith(step: RegistrationStep.businessInfo);
  }

  void editLocation() {
    state = state.copyWith(step: RegistrationStep.location);
  }

  void editDocuments() {
    state = state.copyWith(step: RegistrationStep.documents);
  }

  // ── Location (delegates to the EXISTING capture controller) ─────────────

  /// EXISTING location state machine (GPS multi-reading, drift, geocoding).
  LocationCaptureState get _locationState =>
      ref.read(locationCaptureControllerProvider);

  LocationCaptureController get _location =>
      ref.read(locationCaptureControllerProvider.notifier);

  /// "Get Current Location" — permission handling, multi-reading acquisition
  /// and progressive accuracy all live in the existing capture controller.
  Future<void> acquireLocation() async {
    state = state.copyWith(clearLocationError: true);
    await _location.startCapture();
    await _syncLocationIntoWizard();
  }

  /// Retry after a failed acquisition — re-runs the full pre-flight so a
  /// revoked permission or a disabled GPS service is reported honestly.
  Future<void> retryLocation() => acquireLocation();

  /// Manual pin adjustment (map tap, marker drag or manual coordinates).
  /// The wizard pin updates immediately so the map, the coordinate fields and
  /// the confirmation card can never disagree.
  void movePin(LatLng position) {
    _location.moveShopPin(position);
    state = state.copyWith(
      pin: position,
      pinAdjusted: true,
      // No GPS reading behind the pin → this is a MANUAL capture, and the
      // payload must say so instead of claiming a fix.
      locationManual: state.reading == null || state.locationManual,
      locationStatus: RegistrationLocationStatus.ready,
      clearLocationError: true,
    );
  }

  /// "Choose Location on Map" / "Enter Address Manually" — both dismiss the
  /// permission + GPS prompts so the step can be completed without them: the
  /// pin comes from the map, the address from the fields below it.
  ///
  /// Nothing is inferred: the capture stays flagged as MANUAL.
  void useManualLocation() {
    _location.startMapOnlyCapture();
    state = state.copyWith(
      locationManual: true,
      locationStatus: RegistrationLocationStatus.ready,
      clearLocationError: true,
    );
  }

  /// Opens this app's page in the system settings — the only way back from a
  /// permanently denied location permission.
  Future<bool> openSystemSettings() => _location.openSystemSettings();

  /// Opens the device location-services page — the way back from "GPS is off".
  Future<bool> openDeviceLocationSettings() =>
      _location.openDeviceLocationSettings();

  /// Re-confirms after the shopkeeper moved the pin far from the GPS fix.
  void confirmPinDrift() {
    _location.confirmPinDrift();
    state = state.copyWith(pinDriftConfirmed: true);
  }

  /// Reverse-geocode AFTER the final pin selection, then prefill the address
  /// fields. Editing the address text never moves the pin.
  Future<void> confirmPinAndReverseGeocode() async {
    state = state.copyWith(reverseGeocoding: true);
    await _location.confirmLocation();
    await _syncLocationIntoWizard(prefillAddress: true);
    state = state.copyWith(reverseGeocoding: false);
  }

  /// Copies the capture controller's coordinates + detected address into the
  /// wizard state so the wizard owns one render source for the UI.
  Future<void> _syncLocationIntoWizard({bool prefillAddress = false}) async {
    final capture = _locationState;
    final detected = capture.address;
    state = state.copyWith(
      pin: capture.shopPin,
      reading: capture.deviceReading,
      accuracyMeters: capture.accuracyMeters,
      pinAdjusted: capture.pinIsAdjusted,
      pinDriftMeters: capture.pinDriftMeters,
      pinDriftConfirmed: capture.pinDriftConfirmed,
      detectedAddress: detected,
      locationError: capture.status == LocationCaptureStatus.error
          ? (capture.errorMessage ?? 'Could not get your location')
          : (capture.status == LocationCaptureStatus.locationPermissionDenied
              ? (capture.permissionBlocked
                  ? 'Location permission is blocked for this app. '
                      'Allow it in your phone settings, or place the pin on '
                      'the map.'
                  : 'Location permission is needed to verify your shop.')
              : (capture.status ==
                      LocationCaptureStatus.locationServiceDisabled
                  ? 'Location services are turned off. Please enable GPS and try again.'
                  : null)),
      locationStatus: switch (capture.status) {
        LocationCaptureStatus.initial ||
        LocationCaptureStatus.requestingPermission =>
          RegistrationLocationStatus.requestingPermission,
        LocationCaptureStatus.fetchingLocation ||
        LocationCaptureStatus.improvingAccuracy =>
          RegistrationLocationStatus.locating,
        LocationCaptureStatus.locationReady ||
        LocationCaptureStatus.locationPoorAccuracy ||
        LocationCaptureStatus.reverseGeocoding ||
        LocationCaptureStatus.readyForConfirmation ||
        LocationCaptureStatus.saving ||
        LocationCaptureStatus.success =>
          RegistrationLocationStatus.ready,
        LocationCaptureStatus.locationPermissionDenied =>
          capture.permissionBlocked
              ? RegistrationLocationStatus.permissionBlocked
              : RegistrationLocationStatus.permissionDenied,
        LocationCaptureStatus.locationServiceDisabled =>
          RegistrationLocationStatus.serviceDisabled,
        LocationCaptureStatus.error => RegistrationLocationStatus.error,
      },
    );
    if (prefillAddress) {
      // Prefill ONLY empty fields — never overwrite what the shopkeeper typed.
      state = state.copyWith(
        addressLine: state.addressLine.isEmpty
            ? (detected?.addressLine ?? '')
            : state.addressLine,
        city: state.city.isEmpty ? (detected?.city ?? '') : state.city,
        stateName: state.stateName.isEmpty
            ? (detected?.state ?? '')
            : state.stateName,
        pincode:
            state.pincode.isEmpty ? (detected?.pincode ?? '') : state.pincode,
      );
    }
  }

  /// GPS drift warning threshold (mirrors the existing capture flow).
  bool get needsDriftConfirmation => state.needsPinDriftConfirmation;

  // ── Documents ────────────────────────────────────────────────────────────

  void _setSlot(String key, DocumentSlot slot) {
    state = state.copyWith(slots: {...state.slots, key: slot});
  }

  /// Pick a file for a slot. Shows a Camera/Gallery/Files bottom sheet (for
  /// photos) and preflights extension/MIME/size BEFORE any network work.
  Future<void> pickDocument(
    String key,
    PickSource source,
    Future<PickedFile?> Function(PickSource source) picker,
  ) async {
    final slot = state.slots[key];
    if (slot == null || slot.isBusy) return;
    final picked = await picker(source);
    if (picked == null) return;
    final error = DocumentPreflight.validate(
        picked, slot.requirement.mediaCategory);
    if (error != null) {
      _setSlot(key, slot.copyWith(
        status: DocumentUploadStatus.error,
        error: error,
      ));
      return;
    }
    // Files upload during submit (after the shop exists and can own them).
    _setSlot(key, slot.copyWith(
      status: DocumentUploadStatus.idle,
      pickedName: picked.name,
      pickedPath: picked.path,
      pickedSizeBytes: picked.sizeBytes,
      clearObjectKey: true,
      clearError: true,
    ));
  }

  void replaceDocument(
    String key,
    Future<PickedFile?> Function(PickSource source) picker,
  ) => pickDocument(key, PickSource.files, picker);

  void removeDocument(String key) {
    final slot = state.slots[key];
    if (slot == null) return;
    _setSlot(key, slot.copyWith(
      clearFile: true,
      status: DocumentUploadStatus.idle,
      clearObjectKey: true,
      clearError: true,
    ));
  }

  // ── Submit (create shop → upload → hours → attach) ───────────────────────

  void clearSubmitError() =>
      state = state.copyWith(clearSubmitError: true, clearSubmitErrorCode: true);

  /// Full registration pipeline. Returns the created shop id on success
  /// (used by the UI to navigate to the dashboard), null on failure
  /// ([state.submitError] explains what happened). Guards against duplicate
  /// submission — the CTA is disabled while [state.isSubmitting].
  Future<int?> submit() async {
    if (state.isSubmitting) return null;

    // Local validation — the backend validates everything again.
    final pin = state.pin;
    if (pin == null ||
        !ShopRegistrationValidators.validLatitude(pin.latitude) ||
        !ShopRegistrationValidators.validLongitude(pin.longitude)) {
      state = state.copyWith(
        attempted: true,
        submitError: 'Confirm your shop location on the map first.',
      );
      return null;
    }
    if (ShopRegistrationValidators.shopName(state.shopName) != null ||
        ShopRegistrationValidators.category(state.category) != null ||
        ShopRegistrationValidators.address(state.addressLine) != null ||
        ShopRegistrationValidators.city(state.city) != null ||
        ShopRegistrationValidators.stateName(state.stateName) != null ||
        ShopRegistrationValidators.pincode(state.pincode) != null) {
      state = state.copyWith(
        attempted: true,
        submitError: 'Some required details are missing or invalid.',
      );
      return null;
    }

    final token = await _token();
    if (token == null) {
      state = state.copyWith(
        submitError: 'Your session has expired. Please sign in again.',
        submitErrorCode: 'SESSION_EXPIRED',
      );
      return null;
    }

    try {
      // 1) Create the shop (caller becomes its primary owner; category-driven
      //    onboarding is bound on the backend).
      state = state.copyWith(submitPhase: SubmitPhase.creatingShop);
      final detail = await _repo.registerShop(_registrationPayload(pin), token);
      final shopId = detail.summary.id;

      // 2) Upload picked documents (presigned policy; AWS credentials never
      //    reach the client) and 3) attach each as a verification document.
      await _uploadAndAttachDocuments(shopId, token);

      // 4) Persist the operating hours chosen on the Documents step.
      state = state.copyWith(submitPhase: SubmitPhase.savingHours);
      try {
        await _repo.updateOperatingHours(
          shopId: shopId,
          openTime: state.openTime,
          closeTime: state.closeTime,
          token: token,
        );
      } on ApiException catch (e) {
        // Hours are cosmetic defaults — registration never blocks on them.
        debugPrint('Hours save failed: ${e.message}');
      }

      // 5) Refresh the authorized-shops list from source of truth and select
      //    the new business so the dashboard renders it.
      state = state.copyWith(submitPhase: SubmitPhase.done);
      final refreshed = await ref.read(shopRepositoryProvider).listMyShops(token);
      final created = refreshed.where((s) => s.id == shopId).toList();
      ref.read(selectedShopProvider.notifier).select(
            created.isNotEmpty ? created.first : detail.summary,
          );
      unawaited(ref.read(shopsControllerProvider.notifier).load());

      state = state.copyWith(step: RegistrationStep.success);
      return shopId;
    } on ApiException catch (e) {
      state = state.copyWith(
        submitPhase: SubmitPhase.idle,
        submitError: _friendly(e, fallback: 'Shop registration failed'),
        submitErrorCode: e.errorCode,
      );
      return null;
    } catch (_) {
      state = state.copyWith(
        submitPhase: SubmitPhase.idle,
        submitError: 'Shop registration failed. Please retry.',
        submitErrorCode: 'NETWORK',
      );
      return null;
    }
  }

  /// Upload every picked slot then attach the confirmed objects. A failed
  /// upload marks ONLY that slot — other documents still attach.
  Future<void> _uploadAndAttachDocuments(int shopId, String token) async {
    final withFiles = state.slotList.where((s) => s.hasFile).toList();
    if (withFiles.isEmpty) return;

    state = state.copyWith(submitPhase: SubmitPhase.uploadingDocuments);
    for (final slot in withFiles) {
      final key = slot.requirement.key;
      _setSlot(key, slot.copyWith(status: DocumentUploadStatus.uploading));
      try {
        final path = slot.pickedPath!;
        final ext = path.split(Platform.pathSeparator).last
            .split('.').last.toLowerCase();
        final object = await _media.upload(
          category: DocumentPreflight.mediaCategory(
              slot.requirement.mediaCategory),
          filePath: path,
          contentType: DocumentPreflight.mimeForExtension(ext),
          shopId: shopId,
        );
        _setSlot(key, slot.copyWith(
          status: DocumentUploadStatus.uploaded,
          objectKey: object.key,
        ));
      } on ApiException catch (e) {
        _setSlot(key, slot.copyWith(
          status: DocumentUploadStatus.error,
          error: _friendly(e, fallback: 'Upload failed'),
        ));
      }
    }

    state = state.copyWith(submitPhase: SubmitPhase.attachingDocuments);
    for (final slot in state.slotList.where((s) => s.isUploaded)) {
      try {
        await _repo.addShopDocument(
          shopId: shopId,
          documentType: slot.requirement.key,
          documentUrl: slot.objectKey!,
          token: token,
        );
      } on ApiException catch (e) {
        // Attachment failure is non-blocking: the object is safely in S3 and
        // the shop exists; document_type can be re-attached from the profile.
        debugPrint(
            'Document attach failed (${slot.requirement.key}): ${e.message}');
      }
    }
  }

  Map<String, dynamic> _registrationPayload(LatLng pin) {
    final location = _locationState;
    final reading = location.deviceReading;
    return {
      'name': state.shopName.trim(),
      // Approved merchant category code — the backend maps it onto the legacy
      // shop category AND binds the matching onboarding record.
      'category': state.category!.code,
      'gstin': state.gstin.trim().isEmpty
          ? null
          : state.gstin.trim().toUpperCase(),
      'latitude': pin.latitude,
      'longitude': pin.longitude,
      'address': {
        'address_line1': state.addressLine.trim(),
        'address_line2': state.landmark.trim().isEmpty
            ? null
            : state.landmark.trim(),
        'landmark':
            state.landmark.trim().isEmpty ? null : state.landmark.trim(),
        'city': state.city.trim(),
        'state': state.stateName.trim(),
        'pincode': state.pincode.trim(),
        'country': 'India',
      },
      // Capture provenance. A device fix reports GPS with its REAL accuracy
      // radius (never claimed as 100%). A pin the shopkeeper placed by hand —
      // permission denied, GPS off, or no signal — is reported as MANUAL with
      // no accuracy radius, so the backend never records a fiction.
      'location': reading == null
          ? {
              'location_source': 'MANUAL',
              'location_type': 'SHOP_ENTRANCE',
              'location_status': 'CORRECTED',
              'location_integrity_status': 'UNKNOWN',
              'location_verified': true,
            }
          : {
              'location_source': 'GPS',
              'location_type': 'SHOP_ENTRANCE',
              'location_status':
                  location.pinIsAdjusted ? 'CORRECTED' : 'CONFIRMED',
              'location_integrity_status':
                  reading.isMock ? 'SUSPICIOUS' : 'NORMAL',
              'accuracy_meters': location.accuracyMeters,
              'location_captured_at':
                  reading.timestamp.toUtc().toIso8601String(),
              'location_verified': true,
            },
    };
  }

  /// Technical exceptions → shopkeeper-friendly copy.
  String _friendly(ApiException e, {required String fallback}) {
    if (e.isUnauthorized || e.statusCode == 401) {
      return 'Your session has expired. Please sign in again.';
    }
    if (e.statusCode == 403) {
      return 'You do not have permission to register a shop.';
    }
    if (e.statusCode == 409) {
      return 'A business is already registered with these details.';
    }
    final code = e.errorCode ?? '';
    if (code == 'SESSION_EXPIRED') {
      return 'Your session has expired. Please sign in again.';
    }
    if (e.statusCode == null) {
      return 'No internet connection. Check your network and retry.';
    }
    final message = e.message;
    if (message.isNotEmpty && message != 'Network error' && message.length < 160) {
      return message;
    }
    return fallback;
  }

  /// Fresh wizard state (used when the shopkeeper starts a new registration).
  void reset() {
    state = const ShopRegistrationState();
  }
}

/// Shared provider for the registration wizard. Kept non-autoDispose to match
/// the app's existing convention (plain Notifier + NotifierProvider); the
/// wizard resets itself explicitly via [reset].
final shopRegistrationControllerProvider =
    NotifierProvider<ShopRegistrationController, ShopRegistrationState>(
        ShopRegistrationController.new);