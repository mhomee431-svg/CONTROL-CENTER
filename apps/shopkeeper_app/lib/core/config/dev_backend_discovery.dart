import 'package:dio/dio.dart';

import 'env_config.dart';

/// Development-mode backend auto-discovery.
///
/// Problem this solves
/// -------------------
/// Plain `flutter run` (without `--dart-define=SHOPKEEPER_API_BASE_URL=…`)
/// embeds the emulator-only `http://10.0.2.2:8000` default, which a physical
/// device can never reach → every API call hangs until timeout.
///
/// Solution
/// --------
/// In development builds (never in release) we probe a short list of
/// candidate backends at startup and use the first one that answers `/health`:
///
///  1. The developer's PC LAN IP (Wi-Fi direct — the most reliable path).
///  2. `127.0.0.1` (works when an `adb reverse tcp:8000 tcp:8000` tunnel is up).
///  3. `10.0.2.2` (Android emulator host loopback).
///
/// The winning URL is cached for the lifetime of the process, so this costs
/// at most a couple of short-lived HTTP GETs at startup.
class DevBackendDiscovery {
  DevBackendDiscovery._();

  /// Runtime override applied to [EnvConfig.apiBaseUrl] once discovery picks
  /// a reachable backend. `null` → keep the build-time default.
  static String? resolvedBaseUrl;

  /// Dart-define override for the PC's LAN IP (build-machine dependent).
  static const String _lanIp = String.fromEnvironment(
    'SHOPKEEPER_DEV_LAN_IP',
    defaultValue: '192.168.31.31',
  );

  /// Ordered candidate base URLs — most reliable first.
  static List<String> get candidates => [
        'http://$_lanIp:8000', // Wi-Fi direct to the dev PC (fastest, stable)
        'http://127.0.0.1:8000', // adb reverse tunnel (USB)
        'http://10.0.2.2:8000', // Android emulator host loopback
      ];

  /// True when discovery should run: development builds WITHOUT an explicit
  /// build-time base URL (an explicit override is always authoritative).
  static bool get shouldRun =>
      !EnvConfig.isProduction && EnvConfig.explicitApiBaseUrl.isEmpty;

  /// Probes [candidates] and stores the first reachable backend.
  ///
  /// Every probe is a 2-second `/health` GET — worst case the whole discovery
  /// finishes in ~6s (only when NOTHING is reachable, which itself is the
  /// signal that the backend isn't running).
  static Future<void> discover() async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      responseType: ResponseType.json,
    ));

    for (final url in candidates) {
      try {
        final response = await dio.get<Object?>('$url/health');
        if (response.statusCode == 200) {
          resolvedBaseUrl = url;
          return;
        }
      } on DioException {
        // Unreachable candidate — try the next one.
      } catch (_) {
        // Malformed response etc. — still try the next candidate.
      }
    }
    // Nothing reachable: leave [resolvedBaseUrl] null so the app falls back
    // to the build-time default and surfaces the normal timeout errors.
  }
}
