import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../shops/data/location_accuracy_config.dart';
import '../../shops/data/location_service.dart';
import '../../shops/domain/shop_models.dart';

/// Steps of the "Register Your Shop" wizard, in visual order.
enum RegistrationStep { welcome, businessInfo, location, documents, review, success }

/// Business types offered on the Business Information step.
const kBusinessTypes = <String>[
  'Retail',
  'Wholesale',
  'Retail & Wholesale',
  'Service',
  'Other',
];

/// Lifecycle of a single verification-document upload slot.
enum DocumentUploadStatus { idle, uploading, uploaded, error }

/// One document slot (e.g. Drug License) + its local pick & upload result.
class DocumentSlot {
  const DocumentSlot({
    required this.requirement,
    this.pickedName,
    this.pickedPath,
    this.pickedSizeBytes,
    this.status = DocumentUploadStatus.idle,
    this.objectKey,
    this.error,
  });

  final DocumentRequirement requirement;

  /// Local filename chosen by the shopkeeper (pre-upload display only).
  final String? pickedName;

  /// Local absolute path (read at submit time for the S3 upload).
  final String? pickedPath;
  final int? pickedSizeBytes;

  final DocumentUploadStatus status;

  /// Server-minted object key persisted as the durable document reference.
  final String? objectKey;
  final String? error;

  bool get hasFile => pickedName != null;
  bool get isUploaded => status == DocumentUploadStatus.uploaded;
  bool get isBusy => status == DocumentUploadStatus.uploading;

  DocumentSlot copyWith({
    String? pickedName,
    String? pickedPath,
    int? pickedSizeBytes,
    bool clearFile = false,
    DocumentUploadStatus? status,
    String? objectKey,
    bool clearObjectKey = false,
    String? error,
    bool clearError = false,
  }) {
    return DocumentSlot(
      requirement: requirement,
      pickedName: clearFile ? null : (pickedName ?? this.pickedName),
      pickedPath: clearFile ? null : (pickedPath ?? this.pickedPath),
      pickedSizeBytes:
          clearFile ? null : (pickedSizeBytes ?? this.pickedSizeBytes),
      status: status ?? this.status,
      objectKey: clearObjectKey ? null : (objectKey ?? this.objectKey),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Lifecycle of the submit request (prevents duplicate submission and drives
/// honest loading copy: "Uploading document…", "Submitting registration…").
enum SubmitPhase {
  idle,
  uploadingDocuments,
  creatingShop,
  savingHours,
  attachingDocuments,
  done,
}

/// Location acquisition status for the wizard's map step.
enum RegistrationLocationStatus {
  idle,
  requestingPermission,
  locating,
  adjustingAccuracy,
  ready,
  permissionDenied,

  /// Permanently denied / blocked by policy: asking again cannot work, only the
  /// system settings can.
  permissionBlocked,
  serviceDisabled,
  error,
}

/// Immutable wizard state. The UI renders this and forwards events to the
/// [ShopRegistrationController] — it contains no business logic.
@immutable
class ShopRegistrationState {
  const ShopRegistrationState({
    this.step = RegistrationStep.welcome,
    this.categories = const [],
    this.categoriesLoading = false,
    this.categoriesError,
    this.category,
    this.businessType,
    this.shopName = '',
    this.gstin = '',
    this.udyam = '',
    this.requirementsLoading = false,
    this.requirementsError,
    this.requirements,
    this.addressLine = '',
    this.city = '',
    this.stateName = '',
    this.pincode = '',
    this.landmark = '',
    this.locationStatus = RegistrationLocationStatus.idle,
    this.reading,
    this.pin,
    this.pinAdjusted = false,
    this.pinDriftMeters,
    this.pinDriftConfirmed = false,
    this.accuracyMeters,
    this.reverseGeocoding = false,
    this.detectedAddress,
    this.locationManual = false,
    this.locationError,
    this.description = '',
    this.openTime = '09:00',
    this.closeTime = '21:00',
    this.website = '',
    this.socialMedia = '',
    this.slots = const {},
    this.submitPhase = SubmitPhase.idle,
    this.submitError,
    this.submitErrorCode,
    this.attempted = false,
  });

  final RegistrationStep step;

  // ── Business information ──
  final List<MerchantCategoryOption> categories;
  final bool categoriesLoading;
  final String? categoriesError;
  final MerchantCategoryOption? category;

  /// Retail | Wholesale | … (informational — no backend rules).
  final String? businessType;
  final String shopName;

  /// Raw GSTIN / Udyam as typed (validated by [ShopRegistrationValidators]).
  final String gstin;
  final String udyam;

  // ── Backend-driven requirements for the selected category ──
  final bool requirementsLoading;
  final String? requirementsError;
  final CategoryRequirements? requirements;

  // ── Location ──
  final String addressLine;
  final String city;
  final String stateName;
  final String pincode;
  final String landmark;
  final RegistrationLocationStatus locationStatus;
  final GpsReading? reading;

  /// The shop-entrance pin (initialised to the GPS fix, then draggable).
  final LatLng? pin;
  final bool pinAdjusted;

  /// Distance between the shop pin and the device GPS fix, in meters.
  final double? pinDriftMeters;

  /// True once the shopkeeper confirmed a significant pin drift.
  final bool pinDriftConfirmed;
  final double? accuracyMeters;
  final bool reverseGeocoding;
  final PickedLocation? detectedAddress;

  /// True when the pin was placed by hand because no GPS fix was available
  /// (permission denied, GPS off, or no signal) — the submitted capture
  /// provenance says `MANUAL` and claims no accuracy radius.
  final bool locationManual;
  final String? locationError;

  // ── Documents & additional information ──
  final String description;

  /// HH:MM 24h strings as submitted to the backend.
  final String openTime;
  final String closeTime;
  final String website;
  final String socialMedia;

  /// Document slots keyed by backend requirement code.
  final Map<String, DocumentSlot> slots;

  final SubmitPhase submitPhase;
  final String? submitError;
  final String? submitErrorCode;
  final bool attempted;

  bool get isSubmitting =>
      submitPhase != SubmitPhase.idle && submitPhase != SubmitPhase.done;

  /// All document slots (universal + category-specific), in display order.
  List<DocumentSlot> get slotList => slots.values.toList(growable: false);

  bool get hasPin => pin != null;

  /// True when the GPS fix backing the current pin is good enough to submit
  /// (never claims 100% accuracy — the real radius is shown in the UI).
  bool get hasUsableLocation =>
      hasPin && accuracyMeters != null && accuracyMeters! <= 50;

  /// True when the pin was moved far from the GPS fix and the shopkeeper has
  /// not yet confirmed it ("Are you sure this is your shop?").
  bool get needsPinDriftConfirmation =>
      !pinDriftConfirmed &&
      (pinDriftMeters ?? 0) > LocationAccuracyConfig.pinDriftWarningMeters;

  ShopRegistrationState copyWith({
    RegistrationStep? step,
    List<MerchantCategoryOption>? categories,
    bool? categoriesLoading,
    String? categoriesError,
    bool clearCategoriesError = false,
    MerchantCategoryOption? category,
    bool clearCategory = false,
    String? businessType,
    bool clearBusinessType = false,
    String? shopName,
    String? gstin,
    String? udyam,
    bool? requirementsLoading,
    String? requirementsError,
    bool clearRequirementsError = false,
    CategoryRequirements? requirements,
    bool clearRequirements = false,
    String? addressLine,
    String? city,
    String? stateName,
    String? pincode,
    String? landmark,
    RegistrationLocationStatus? locationStatus,
    GpsReading? reading,
    LatLng? pin,
    bool clearPin = false,
    bool? pinAdjusted,
    double? pinDriftMeters,
    bool clearPinDrift = false,
    bool? pinDriftConfirmed,
    double? accuracyMeters,
    bool clearAccuracy = false,
    bool? reverseGeocoding,
    PickedLocation? detectedAddress,
    bool clearDetectedAddress = false,
    /// The pin was placed by hand (permission denied / GPS off) instead of from
    /// a GPS fix — reported honestly to the backend as `MANUAL`.
    bool? locationManual,
    String? locationError,
    bool clearLocationError = false,
    String? description,
    String? openTime,
    String? closeTime,
    String? website,
    String? socialMedia,
    Map<String, DocumentSlot>? slots,
    SubmitPhase? submitPhase,
    String? submitError,
    bool clearSubmitError = false,
    String? submitErrorCode,
    bool clearSubmitErrorCode = false,
    bool? attempted,
  }) {
    return ShopRegistrationState(
      step: step ?? this.step,
      categories: categories ?? this.categories,
      categoriesLoading: categoriesLoading ?? this.categoriesLoading,
      categoriesError:
          clearCategoriesError ? null : (categoriesError ?? this.categoriesError),
      category: clearCategory ? null : (category ?? this.category),
      businessType:
          clearBusinessType ? null : (businessType ?? this.businessType),
      shopName: shopName ?? this.shopName,
      gstin: gstin ?? this.gstin,
      udyam: udyam ?? this.udyam,
      requirementsLoading: requirementsLoading ?? this.requirementsLoading,
      requirementsError: clearRequirementsError
          ? null
          : (requirementsError ?? this.requirementsError),
      requirements: clearRequirements ? null : (requirements ?? this.requirements),
      addressLine: addressLine ?? this.addressLine,
      city: city ?? this.city,
      stateName: stateName ?? this.stateName,
      pincode: pincode ?? this.pincode,
      landmark: landmark ?? this.landmark,
      locationStatus: locationStatus ?? this.locationStatus,
      reading: reading ?? this.reading,
      pin: clearPin ? null : (pin ?? this.pin),
      pinAdjusted: pinAdjusted ?? this.pinAdjusted,
      pinDriftMeters:
          clearPinDrift ? null : (pinDriftMeters ?? this.pinDriftMeters),
      pinDriftConfirmed: pinDriftConfirmed ?? this.pinDriftConfirmed,
      accuracyMeters: clearAccuracy ? null : (accuracyMeters ?? this.accuracyMeters),
      reverseGeocoding: reverseGeocoding ?? this.reverseGeocoding,
      detectedAddress:
          clearDetectedAddress ? null : (detectedAddress ?? this.detectedAddress),
      locationManual: locationManual ?? this.locationManual,
      locationError:
          clearLocationError ? null : (locationError ?? this.locationError),
      description: description ?? this.description,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
      website: website ?? this.website,
      socialMedia: socialMedia ?? this.socialMedia,
      slots: slots ?? this.slots,
      submitPhase: submitPhase ?? this.submitPhase,
      submitError: clearSubmitError ? null : (submitError ?? this.submitError),
      submitErrorCode:
          clearSubmitErrorCode ? null : (submitErrorCode ?? this.submitErrorCode),
      attempted: attempted ?? this.attempted,
    );
  }
}

/// Local (client-side) validation for the wizard. Mirrors the backend rules
/// (same GSTIN/Udyam regex as `schemas/merchant_onboarding.py`) — the backend
/// validates everything again on submit.
class ShopRegistrationValidators {
  ShopRegistrationValidators._();

  static final RegExp _gstin =
      RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
  static final RegExp _udyam = RegExp(r'^UDYAM-[A-Z]{2}-[0-9]{8,12}$');
  static final RegExp _pincode = RegExp(r'^[1-9][0-9]{5}$');

  /// Shop / business name — required.
  static String? shopName(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Shop name is required';
    if (value.length > 255) return 'Shop name is too long';
    return null;
  }

  /// GSTIN — optional, but must be a valid format when entered.
  static String? gstin(String? v) {
    final value = (v ?? '').trim().toUpperCase();
    if (value.isEmpty) return null;
    if (!_gstin.hasMatch(value)) return 'Enter a valid 15-character GSTIN';
    return null;
  }

  /// Udyam / MSME — optional, but must be valid when entered.
  static String? udyam(String? v) {
    final value = (v ?? '').trim().toUpperCase();
    if (value.isEmpty) return null;
    if (!_udyam.hasMatch(value)) return 'Format: UDYAM-XX-0000000000';
    return null;
  }

  /// Indian pincode — required, cannot start with 0.
  static String? pincode(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Pincode is required';
    if (!_pincode.hasMatch(value)) return 'Enter a valid 6-digit pincode';
    return null;
  }

  /// Latitude / longitude sanity (mirrors backend ge=−90 / le=180).
  static bool validLatitude(double? v) => v != null && v >= -90 && v <= 90;
  static bool validLongitude(double? v) => v != null && v >= -180 && v <= 180;

  /// Category — required.
  static String? category(MerchantCategoryOption? v) =>
      v == null ? 'Select your business category' : null;

  /// Business type — required.
  static String? businessType(String? v) =>
      (v == null || v.isEmpty) ? 'Select your business type' : null;

  /// Address — required.
  static String? address(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Address is required';
    if (value.length > 255) return 'Address is too long';
    return null;
  }

  static String? city(String? v) =>
      (v ?? '').trim().isEmpty ? 'City is required' : null;
  static String? stateName(String? v) =>
      (v ?? '').trim().isEmpty ? 'State is required' : null;
}
