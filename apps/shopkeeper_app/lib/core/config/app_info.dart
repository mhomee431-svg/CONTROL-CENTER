/// Static facts about the app, used by the About screen and by issue reports.
///
/// Kept as constants because the app has no `package_info_plus` dependency:
/// bump [version] / [build] together with `version:` in `pubspec.yaml`.
abstract final class AppInfo {
  AppInfo._();

  static const String name = 'Passly Business';
  static const String tagline = 'Shopkeeper console for local businesses';
  static const String version = '1.0.0';
  static const String build = '1';

  static const String versionLabel = 'v$version (build $build)';
}