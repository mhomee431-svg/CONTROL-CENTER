/// Platform-permission vocabulary for the customer app.
///
/// WHY A SEPARATE VOCABULARY: `permission_handler`'s `PermissionStatus` mixes
/// platform detail (provisional, limited, restricted) into the app's UI logic,
/// and it cannot be constructed in a widget test. Screens depend on these three
/// types instead, so every "what do we do next" decision is a plain switch on an
/// enum that a fake can produce.
///
/// Mirrors `apps/shopkeeper_app/lib/core/permissions/permission_models.dart`
/// deliberately: both apps must read a denial the same way.
library;

/// The permission surfaces the customer app asks for through
/// [PermissionService].
///
/// NOT here: location. The location stack owns its permission through
/// `geolocator` (`LocationService`), which must stay the single owner of the
/// GPS grant — two owners for one permission is how an app asks twice.
enum PermissionKind {
  /// Barcode scanning (`mobile_scanner`).
  camera,
}

/// What the platform says about a permission, normalised into the only
/// outcomes the UI ever has to distinguish.
enum PermissionOutcome {
  /// Granted for real.
  granted,

  /// iOS "limited"/"provisional" — usable, but not a full grant.
  limited,

  /// Refused, but the OS will show the dialog again on the next request.
  denied,

  /// Refused permanently ("Don't ask again", iOS "Don't Allow" after the first
  /// prompt): the ONLY way back is the system settings page.
  permanentlyDenied,

  /// iOS parental controls / MDM — the app may not even ask.
  restricted,

  /// The status could not be read on this platform (no plugin implementation,
  /// e.g. desktop or web builds). Never treated as a denial: the caller keeps
  /// working and lets the underlying feature report its own failure.
  unknown;

  /// True when the feature behind this permission can be used now.
  bool get isGranted => this == granted || this == limited;

  /// True when asking again makes sense (the OS will show its dialog).
  bool get canAskAgain => this == denied || this == unknown;

  /// True when the customer must be sent to the system settings page — asking
  /// again would resolve instantly with the same denial.
  bool get needsSystemSettings =>
      this == permanentlyDenied || this == restricted;

  /// Human status word for settings rows.
  String get label => switch (this) {
        PermissionOutcome.granted => 'Allowed',
        PermissionOutcome.limited => 'Allowed',
        PermissionOutcome.denied => 'Not allowed',
        PermissionOutcome.permanentlyDenied => 'Blocked',
        PermissionOutcome.restricted => 'Blocked',
        PermissionOutcome.unknown => 'Unknown',
      };
}

/// The status of one permission at one moment.
class PermissionSnapshot {
  const PermissionSnapshot({required this.kind, required this.outcome});

  final PermissionKind kind;
  final PermissionOutcome outcome;

  bool get isGranted => outcome.isGranted;
  bool get canAskAgain => outcome.canAskAgain;
  bool get needsSystemSettings => outcome.needsSystemSettings;

  @override
  String toString() => 'PermissionSnapshot(${kind.name}: ${outcome.name})';
}
