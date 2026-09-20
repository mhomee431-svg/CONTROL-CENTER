// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Hyperlocal Shopkeeper';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get accountFallbackTitle => 'Your account';

  @override
  String get accountNoBusinessLinked => 'No business linked yet';

  @override
  String settingsIdentitySubtitle(String shopName, String membership) {
    return '$shopName - $membership';
  }

  @override
  String get roleOwner => 'Owner';

  @override
  String get roleManager => 'Manager';

  @override
  String get settingsGroupAccount => 'Account';

  @override
  String get settingsMyProfile => 'My profile';

  @override
  String get settingsMyProfileFallback => 'Name, e-mail and photo';

  @override
  String get settingsShopProfile => 'Shop profile';

  @override
  String get settingsShopNotEstablished => 'Not established yet';

  @override
  String get settingsLogout => 'Logout';

  @override
  String get settingsLogoutSubtitle => 'Sign out of this device';

  @override
  String get settingsGroupSecurity => 'Security';

  @override
  String get settingsSecurityFootnote =>
      'Sign-in is verified by Google, and the session list is read from the server — so it shows what is really signed in.';

  @override
  String get settingsAuthentication => 'Authentication';

  @override
  String get settingsAuthenticationSubtitle =>
      'Sign-in method, account status and safety';

  @override
  String get settingsSessionsDevices => 'Sessions & devices';

  @override
  String get settingsSessionsDevicesSubtitle =>
      'Every device signed in to this account';

  @override
  String get settingsGroupApp => 'App';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsNotificationsSubtitle =>
      'Delivery, categories and permissions';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSubtitle => 'Light, dark or follow this device';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSubtitle => 'App language for this device';

  @override
  String get settingsDataStorage => 'Data & storage';

  @override
  String get settingsDataStorageSubtitle => 'What is kept on this device';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAboutSubtitle => 'Version, licences and credits';

  @override
  String get settingsGroupLegal => 'Legal';

  @override
  String get settingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get settingsPrivacyPolicySubtitle => 'What we collect and why';

  @override
  String get settingsTerms => 'Terms & Conditions';

  @override
  String get settingsTermsSubtitle => 'The agreement for using Passly Business';

  @override
  String get settingsGroupSupport => 'Support';

  @override
  String get settingsHelpCenter => 'Help Center';

  @override
  String get settingsHelpCenterSubtitle => 'Guides and ways to reach the team';

  @override
  String get settingsFaqs => 'FAQs';

  @override
  String get settingsFaqsSubtitle => 'Answers to the most common questions';

  @override
  String get settingsContactSupport => 'Contact Support';

  @override
  String get settingsContactSupportSubtitle => 'Message the support team';

  @override
  String get settingsReportIssue => 'Report Issue';

  @override
  String get settingsReportIssueSubtitle => 'Tell us what went wrong';

  @override
  String get settingsBusinessPointerTitle => 'Looking for your businesses?';

  @override
  String get settingsBusinessPointerMessage =>
      'Shop settings, holidays and switching between shops belong to the Account tab — they change shop data, not your account or this app.';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageIntroTitle => 'App language';

  @override
  String get languageIntroSubtitle => 'Applies to this device only';

  @override
  String get languageGroupAvailable => 'Available now';

  @override
  String get languageFootnote =>
      'A language appears here only once its translations are complete — the app never shows a half-translated screen.';

  @override
  String get languageCurrentDescription => 'Currently used by the app';

  @override
  String languageUseDescription(String language) {
    return 'Use $language for the app';
  }

  @override
  String get languageGroupComingSoon => 'Coming soon';

  @override
  String get languageComingSoon => 'Coming soon';

  @override
  String get languageNotTranslated => 'Not translated yet';

  @override
  String get languagePhoneNoticeTitle =>
      'Your phone\'s language is not used yet';

  @override
  String get languagePhoneNoticeMessage =>
      'Passly Business follows the language chosen here, not your phone\'s system setting. Alert text keeps the wording the backend sent it with, so an English alert stays English.';

  @override
  String get appSettingsTitle => 'App settings';

  @override
  String get appSettingsIntroTitle => 'Appearance';

  @override
  String get appSettingsIntroSubtitle => 'Applies to this device only';

  @override
  String get appSettingsGroupTheme => 'Theme';

  @override
  String get appSettingsThemeFootnote =>
      'Kept on this device and left unchanged when you log out.';

  @override
  String get themeFollowDevice => 'Follow device';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeFollowDeviceDescription =>
      'Switch with your phone\'s light / dark setting';

  @override
  String get themeLightDescription => 'Always use the light theme';

  @override
  String get themeDarkDescription => 'Always use the dark theme';

  @override
  String get appSettingsLanguageLink => 'App language';

  @override
  String get appSettingsGroupLanguage => 'Language';

  @override
  String get dataStorageTitle => 'Data & storage';

  @override
  String get dataStorageIntroTitle => 'On this device';

  @override
  String get dataStorageIntroSubtitle =>
      'What Passly keeps locally, and nothing more';

  @override
  String get dataStorageGroupStored => 'Stored locally';

  @override
  String get dataStorageTokens => 'Sign-in tokens & session';

  @override
  String get dataStorageTokensSubtitle => 'Encrypted in the device keychain';

  @override
  String get dataStorageEncrypted => 'Encrypted';

  @override
  String get dataStoragePreferences => 'Delivery preferences';

  @override
  String get dataStorageUsingDefaults => 'Using the defaults';

  @override
  String get dataStorageSavedForAccount => 'Saved for this account';

  @override
  String get dataStorageDefaults => 'Defaults';

  @override
  String get dataStorageSaved => 'Saved';

  @override
  String get dataStorageAppearance => 'Appearance & language';

  @override
  String dataStorageAppearanceSubtitle(String theme, String language) {
    return '$theme · $language';
  }

  @override
  String get dataStorageResetPreferences => 'Reset delivery preferences';

  @override
  String get dataStorageResetting => 'Resetting…';

  @override
  String get dataStorageResetDialogTitle => 'Reset delivery preferences?';

  @override
  String get dataStorageResetDialogContent =>
      'Push, e-mail and SMS choices go back to their defaults. Nothing else on your account changes.';

  @override
  String get dataStorageResetAction => 'Reset';

  @override
  String get dataStorageResetSuccess =>
      'Delivery preferences reset to their defaults.';

  @override
  String get dataStorageResetFailure =>
      'Could not reset the saved preferences.';

  @override
  String get dataStorageGroupDevice => 'Device & sessions';

  @override
  String get dataStorageSessionsSubtitle => 'Where you are signed in';

  @override
  String get dataStorageNothingOfflineTitle => 'Nothing offline to clear';

  @override
  String get dataStorageNothingOfflineMessage =>
      'Products, stock, offers and alerts are read from the server every time, so the app keeps no offline copy that could go stale. Removing sign-in tokens is exactly what Log out does — it is not a second, separate reset.';

  @override
  String get sessionsLoadFailure => 'Could not load your active devices.';

  @override
  String get sessionsEmptyTitle => 'No device sessions recorded';

  @override
  String get sessionsEmptyMessage =>
      'This account signs in with Google, so the session is managed by Google rather than stored as a Passly device session. Logging out from Settings still ends it on this device.';

  @override
  String get sessionsIntroTitle => 'Where you are signed in';

  @override
  String get sessionsIntroSubtitle =>
      'Devices with an active Passly Business session';

  @override
  String get sessionsGroupThisDevice => 'This device';

  @override
  String get sessionsGroupOtherDevices => 'Other devices';

  @override
  String get sessionsNoOtherDevices => 'No other devices';

  @override
  String get sessionsNoOtherDevicesSubtitle =>
      'Only this device is signed in right now.';

  @override
  String get sessionsThisDevice => 'This device';

  @override
  String get sessionsNoticeTitle =>
      'Signing a device out takes effect immediately';

  @override
  String get sessionsNoticeMessage =>
      'The device is returned to the sign-in screen the next time it reaches Passly. To end THIS session, use Log out in Settings — that also erases the saved tokens on this phone.';

  @override
  String get sessionsRevokeTitle => 'Sign out this device?';

  @override
  String sessionsRevokeMessage(String label) {
    return '$label will need to sign in again. This device stays signed in.';
  }

  @override
  String get sessionsRevokeAction => 'Sign out';

  @override
  String sessionFallbackLabel(String id) {
    return 'Device $id';
  }

  @override
  String get sessionDetailsUnavailable => 'Device details unavailable';

  @override
  String sessionVersion(String version) {
    return 'v$version';
  }

  @override
  String sessionLastUsed(String stamp) {
    return 'Last used $stamp';
  }

  @override
  String sessionSignedInAt(String stamp) {
    return 'Signed in $stamp';
  }

  @override
  String get sessionActivityUnknown => 'Activity time unknown';

  @override
  String sessionIp(String address) {
    return 'IP $address';
  }
}
