/// Device push-registration payload prepared for the future backend
/// notification service (API_CONTRACT §21.6).
///
/// The customer app obtains the platform token from a
/// [PushNotificationService] implementation (e.g. FCM) and hands it to
/// the repository; no delivery logic ever lives in the UI layer.
class DeviceTokenRegistration {
  /// Provider token (max 500 chars per contract validation).
  final String token;

  /// `android`, `ios` or `web`.
  final String deviceType;

  /// Push provider identifier — `FCM` or `APNS`.
  final String? platform;

  /// App version (max 20 chars per contract validation).
  final String? appVersion;

  const DeviceTokenRegistration({
    required this.token,
    required this.deviceType,
    this.platform,
    this.appVersion,
  });

  Map<String, dynamic> toJson() => {
    'token': token,
    'device_type': deviceType,
    if (platform != null) 'platform': platform,
    if (appVersion != null) 'app_version': appVersion,
  };
}
