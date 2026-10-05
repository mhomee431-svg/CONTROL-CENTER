/// CAPABILITY-DRIVEN PRODUCT FIELDS â€” what one category asks you to type.
///
/// Business category and product category are different things, and this file is
/// the proof of it: a pharmacy item, a spark plug and a flight booking are three
/// unrelated shapes. Rather than forcing one inventory form on everybody (or
/// worse, inventing fields per category in Flutter), the backend decides WHICH
/// attributes a category has and this file renders exactly that.
///
/// Same discipline as [CapabilityFieldSpec]:
///   * the backend's attribute LIST is authoritative â€” this build never adds an
///     attribute the backend did not send;
///   * this file only supplies presentation (icon) and validation for keys it
///     recognises, so an unknown key degrades to a plain text input rather than
///     being dropped or guessed at;
///   * a category with no attributes â€” a restaurant, a transport provider â€” has an
///     empty form, which is a correct answer and not a missing feature.
///
/// Regulatory verification is deliberately absent: the spec forbids inventing it
/// before the backend defines it.
library;

/// How an attribute value is captured. Mirrors the backend's kinds one-to-one.
enum ProductAttributeKind {
  /// Single-line free text.
  text,

  /// Multi-line free text.
  multiline,

  /// Numeric input, using the app's shared numeric formatter.
  number,

  /// A choice from a fixed set, using the app's shared dropdown.
  choice;

  /// Parse a backend kind string, falling back to [text].
  ///
  /// A future backend kind must degrade to something usable rather than crash
  /// the form on a shipping app.
  static ProductAttributeKind parse(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'MULTILINE':
        return ProductAttributeKind.multiline;
      case 'NUMBER':
        return ProductAttributeKind.number;
      case 'CHOICE':
        return ProductAttributeKind.choice;
      default:
        return ProductAttributeKind.text;
    }
  }
}

/// Where a value is stored. The key doubles as the storage destination.
enum ProductAttributeKey {
  name,
  brand,
  category,
  subcategory,
  productType,
  description,
  baseUnit,
  baseQuantity,
  sku,
  barcode,
  variant,
  extensionAttributes,
  /// Furniture & home care, each named because the spec names them
  /// separately and they are separately useful — one free-text box holding
  /// "oak, brown, 6 ft" cannot be filtered on.
  ///
  /// All land in the variant's `attributes_json`, which is where the
  /// schema already keeps category-specific data.
  dimensions,
  material,
  color,
  assemblyService,
  /// Size — shared across household, sports, hardware and furniture rather than
  /// re-typed per category. Its own key so a shopper can filter on it without
  /// also filtering on colour or material: one box reading
  /// "large, blue, cotton" is data nobody can query.
  size,

  /// Sports.
  sportType,
  model,
  equipmentType,

  /// Books.
  language,
  publicationDate,

  /// Automotive and hardware.
  partNumber,
  toolType,
  specification,

  /// Author / creator. Books, media and stationery all need it and none of
  /// them can express it through an existing column, so the backend puts it in
  /// the variant's `attributes_json`.
  author,

  /// OEM / OE reference number for an automotive part — the number the
  /// manufacturer superseded, which is not the part's own number. The backend
  /// declares it as `IdentifierType.MPN`.
  oemReferenceNumber,

  /// Vehicle MODEL, recorded as typed text. Not a fitment rule: the schema has
  /// no vehicle catalog, so nothing here claims what the part fits.
  vehicleModel,

  /// Who made the part. Separate from [brand] because "Bosch QuietCast" is a
  /// line while Bosch is the manufacturer an OE catalogue is searched by.
  manufacturer,
  price,
  mrp,
  availability,
  quantity,
  image;

  // DELIBERATELY ABSENT: prescriptionRequired, regulatoryClass, licenseType,
  // isRestricted.
  //
  // `product_masters` has those columns, but the backend has defined nothing
  // about them â€” no enum, no CHECK constraint, no validation, and a default of
  // "UNCLASSIFIED" that says nobody decided. The spec lists licence,
  // regulatory and medical-attribute fields as future work and forbids
  // inventing them.
  //
  // No unused enum members are kept on purpose: a key declared but unused is
  // an invitation to wire it up later without re-asking the question.
  //
  // Add them back only when the backend defines the valid values.

  /// The wire name, matching the backend's `key`.
  String get wireName => switch (this) {
        ProductAttributeKey.name => 'name',
        ProductAttributeKey.brand => 'brand',
        ProductAttributeKey.category => 'category',
        ProductAttributeKey.subcategory => 'subcategory',
        ProductAttributeKey.productType => 'product_type',
        ProductAttributeKey.description => 'description',
        ProductAttributeKey.baseUnit => 'base_unit',
        ProductAttributeKey.baseQuantity => 'base_quantity',
        ProductAttributeKey.sku => 'sku',
        ProductAttributeKey.barcode => 'barcode',
        ProductAttributeKey.variant => 'variant',
        ProductAttributeKey.extensionAttributes => 'extension_attributes',
        ProductAttributeKey.dimensions => 'dimensions',
        ProductAttributeKey.material => 'material',
        ProductAttributeKey.color => 'colour',
        ProductAttributeKey.assemblyService => 'assembly_service',
        ProductAttributeKey.size => 'size',
        ProductAttributeKey.sportType => 'sport_type',
        ProductAttributeKey.model => 'model',
        ProductAttributeKey.equipmentType => 'equipment_type',
        ProductAttributeKey.language => 'language',
        ProductAttributeKey.publicationDate => 'publication_date',
        ProductAttributeKey.partNumber => 'part_number',
        ProductAttributeKey.toolType => 'tool_type',
        ProductAttributeKey.specification => 'specification',
        ProductAttributeKey.author => 'author',
        ProductAttributeKey.oemReferenceNumber => 'oem_reference_number',
        ProductAttributeKey.vehicleModel => 'vehicle_model',
        ProductAttributeKey.manufacturer => 'manufacturer',
        ProductAttributeKey.price => 'price',
        ProductAttributeKey.mrp => 'mrp',
        ProductAttributeKey.availability => 'availability',
        ProductAttributeKey.quantity => 'quantity',
        ProductAttributeKey.image => 'image',
      };

  /// Recognise a backend key, or null when this build does not know it.
  static ProductAttributeKey? tryParse(String? raw) {
    final value = (raw ?? '').trim();
    for (final key in ProductAttributeKey.values) {
      if (key.wireName == value) return key;
    }
    return null;
  }

  /// Icons per recognised key, mirroring the app's existing icon set.
  static String? iconFor(String wireKey) => switch (tryParse(wireKey)) {
        ProductAttributeKey.name => 'inventory',
        ProductAttributeKey.brand => 'label',
        ProductAttributeKey.category => 'category',
        ProductAttributeKey.subcategory => 'category',
        ProductAttributeKey.productType => 'category',
        ProductAttributeKey.description => 'description',
        ProductAttributeKey.baseUnit => 'scale',
        ProductAttributeKey.baseQuantity => 'numbers',
        ProductAttributeKey.sku => 'qr_code',
        ProductAttributeKey.barcode => 'qr_code',
        ProductAttributeKey.variant => 'style',
        ProductAttributeKey.extensionAttributes => 'tune',
        ProductAttributeKey.dimensions => 'straighten',
        ProductAttributeKey.material => 'texture',
        ProductAttributeKey.color => 'palette',
        ProductAttributeKey.assemblyService => 'handyman',
        ProductAttributeKey.size => 'straighten',
        ProductAttributeKey.sportType => 'sports_soccer',
        ProductAttributeKey.model => 'style',
        ProductAttributeKey.equipmentType => 'sports_handball',
        ProductAttributeKey.language => 'translate',
        ProductAttributeKey.publicationDate => 'event',
        ProductAttributeKey.partNumber => 'tag',
        ProductAttributeKey.toolType => 'build',
        ProductAttributeKey.specification => 'description',
        ProductAttributeKey.author => 'person',
        ProductAttributeKey.oemReferenceNumber => 'confirmation_number',
        ProductAttributeKey.vehicleModel => 'directions_car',
        ProductAttributeKey.manufacturer => 'business',
        ProductAttributeKey.price => 'currency_rupee',
        ProductAttributeKey.mrp => 'currency_rupee',
        ProductAttributeKey.availability => 'check_circle',
        ProductAttributeKey.quantity => 'numbers',
        ProductAttributeKey.image => 'image',
        null => null,
      };
}

/// The keys that resolve against the catalog rather than to a text column.
///
/// Kept as a set so [ProductAttributeSpec.fromJson] can default the flag to
/// true when talking to an older backend that does not send it â€” failing safe
/// towards offering a picker rather than a box.
const Set<String> _catalogKeys = <String>{
  'category',
  'subcategory',
  'product_type',
};

/// One attribute the backend declared for a category.
class ProductAttributeSpec {
  const ProductAttributeSpec({
    required this.key,
    required this.label,
    required this.kind,
    this.required = false,
    this.hint,
    this.options = const <String>[],
    this.icon,
    this.catalogBacked = false,
    this.identifierType = '',
  });

  /// Build from a backend attribute definition.
  ///
  /// Unknown keys and missing fields degrade instead of throwing: this is data
  /// arriving from a network call on a shipping app.
  factory ProductAttributeSpec.fromJson(Map<String, dynamic> json) {
    final rawKey = (json['key'] as String? ?? '').trim();
    final rawOptions = json['choices'];
    return ProductAttributeSpec(
      key: rawKey,
      label: (json['label'] as String? ?? '').trim(),
      kind: ProductAttributeKind.parse(json['kind'] as String?),
      required: json['required'] == true,
      hint: (json['hint'] as String?)?.trim(),
      options: rawOptions is List
          ? rawOptions.map((e) => '$e').toList(growable: false)
          : const <String>[],
      icon: ProductAttributeKey.iconFor(rawKey),
      // Default true for the keys that resolve to catalog rows: the backend
      // sets it explicitly, but if an older backend omits it the client must
      // still offer a picker rather than a box whose value the database would
      // drop as an unresolvable string.
      catalogBacked: json['catalog_backed'] != false && _catalogKeys.contains(rawKey),
      // Absent from an older backend means "not a typed identifier", which is
      // the honest default — guessing a type would store a wrong one.
      identifierType: (json['identifier_type'] as String? ?? '').trim(),
    );
  }

  /// The backend's key. Also the key this form submits under.
  final String key;

  /// Label as sent by the backend.
  final String label;

  final ProductAttributeKind kind;
  final bool required;
  final String? hint;
  final List<String> options;

  /// Icon name, resolved from the key. Null means "no icon", which the renderer
  /// treats as a plain input.
  final String? icon;

  /// Which `IdentifierType` the value is stored as.
  ///
  /// The schema keeps typed identifiers (`product_identifiers`:
  /// `identifier_type` + `identifier_value`) with ISBN, EAN, ASIN, MPN and
  /// friends. A bare barcode string loses that — a book's ISBN and a shampoo's
  /// EAN are different identifiers and the schema already knows how to tell
  /// them apart.
  ///
  /// Empty means "not a typed identifier": the value is plain text.
  final String identifierType;

  /// True when the destination is a catalog row rather than a column of free
  /// text.
  ///
  /// `product_masters.category_id` and `subcategory_id` are FOREIGN KEYS, so a
  /// typed string cannot be stored â€” it has to resolve to a row in `categories`.
  /// The spec is explicit that final categories come from backend catalog data,
  /// so the renderer must offer the catalog for these rather than a free-text
  /// box whose value the database would silently discard.
  final bool catalogBacked;

  /// False for a key this build does not recognise â€” it still renders, as text.
  bool get isKnownKey => ProductAttributeKey.tryParse(key) != null;

  /// The text to show above the input, falling back to a readable key.
  String get displayLabel => label.isNotEmpty ? label : key;

  /// Validate one value, returning a message when it fails.
  String? errorFor(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return required ? '$displayLabel is required' : null;
    }
    if (kind == ProductAttributeKind.choice && options.isNotEmpty) {
      if (!options.contains(text)) return 'Choose a valid $displayLabel';
    }
    if (kind == ProductAttributeKind.number) {
      final parsed = double.tryParse(text);
      if (parsed == null) return 'Enter a number for $displayLabel';
      if (parsed < 0) return '$displayLabel cannot be negative';
    }
    if (key == ProductAttributeKey.price.wireName) {
      if (double.tryParse(text) == 0) return 'Price must be greater than 0';
    }
    return null;
  }

  /// The JSON this attribute contributes to a submission.
  Map<String, dynamic> toSubmissionJson(String? value) {
    final text = (value ?? '').trim();
    final out = <String, dynamic>{
      'key': key,
      'label': displayLabel,
      'value': text,
    };
    if (kind == ProductAttributeKind.number && text.isNotEmpty) {
      // Send a JSON number, not a string, so the backend stores a real numeric
      // type and arithmetic on price/quantity does not need re-parsing.
      final parsed = double.tryParse(text);
      if (parsed != null) {
        out['value'] =
            parsed == parsed.roundToDouble() ? parsed.toInt() : parsed;
      }
    }
    return out;
  }
}

/// The backend's attribute list for one business category.
///
/// An empty [attributes] list is meaningful: the category sells services and has
/// no product form, which the UI renders as nothing rather than as an error.
class CategoryProductAttributes {
  const CategoryProductAttributes({
    required this.categoryCode,
    required this.attributes,
  });

  /// Parse a backend response, tolerating a missing or mistyped list.
  factory CategoryProductAttributes.fromJson(Map<String, dynamic>? json) {
    final raw = json?['attributes'];
    return CategoryProductAttributes(
      categoryCode: (json?['category_code'] as String? ?? '').trim(),
      attributes: raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(ProductAttributeSpec.fromJson)
              .where((spec) => spec.key.isNotEmpty)
              .toList(growable: false)
          : const <ProductAttributeSpec>[],
    );
  }

  final String categoryCode;
  final List<ProductAttributeSpec> attributes;

  /// True when this category has no product form at all.
  bool get hasNoProductForm => attributes.isEmpty;

  bool has(ProductAttributeKey key) =>
      attributes.any((spec) => spec.key == key.wireName);

  /// `{key: error}` for every attribute that fails.
  Map<String, String> validate(Map<String, String> values) {
    final errors = <String, String>{};
    for (final spec in attributes) {
      final error = spec.errorFor(values[spec.key]);
      if (error != null) errors[spec.key] = error;
    }
    return errors;
  }

  bool isComplete(Map<String, String> values) => validate(values).isEmpty;

  /// Keys that already travel in a dedicated field of the create payload.
  ///
  /// Mirrors the backend's routing table so the client does not offer to send a
  /// value the server will refuse. Keeping the two lists in step is deliberate:
  /// the alternative is a form that fills itself in and then gets rejected with
  /// "send this in the other field", which reads as a bug to the shopkeeper.
  static const Set<String> _columnRouted = {
    'name',
    'description',
    'brand',
    'base_unit',
    'price',
    'mrp',
    'quantity',
    'availability',
    'image',
    'barcode',
  };

  /// Catalog-backed keys are chosen by id in `category_id` / `subcategory_id`.
  static const Set<String> _catalogKeysForSubmission = {
    'category',
    'subcategory',
    'product_type',
  };

  /// Whether this key belongs in the `attributes` map at all.
  ///
  /// A key that is not sent from here still renders: the backend advertises the
  /// whole form, and deciding where each value travels is a separate question.
  bool belongsInAttributeMap(ProductAttributeSpec spec) {
    if (_columnRouted.contains(spec.key)) return false;
    if (_catalogKeysForSubmission.contains(spec.key)) return false;
    // Typed identifiers are submitted as their own identifiers by the server,
    // but the value itself is an ordinary string, so it travels in the map and
    // the backend routes it. Anything the backend advertises therefore counts.
    return true;
  }

  /// The `attributes` map for the create/update payload.
  ///
  /// Only non-blank values are included, and only for keys that actually belong
  /// in the map — so an empty map means "this category has nothing extra to
  /// send" and the caller can leave the field out of the request entirely.
  Map<String, String> toAttributeMap(Map<String, String> values) {
    final out = <String, String>{};
    for (final spec in attributes) {
      final value = (values[spec.key] ?? '').trim();
      if (value.isEmpty) continue;
      if (!belongsInAttributeMap(spec)) continue;
      out[spec.key] = value;
    }
    return out;
  }

  /// The body to submit.
  ///
  /// Blanks are omitted so the backend can distinguish "not provided" from
  /// "explicitly empty", and numbers go across as JSON numbers.
  Map<String, dynamic> toSubmissionJson(Map<String, String> values) => {
        'category_code': categoryCode,
        'attributes': [
          for (final spec in attributes)
            if ((values[spec.key] ?? '').trim().isNotEmpty)
              spec.toSubmissionJson(values[spec.key]),
        ],
      };
}
