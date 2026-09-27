import 'package:flutter/foundation.dart';

/// Per-customer notification delivery preferences.
///
/// Field names map 1:1 to the backend contract (API_CONTRACT §21.4/§21.5),
/// which is fixed by `NotificationPreferencesPayload`:
/// `push_enabled`, `email_enabled`, `sms_enabled`, `price_alerts`,
/// `availability_alerts`, `promotional`, `deal_alerts`.
///
/// There is deliberately **no** `shop_updates` or `system_notifications`
/// field: the `notification_preferences` table has no such column, and the
/// backend decision table (`notification_service._TYPE_REGISTRY`) only gates
/// `PRICE_DROP`, `PRODUCT_AVAILABLE` and `OFFER`. Shipping a client-side
/// switch for either would be a control that silently does nothing once the
/// customer is signed in, so neither is exposed.
@immutable
class NotificationPreferences {
  /// Master switch for push delivery on this account.
  final bool pushEnabled;

  /// Deliver notifications through email as well.
  final bool emailEnabled;

  /// Deliver notifications through SMS as well.
  final bool smsEnabled;

  /// Price-drop alerts for watched products.
  final bool priceAlerts;

  /// Back-in-stock / availability alerts.
  final bool availabilityAlerts;

  /// General promotional messages.
  final bool promotional;

  /// Personalised deal alerts.
  final bool dealAlerts;

  const NotificationPreferences({
    this.pushEnabled = true,
    this.emailEnabled = true,
    this.smsEnabled = false,
    this.priceAlerts = true,
    this.availabilityAlerts = true,
    this.promotional = false,
    this.dealAlerts = true,
  });

  static const NotificationPreferences defaults = NotificationPreferences();

  NotificationPreferences copyWith({
    bool? pushEnabled,
    bool? emailEnabled,
    bool? smsEnabled,
    bool? priceAlerts,
    bool? availabilityAlerts,
    bool? promotional,
    bool? dealAlerts,
  }) {
    return NotificationPreferences(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      smsEnabled: smsEnabled ?? this.smsEnabled,
      priceAlerts: priceAlerts ?? this.priceAlerts,
      availabilityAlerts: availabilityAlerts ?? this.availabilityAlerts,
      promotional: promotional ?? this.promotional,
      dealAlerts: dealAlerts ?? this.dealAlerts,
    );
  }

  /// Fields understood by the current backend contract.
  ///
  /// This is the exact set `NotificationPreferencesPayload` accepts; sending
  /// anything else would be silently dropped by Pydantic.
  Map<String, dynamic> toApiJson() => {
    'push_enabled': pushEnabled,
    'email_enabled': emailEnabled,
    'sms_enabled': smsEnabled,
    'price_alerts': priceAlerts,
    'availability_alerts': availabilityAlerts,
    'promotional': promotional,
    'deal_alerts': dealAlerts,
  };

  factory NotificationPreferences.fromApiJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      pushEnabled: json['push_enabled'] as bool? ?? true,
      emailEnabled: json['email_enabled'] as bool? ?? true,
      smsEnabled: json['sms_enabled'] as bool? ?? false,
      priceAlerts: json['price_alerts'] as bool? ?? true,
      availabilityAlerts: json['availability_alerts'] as bool? ?? true,
      promotional: json['promotional'] as bool? ?? false,
      dealAlerts: json['deal_alerts'] as bool? ?? true,
    );
  }

  /// Local serialisation.
  ///
  /// Identical to [toApiJson] because every stored preference is a real
  /// backend field. The two are kept as separate methods so that adding a
  /// genuinely local-only field later is an explicit, reviewable decision
  /// rather than an accident of one method serving both purposes.
  Map<String, dynamic> toLocalJson() => toApiJson();

  factory NotificationPreferences.fromLocalJson(Map<String, dynamic> json) {
    return NotificationPreferences.fromApiJson(json);
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationPreferences &&
      other.pushEnabled == pushEnabled &&
      other.emailEnabled == emailEnabled &&
      other.smsEnabled == smsEnabled &&
      other.priceAlerts == priceAlerts &&
      other.availabilityAlerts == availabilityAlerts &&
      other.promotional == promotional &&
      other.dealAlerts == dealAlerts;

  @override
  int get hashCode => Object.hash(
    pushEnabled,
    emailEnabled,
    smsEnabled,
    priceAlerts,
    availabilityAlerts,
    promotional,
    dealAlerts,
  );
}
