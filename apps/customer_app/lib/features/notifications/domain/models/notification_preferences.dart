import 'package:flutter/foundation.dart';

/// Per-customer notification delivery preferences.
///
/// Field names map 1:1 to the backend contract (API_CONTRACT §21.4/21.5):
/// `push_enabled`, `email_enabled`, `sms_enabled`, `price_alerts`,
/// `availability_alerts`, `promotional`, `deal_alerts`.
///
/// [shopUpdates] is a client-side extension until the backend exposes a
/// dedicated flag; it is persisted locally and never sent to the API.
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

  /// Updates from followed shops (local-only until backend support).
  final bool shopUpdates;

  const NotificationPreferences({
    this.pushEnabled = true,
    this.emailEnabled = true,
    this.smsEnabled = false,
    this.priceAlerts = true,
    this.availabilityAlerts = true,
    this.promotional = false,
    this.dealAlerts = true,
    this.shopUpdates = true,
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
    bool? shopUpdates,
  }) {
    return NotificationPreferences(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      smsEnabled: smsEnabled ?? this.smsEnabled,
      priceAlerts: priceAlerts ?? this.priceAlerts,
      availabilityAlerts: availabilityAlerts ?? this.availabilityAlerts,
      promotional: promotional ?? this.promotional,
      dealAlerts: dealAlerts ?? this.dealAlerts,
      shopUpdates: shopUpdates ?? this.shopUpdates,
    );
  }

  /// Fields understood by the current backend contract.
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
      // Backend has no shop-updates flag yet; keep local default.
      shopUpdates: true,
    );
  }

  /// Full local serialisation (superset of the API fields).
  Map<String, dynamic> toLocalJson() => {
        ...toApiJson(),
        'shop_updates': shopUpdates,
      };

  factory NotificationPreferences.fromLocalJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      pushEnabled: json['push_enabled'] as bool? ?? true,
      emailEnabled: json['email_enabled'] as bool? ?? true,
      smsEnabled: json['sms_enabled'] as bool? ?? false,
      priceAlerts: json['price_alerts'] as bool? ?? true,
      availabilityAlerts: json['availability_alerts'] as bool? ?? true,
      promotional: json['promotional'] as bool? ?? false,
      dealAlerts: json['deal_alerts'] as bool? ?? true,
      shopUpdates: json['shop_updates'] as bool? ?? true,
    );
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
      other.dealAlerts == dealAlerts &&
      other.shopUpdates == shopUpdates;

  @override
  int get hashCode => Object.hash(pushEnabled, emailEnabled, smsEnabled,
      priceAlerts, availabilityAlerts, promotional, dealAlerts, shopUpdates);
}
