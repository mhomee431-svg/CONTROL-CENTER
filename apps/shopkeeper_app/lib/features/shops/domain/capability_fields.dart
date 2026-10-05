/// CAPABILITY-DRIVEN FIELDS — which inputs a shop actually gets.
///
/// The rule this file implements is that the FIELDS change with the category and
/// the business type, while the LOOK does not change at all. Every screen renders
/// inputs the same way (a 16px gap, an outlined field with a leading icon, the
/// shared dropdown); what varies is how many there are and which validators run.
///
/// Two separate things, kept apart on purpose:
///   * `CategoryCapabilitySet` decides WHETHER a field appears, and that set
///     comes from the backend — never from here.
///   * the specs below decide what a field is CALLED and how it is validated.
///
/// So a capability the backend grants but this build has no field for renders
/// nothing rather than an invented input.
library;

import '../domain/shop_models.dart';

/// The input kinds the shared renderer knows how to draw.
///
/// Anything outside this set is intentionally unsupported: adding a kind means
/// teaching the renderer HyperLocal's spacing, icon and validation conventions,
/// not special-casing one screen.
enum CapabilityFieldKind {
  /// Single-line free text.
  text,

  /// Multi-line free text.
  multiline,

  /// Numeric input; rendered with the shared [NumericInput] formatter.
  number,

  /// A choice from a fixed set; rendered with the shared dropdown.
  choice,
}

/// Icon name, kept as a plain string so this file needs no Flutter import and can
/// be unit-tested without a widget binding. The renderer maps it to an icon.
typedef IconCodex = String;

/// One capability-driven input.
class CapabilityFieldSpec {
  const CapabilityFieldSpec({
    required this.key,
    required this.label,
    required this.kind,
    required this.icon,
    this.hint,
    this.required = false,
    this.maxLength,
    this.options = const <String>[],
    this.validate,
  });

  /// Stable identifier — also the key this form is submitted under.
  final String key;

  /// Label for the field, using the app's text conventions.
  final String label;

  final CapabilityFieldKind kind;

  /// Leading icon, matching the outlined-field convention used everywhere.
  final IconCodex icon;

  final String? hint;
  final bool required;
  final int? maxLength;

  /// Choices for [CapabilityFieldKind.choice].
  final List<String> options;

  /// Optional extra rule, composed with the built-in required check.
  ///
  /// Takes a nullable value because that is what `TextFormField.validator`
  /// hands it; the built-in required check has already rejected blanks, so the
  /// implementation can rely on a non-empty value.
  final String? Function(String? value)? validate;

  /// Returns an error message, or null when acceptable.
  String? errorFor(String? value) {
    final trimmed = (value ?? '').trim();
    if (required && trimmed.isEmpty) return '$label is required';
    if (trimmed.isEmpty) return null;
    return validate?.call(trimmed);
  }
}

/// The capability → fields registry.
///
/// Only capabilities that change the SHOP-LEVEL form appear here. A capability
/// that governs a different screen (products, offers, POS, import) contributes
/// nothing on purpose — those screens already render themselves, and pretending
/// otherwise would put a duplicate input on the registration form.
const Map<CategoryCapability, List<CapabilityFieldSpec>>
    kCapabilityFields = {
  CategoryCapability.operatingHours: [
    CapabilityFieldSpec(
      key: 'opening_time',
      label: 'Opening time',
      kind: CapabilityFieldKind.text,
      icon: 'wb_sunny_outlined',
      hint: '09:00',
      required: true,
    ),
    CapabilityFieldSpec(
      key: 'closing_time',
      label: 'Closing time',
      kind: CapabilityFieldKind.text,
      icon: 'bedtime_outlined',
      hint: '21:00',
      required: true,
    ),
    CapabilityFieldSpec(
      key: 'closed_on',
      label: 'Closed on',
      kind: CapabilityFieldKind.choice,
      icon: 'event_busy_outlined',
      options: <String>[
        'None',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ],
    ),
  ],
  CategoryCapability.services: [
    CapabilityFieldSpec(
      key: 'service_summary',
      label: 'Services you offer',
      kind: CapabilityFieldKind.multiline,
      icon: 'spa_outlined',
      hint: 'What can a customer book or ask for?',
      maxLength: 400,
    ),
  ],
  CategoryCapability.booking: [
    CapabilityFieldSpec(
      key: 'booking_lead_hours',
      label: 'Booking lead time (hours)',
      kind: CapabilityFieldKind.number,
      icon: 'schedule_outlined',
      hint: '24',
      validate: _nonNegativeNumber,
    ),
  ],
  CategoryCapability.documents: [
    CapabilityFieldSpec(
      key: 'gst_number',
      label: 'GST number',
      kind: CapabilityFieldKind.text,
      icon: 'receipt_long_outlined',
      hint: '22AAAAA0000A1Z5',
      maxLength: 15,
      validate: _gstShape,
    ),
  ],
  CategoryCapability.contact: [
    CapabilityFieldSpec(
      key: 'contact_phone',
      label: 'Contact number',
      kind: CapabilityFieldKind.text,
      icon: 'phone_outlined',
      required: true,
      validate: _phoneShape,
    ),
  ],
  CategoryCapability.categorySpecificData: [
    CapabilityFieldSpec(
      key: 'business_highlights',
      label: 'What makes your business stand out',
      kind: CapabilityFieldKind.multiline,
      icon: 'auto_awesome_outlined',
      maxLength: 300,
    ),
  ],
};

/// Category-specific business fields, keyed by [ServiceCategoryProfile].
///
/// `CATEGORY_SPECIFIC_DATA` says "this trade has data of its own" but not WHICH,
/// and the answer is genuinely different per trade — a tour operator's service
/// area is not a restaurant's offerings and not a transporter's route list. A
/// single generic field would be a guess, and guessing here is what the spec
/// forbids.
///
/// Each entry names something the backend already stores:
///   * service area → the `service_areas` table (`name`, `pincode_prefix`,
///     `delivery_radius_km`),
///   * offerings → the restaurant menu data,
///   * routes / destinations / itinerary → `transport_providers` and its
///     vehicle columns.
///
/// Category codes are NOT re-typed here: the code→profile mapping lives in
/// `shop_models.dart` beside the other category data, and capability presence
/// still gates this — a category without `CATEGORY_SPECIFIC_DATA` gets none of
/// these fields, whatever this map says.
const Map<ServiceCategoryProfile, List<CapabilityFieldSpec>>
    kCategorySpecificFields = <ServiceCategoryProfile,
        List<CapabilityFieldSpec>>{
  // Personal transport / personal travel: travel providers, tour services,
  // marriage and event travel, transport arrangements. Service-led, so no
  // product form — these are the business-level fields the spec lists.
  ServiceCategoryProfile.personalTravel: [
    CapabilityFieldSpec(
      key: 'service_area',
      label: 'Service area',
      kind: CapabilityFieldKind.text,
      icon: 'map_outlined',
      hint: 'Cities, districts or areas you cover',
      maxLength: 200,
    ),
    CapabilityFieldSpec(
      key: 'service_types',
      label: 'Services you arrange',
      kind: CapabilityFieldKind.multiline,
      icon: 'luggage_outlined',
      hint: 'Personal travel, tour services, event travel, transfers',
      maxLength: 400,
    ),
    CapabilityFieldSpec(
      key: 'travel_details',
      label: 'Travel or service details',
      kind: CapabilityFieldKind.multiline,
      icon: 'flight_takeoff_outlined',
      maxLength: 400,
    ),
  ],
  // Transport: routes and fares rather than destinations.
  ServiceCategoryProfile.transport: [
    CapabilityFieldSpec(
      key: 'service_area',
      label: 'Service area',
      kind: CapabilityFieldKind.text,
      icon: 'map_outlined',
      hint: 'Routes or areas you operate in',
      maxLength: 200,
    ),
    CapabilityFieldSpec(
      key: 'route_fares',
      label: 'Routes and fares',
      kind: CapabilityFieldKind.multiline,
      icon: 'alt_route_outlined',
      maxLength: 400,
    ),
  ],
  // Restaurants: offerings, never a stock ledger.
  ServiceCategoryProfile.restaurant: [
    CapabilityFieldSpec(
      key: 'menu_offerings',
      label: 'Offerings',
      kind: CapabilityFieldKind.multiline,
      icon: 'restaurant_menu_outlined',
      maxLength: 500,
    ),
  ],
};

/// Validators receive a nullable value so they satisfy
/// `String? Function(String?)?` without a cast at every use site.
String? _nonNegativeNumber(String? value) {
  final parsed = num.tryParse((value ?? '').trim());
  if (parsed == null) return 'Enter a number';
  if (parsed < 0) return 'Cannot be negative';
  return null;
}

String? _gstShape(String? value) {
  // Shape only. Whether a GST number is real is the backend's answer; a client
  // that pretended to know would reject valid numbers and accept invalid ones.
  final ok =
      RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]{3}$').hasMatch(value ?? '');
  return ok ? null : 'Use the 15-character GST format';
}

String? _phoneShape(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length < 10) return 'Enter a valid phone number';
  return null;
}

/// Every field the given capability set allows, in a stable order.
///
/// Order comes from the capability enum rather than the map's insertion order,
/// so adding a capability cannot silently reshuffle an existing form.
List<CapabilityFieldSpec> capabilityFieldsFor(CategoryCapabilitySet set) {
  final fields = <CapabilityFieldSpec>[];
  for (final capability in CategoryCapability.values) {
    if (!set.has(capability)) continue;
    fields.addAll(kCapabilityFields[capability] ?? const []);
    // Category-specific fields are an ADDITION to the generic ones, never a
    // replacement: the generic `business_highlights` still applies. They stay
    // behind CATEGORY_SPECIFIC_DATA so a category the backend did not grant it
    // to cannot surface trade-specific inputs.
    if (capability == CategoryCapability.categorySpecificData) {
      final profile = serviceProfileForCategory(set.categoryCode);
      if (profile != null) {
        fields.addAll(kCategorySpecificFields[profile] ?? const []);
      }
    }
  }
  return List.unmodifiable(fields);
}

/// The values a form should submit, taken from an explicit field list.
///
/// This is the SERVER-AUTHORITATIVE version. [submittedCapabilityFields] is the
/// offline convenience that re-derives the list from a capability set; when the
/// backend has already said which fields exist, that re-derivation is a guess
/// and a field the server declared would be dropped on the way out even though
/// the shopkeeper filled it in.
Map<String, String> submittedCapabilityValues(
  List<CapabilityFieldSpec> specs,
  Map<String, String> values,
) {
  final out = <String, String>{};
  for (final spec in specs) {
    final value = (values[spec.key] ?? '').trim();
    if (value.isNotEmpty) out[spec.key] = value;
  }
  return out;
}

/// The values a form should submit, keyed by [CapabilityFieldSpec.key].
///
/// Only non-empty values are included: sending a blank optional field is how a
/// backend ends up with empty strings where it expected "not provided".
Map<String, String> submittedCapabilityFields(
  CategoryCapabilitySet set,
  Map<String, String> values,
) =>
    submittedCapabilityValues(capabilityFieldsFor(set), values);

/// Validates an explicit field list, returning `{key: error}` for failures.
Map<String, String> validateCapabilityValues(
  List<CapabilityFieldSpec> specs,
  Map<String, String> values,
) {
  final errors = <String, String>{};
  for (final spec in specs) {
    final error = spec.errorFor(values[spec.key]);
    if (error != null) errors[spec.key] = error;
  }
  return errors;
}

/// Validates every field, returning `{key: error}` for the ones that fail.
Map<String, String> validateCapabilityFields(
  CategoryCapabilitySet set,
  Map<String, String> values,
) =>
    validateCapabilityValues(capabilityFieldsFor(set), values);

/// True when every field in [specs] is filled and valid.
///
/// The gate a submit handler calls, so a screen cannot accidentally post a form
/// the backend will reject. Takes the loaded field list rather than a capability
/// set so that a required field the server declared — and this build has no local
/// twin for — still blocks submission.
bool isCapabilityValuesComplete(
  List<CapabilityFieldSpec> specs,
  Map<String, String> values,
) =>
    validateCapabilityValues(specs, values).isEmpty;

/// True when every field the capability set requires has been filled and valid.
bool isCapabilityFormComplete(
  CategoryCapabilitySet set,
  Map<String, String> values,
) =>
    validateCapabilityFields(set, values).isEmpty;