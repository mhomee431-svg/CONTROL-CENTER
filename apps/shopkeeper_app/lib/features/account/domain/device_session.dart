/// One active sign-in session (device) reported by the backend.
///
/// Mirrors `GET /api/v1/shopkeeper/auth/sessions` exactly. Every field except
/// [sessionId] is optional, because the backend only records what the client
/// sent at sign-in: an older row may have no device metadata. A missing field
/// renders as a fallback label rather than dropping the row — hiding a
/// signed-in device would defeat the point of this screen.
class DeviceSession {
  const DeviceSession({
    required this.sessionId,
    this.deviceName,
    this.deviceType,
    this.platform,
    this.appVersion,
    this.ipAddress,
    this.lastActivityAt,
    this.createdAt,
    this.expiresAt,
  });

  /// Server-side session identifier — the value `DELETE .../sessions/{id}`
  /// takes. Never rendered raw; see [label].
  final String sessionId;

  final String? deviceName;
  final String? deviceType;
  final String? platform;
  final String? appVersion;
  final String? ipAddress;

  /// Last time this device talked to the backend (absolute timestamp).
  final DateTime? lastActivityAt;

  /// When the device signed in.
  final DateTime? createdAt;
  final DateTime? expiresAt;

  /// A row without an id can neither be shown nor revoked, so it is not a
  /// usable session.
  bool get isValid => sessionId.trim().isNotEmpty;

  /// Human name for the device.
  ///
  /// Falls back through the metadata the backend does have (name → type →
  /// platform → a shortened id), so the row is always identifiable and the raw
  /// session id is only used when nothing better exists.
  String get label {
    final name = deviceName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final type = deviceType?.trim();
    if (type != null && type.isNotEmpty) return type;
    final platformName = platform?.trim();
    if (platformName != null && platformName.isNotEmpty) return platformName;
    final short = sessionId.trim();
    return short.length <= 8
        ? 'Device $short'
        : 'Device ${short.substring(0, 8)}';
  }

  /// Secondary line: platform and app version, or an honest gap notice.
  String get detail {
    final parts = <String>[
      if (platform?.trim().isNotEmpty ?? false) platform!.trim(),
      if (appVersion?.trim().isNotEmpty ?? false) 'v${appVersion!.trim()}',
    ];
    return parts.isEmpty ? 'Device details unavailable' : parts.join(' · ');
  }

  static DeviceSession fromJson(Map<String, dynamic> json) => DeviceSession(
        sessionId: _text(json['session_id']) ?? '',
        deviceName: _text(json['device_name']),
        deviceType: _text(json['device_type']),
        platform: _text(json['platform']),
        appVersion: _text(json['app_version']),
        ipAddress: _text(json['ip_address']),
        lastActivityAt: _parseDate(json['last_activity_at']),
        createdAt: _parseDate(json['created_at']),
        expiresAt: _parseDate(json['expires_at']),
      );

  /// Parses the `{sessions: [...]}` envelope (or a bare list) into usable rows.
  ///
  /// Anything that is not a map, or has no session id, is skipped: the screen
  /// must never render a device it cannot act on.
  static List<DeviceSession> listFrom(Object? data) {
    final raw = data is Map ? data['sessions'] : data;
    if (raw is! List) return const [];
    final sessions = <DeviceSession>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final session = DeviceSession.fromJson(
        row.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (session.isValid) sessions.add(session);
    }
    return sessions;
  }

  static String? _text(Object? raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();
    return value.isEmpty ? null : value;
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw == null) return null;
    final value = raw.toString().trim();
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceSession &&
      other.sessionId == sessionId &&
      other.deviceName == deviceName &&
      other.deviceType == deviceType &&
      other.platform == platform &&
      other.appVersion == appVersion &&
      other.ipAddress == ipAddress &&
      other.lastActivityAt == lastActivityAt &&
      other.createdAt == createdAt &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(
        sessionId,
        deviceName,
        deviceType,
        platform,
        appVersion,
        ipAddress,
        lastActivityAt,
        createdAt,
        expiresAt,
      );
}