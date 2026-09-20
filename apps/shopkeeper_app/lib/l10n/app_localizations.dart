import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Hyperlocal Shopkeeper'**
  String get appTitle;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @accountFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get accountFallbackTitle;

  /// No description provided for @accountNoBusinessLinked.
  ///
  /// In en, this message translates to:
  /// **'No business linked yet'**
  String get accountNoBusinessLinked;

  /// No description provided for @settingsIdentitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'{shopName} - {membership}'**
  String settingsIdentitySubtitle(String shopName, String membership);

  /// No description provided for @roleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get roleOwner;

  /// No description provided for @roleManager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get roleManager;

  /// No description provided for @settingsGroupAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsGroupAccount;

  /// No description provided for @settingsMyProfile.
  ///
  /// In en, this message translates to:
  /// **'My profile'**
  String get settingsMyProfile;

  /// No description provided for @settingsMyProfileFallback.
  ///
  /// In en, this message translates to:
  /// **'Name, e-mail and photo'**
  String get settingsMyProfileFallback;

  /// No description provided for @settingsShopProfile.
  ///
  /// In en, this message translates to:
  /// **'Shop profile'**
  String get settingsShopProfile;

  /// No description provided for @settingsShopNotEstablished.
  ///
  /// In en, this message translates to:
  /// **'Not established yet'**
  String get settingsShopNotEstablished;

  /// No description provided for @settingsLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get settingsLogout;

  /// No description provided for @settingsLogoutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out of this device'**
  String get settingsLogoutSubtitle;

  /// No description provided for @settingsGroupSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsGroupSecurity;

  /// No description provided for @settingsSecurityFootnote.
  ///
  /// In en, this message translates to:
  /// **'Sign-in is verified by Google, and the session list is read from the server — so it shows what is really signed in.'**
  String get settingsSecurityFootnote;

  /// No description provided for @settingsAuthentication.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get settingsAuthentication;

  /// No description provided for @settingsAuthenticationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign-in method, account status and safety'**
  String get settingsAuthenticationSubtitle;

  /// No description provided for @settingsSessionsDevices.
  ///
  /// In en, this message translates to:
  /// **'Sessions & devices'**
  String get settingsSessionsDevices;

  /// No description provided for @settingsSessionsDevicesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every device signed in to this account'**
  String get settingsSessionsDevicesSubtitle;

  /// No description provided for @settingsGroupApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsGroupApp;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsNotificationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery, categories and permissions'**
  String get settingsNotificationsSubtitle;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Light, dark or follow this device'**
  String get settingsThemeSubtitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'App language for this device'**
  String get settingsLanguageSubtitle;

  /// No description provided for @settingsDataStorage.
  ///
  /// In en, this message translates to:
  /// **'Data & storage'**
  String get settingsDataStorage;

  /// No description provided for @settingsDataStorageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What is kept on this device'**
  String get settingsDataStorageSubtitle;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsAboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Version, licences and credits'**
  String get settingsAboutSubtitle;

  /// No description provided for @settingsGroupLegal.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get settingsGroupLegal;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsPrivacyPolicySubtitle.
  ///
  /// In en, this message translates to:
  /// **'What we collect and why'**
  String get settingsPrivacyPolicySubtitle;

  /// No description provided for @settingsTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get settingsTerms;

  /// No description provided for @settingsTermsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The agreement for using Passly Business'**
  String get settingsTermsSubtitle;

  /// No description provided for @settingsGroupSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get settingsGroupSupport;

  /// No description provided for @settingsHelpCenter.
  ///
  /// In en, this message translates to:
  /// **'Help Center'**
  String get settingsHelpCenter;

  /// No description provided for @settingsHelpCenterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Guides and ways to reach the team'**
  String get settingsHelpCenterSubtitle;

  /// No description provided for @settingsFaqs.
  ///
  /// In en, this message translates to:
  /// **'FAQs'**
  String get settingsFaqs;

  /// No description provided for @settingsFaqsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Answers to the most common questions'**
  String get settingsFaqsSubtitle;

  /// No description provided for @settingsContactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get settingsContactSupport;

  /// No description provided for @settingsContactSupportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Message the support team'**
  String get settingsContactSupportSubtitle;

  /// No description provided for @settingsReportIssue.
  ///
  /// In en, this message translates to:
  /// **'Report Issue'**
  String get settingsReportIssue;

  /// No description provided for @settingsReportIssueSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us what went wrong'**
  String get settingsReportIssueSubtitle;

  /// No description provided for @settingsBusinessPointerTitle.
  ///
  /// In en, this message translates to:
  /// **'Looking for your businesses?'**
  String get settingsBusinessPointerTitle;

  /// No description provided for @settingsBusinessPointerMessage.
  ///
  /// In en, this message translates to:
  /// **'Shop settings, holidays and switching between shops belong to the Account tab — they change shop data, not your account or this app.'**
  String get settingsBusinessPointerMessage;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// No description provided for @languageIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get languageIntroTitle;

  /// No description provided for @languageIntroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Applies to this device only'**
  String get languageIntroSubtitle;

  /// No description provided for @languageGroupAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available now'**
  String get languageGroupAvailable;

  /// No description provided for @languageFootnote.
  ///
  /// In en, this message translates to:
  /// **'A language appears here only once its translations are complete — the app never shows a half-translated screen.'**
  String get languageFootnote;

  /// No description provided for @languageCurrentDescription.
  ///
  /// In en, this message translates to:
  /// **'Currently used by the app'**
  String get languageCurrentDescription;

  /// No description provided for @languageUseDescription.
  ///
  /// In en, this message translates to:
  /// **'Use {language} for the app'**
  String languageUseDescription(String language);

  /// No description provided for @languageGroupComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get languageGroupComingSoon;

  /// No description provided for @languageComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get languageComingSoon;

  /// No description provided for @languageNotTranslated.
  ///
  /// In en, this message translates to:
  /// **'Not translated yet'**
  String get languageNotTranslated;

  /// No description provided for @languagePhoneNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Your phone\'s language is not used yet'**
  String get languagePhoneNoticeTitle;

  /// No description provided for @languagePhoneNoticeMessage.
  ///
  /// In en, this message translates to:
  /// **'Passly Business follows the language chosen here, not your phone\'s system setting. Alert text keeps the wording the backend sent it with, so an English alert stays English.'**
  String get languagePhoneNoticeMessage;

  /// No description provided for @appSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'App settings'**
  String get appSettingsTitle;

  /// No description provided for @appSettingsIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appSettingsIntroTitle;

  /// No description provided for @appSettingsIntroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Applies to this device only'**
  String get appSettingsIntroSubtitle;

  /// No description provided for @appSettingsGroupTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get appSettingsGroupTheme;

  /// No description provided for @appSettingsThemeFootnote.
  ///
  /// In en, this message translates to:
  /// **'Kept on this device and left unchanged when you log out.'**
  String get appSettingsThemeFootnote;

  /// No description provided for @themeFollowDevice.
  ///
  /// In en, this message translates to:
  /// **'Follow device'**
  String get themeFollowDevice;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeFollowDeviceDescription.
  ///
  /// In en, this message translates to:
  /// **'Switch with your phone\'s light / dark setting'**
  String get themeFollowDeviceDescription;

  /// No description provided for @themeLightDescription.
  ///
  /// In en, this message translates to:
  /// **'Always use the light theme'**
  String get themeLightDescription;

  /// No description provided for @themeDarkDescription.
  ///
  /// In en, this message translates to:
  /// **'Always use the dark theme'**
  String get themeDarkDescription;

  /// No description provided for @appSettingsLanguageLink.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get appSettingsLanguageLink;

  /// No description provided for @appSettingsGroupLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get appSettingsGroupLanguage;

  /// No description provided for @dataStorageTitle.
  ///
  /// In en, this message translates to:
  /// **'Data & storage'**
  String get dataStorageTitle;

  /// No description provided for @dataStorageIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get dataStorageIntroTitle;

  /// No description provided for @dataStorageIntroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What Passly keeps locally, and nothing more'**
  String get dataStorageIntroSubtitle;

  /// No description provided for @dataStorageGroupStored.
  ///
  /// In en, this message translates to:
  /// **'Stored locally'**
  String get dataStorageGroupStored;

  /// No description provided for @dataStorageTokens.
  ///
  /// In en, this message translates to:
  /// **'Sign-in tokens & session'**
  String get dataStorageTokens;

  /// No description provided for @dataStorageTokensSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypted in the device keychain'**
  String get dataStorageTokensSubtitle;

  /// No description provided for @dataStorageEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Encrypted'**
  String get dataStorageEncrypted;

  /// No description provided for @dataStoragePreferences.
  ///
  /// In en, this message translates to:
  /// **'Delivery preferences'**
  String get dataStoragePreferences;

  /// No description provided for @dataStorageUsingDefaults.
  ///
  /// In en, this message translates to:
  /// **'Using the defaults'**
  String get dataStorageUsingDefaults;

  /// No description provided for @dataStorageSavedForAccount.
  ///
  /// In en, this message translates to:
  /// **'Saved for this account'**
  String get dataStorageSavedForAccount;

  /// No description provided for @dataStorageDefaults.
  ///
  /// In en, this message translates to:
  /// **'Defaults'**
  String get dataStorageDefaults;

  /// No description provided for @dataStorageSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get dataStorageSaved;

  /// No description provided for @dataStorageAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance & language'**
  String get dataStorageAppearance;

  /// No description provided for @dataStorageAppearanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{theme} · {language}'**
  String dataStorageAppearanceSubtitle(String theme, String language);

  /// No description provided for @dataStorageResetPreferences.
  ///
  /// In en, this message translates to:
  /// **'Reset delivery preferences'**
  String get dataStorageResetPreferences;

  /// No description provided for @dataStorageResetting.
  ///
  /// In en, this message translates to:
  /// **'Resetting…'**
  String get dataStorageResetting;

  /// No description provided for @dataStorageResetDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset delivery preferences?'**
  String get dataStorageResetDialogTitle;

  /// No description provided for @dataStorageResetDialogContent.
  ///
  /// In en, this message translates to:
  /// **'Push, e-mail and SMS choices go back to their defaults. Nothing else on your account changes.'**
  String get dataStorageResetDialogContent;

  /// No description provided for @dataStorageResetAction.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get dataStorageResetAction;

  /// No description provided for @dataStorageResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Delivery preferences reset to their defaults.'**
  String get dataStorageResetSuccess;

  /// No description provided for @dataStorageResetFailure.
  ///
  /// In en, this message translates to:
  /// **'Could not reset the saved preferences.'**
  String get dataStorageResetFailure;

  /// No description provided for @dataStorageGroupDevice.
  ///
  /// In en, this message translates to:
  /// **'Device & sessions'**
  String get dataStorageGroupDevice;

  /// No description provided for @dataStorageSessionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Where you are signed in'**
  String get dataStorageSessionsSubtitle;

  /// No description provided for @dataStorageNothingOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing offline to clear'**
  String get dataStorageNothingOfflineTitle;

  /// No description provided for @dataStorageNothingOfflineMessage.
  ///
  /// In en, this message translates to:
  /// **'Products, stock, offers and alerts are read from the server every time, so the app keeps no offline copy that could go stale. Removing sign-in tokens is exactly what Log out does — it is not a second, separate reset.'**
  String get dataStorageNothingOfflineMessage;

  /// No description provided for @sessionsLoadFailure.
  ///
  /// In en, this message translates to:
  /// **'Could not load your active devices.'**
  String get sessionsLoadFailure;

  /// No description provided for @sessionsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No device sessions recorded'**
  String get sessionsEmptyTitle;

  /// No description provided for @sessionsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'This account signs in with Google, so the session is managed by Google rather than stored as a Passly device session. Logging out from Settings still ends it on this device.'**
  String get sessionsEmptyMessage;

  /// No description provided for @sessionsIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Where you are signed in'**
  String get sessionsIntroTitle;

  /// No description provided for @sessionsIntroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Devices with an active Passly Business session'**
  String get sessionsIntroSubtitle;

  /// No description provided for @sessionsGroupThisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get sessionsGroupThisDevice;

  /// No description provided for @sessionsGroupOtherDevices.
  ///
  /// In en, this message translates to:
  /// **'Other devices'**
  String get sessionsGroupOtherDevices;

  /// No description provided for @sessionsNoOtherDevices.
  ///
  /// In en, this message translates to:
  /// **'No other devices'**
  String get sessionsNoOtherDevices;

  /// No description provided for @sessionsNoOtherDevicesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only this device is signed in right now.'**
  String get sessionsNoOtherDevicesSubtitle;

  /// No description provided for @sessionsThisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get sessionsThisDevice;

  /// No description provided for @sessionsNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Signing a device out takes effect immediately'**
  String get sessionsNoticeTitle;

  /// No description provided for @sessionsNoticeMessage.
  ///
  /// In en, this message translates to:
  /// **'The device is returned to the sign-in screen the next time it reaches Passly. To end THIS session, use Log out in Settings — that also erases the saved tokens on this phone.'**
  String get sessionsNoticeMessage;

  /// No description provided for @sessionsRevokeTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out this device?'**
  String get sessionsRevokeTitle;

  /// No description provided for @sessionsRevokeMessage.
  ///
  /// In en, this message translates to:
  /// **'{label} will need to sign in again. This device stays signed in.'**
  String sessionsRevokeMessage(String label);

  /// No description provided for @sessionsRevokeAction.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get sessionsRevokeAction;

  /// No description provided for @sessionFallbackLabel.
  ///
  /// In en, this message translates to:
  /// **'Device {id}'**
  String sessionFallbackLabel(String id);

  /// No description provided for @sessionDetailsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Device details unavailable'**
  String get sessionDetailsUnavailable;

  /// No description provided for @sessionVersion.
  ///
  /// In en, this message translates to:
  /// **'v{version}'**
  String sessionVersion(String version);

  /// No description provided for @sessionLastUsed.
  ///
  /// In en, this message translates to:
  /// **'Last used {stamp}'**
  String sessionLastUsed(String stamp);

  /// No description provided for @sessionSignedInAt.
  ///
  /// In en, this message translates to:
  /// **'Signed in {stamp}'**
  String sessionSignedInAt(String stamp);

  /// No description provided for @sessionActivityUnknown.
  ///
  /// In en, this message translates to:
  /// **'Activity time unknown'**
  String get sessionActivityUnknown;

  /// No description provided for @sessionIp.
  ///
  /// In en, this message translates to:
  /// **'IP {address}'**
  String sessionIp(String address);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
