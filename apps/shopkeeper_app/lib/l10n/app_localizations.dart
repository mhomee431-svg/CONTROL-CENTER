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

  /// No description provided for @msgNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get msgNotSignedIn;

  /// No description provided for @msgNoShopSelected.
  ///
  /// In en, this message translates to:
  /// **'No shop selected'**
  String get msgNoShopSelected;

  /// No description provided for @msgSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get msgSessionExpired;

  /// No description provided for @msgNoInternet.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Check your network and retry.'**
  String get msgNoInternet;

  /// No description provided for @formProductNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Product name is required'**
  String get formProductNameRequired;

  /// No description provided for @formSellingPriceRequired.
  ///
  /// In en, this message translates to:
  /// **'Selling price is required'**
  String get formSellingPriceRequired;

  /// No description provided for @formEnterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get formEnterValidAmount;

  /// No description provided for @formPriceCannotBeNegative.
  ///
  /// In en, this message translates to:
  /// **'Price cannot be negative'**
  String get formPriceCannotBeNegative;

  /// No description provided for @formMrpCannotBeNegative.
  ///
  /// In en, this message translates to:
  /// **'MRP cannot be negative'**
  String get formMrpCannotBeNegative;

  /// No description provided for @formMrpBelowPrice.
  ///
  /// In en, this message translates to:
  /// **'MRP cannot be lower than the selling price'**
  String get formMrpBelowPrice;

  /// No description provided for @formWholeNumberRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number'**
  String get formWholeNumberRequired;

  /// No description provided for @formQuantityCannotBeNegative.
  ///
  /// In en, this message translates to:
  /// **'Quantity cannot be negative'**
  String get formQuantityCannotBeNegative;

  /// No description provided for @formBarcodeTooShort.
  ///
  /// In en, this message translates to:
  /// **'Barcode must be at least {count} characters'**
  String formBarcodeTooShort(int count);

  /// No description provided for @formTooManyCharacters.
  ///
  /// In en, this message translates to:
  /// **'Use at most {count} characters'**
  String formTooManyCharacters(int count);

  /// No description provided for @dashLabel.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get dashLabel;

  /// No description provided for @notUpdatedYet.
  ///
  /// In en, this message translates to:
  /// **'Not updated yet'**
  String get notUpdatedYet;

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String timeMinutesAgo(int count);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} h ago'**
  String timeHoursAgo(int count);

  /// No description provided for @timeYesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'Yesterday {time}'**
  String timeYesterdayAt(String time);

  /// No description provided for @patternTime.
  ///
  /// In en, this message translates to:
  /// **'HH:mm'**
  String get patternTime;

  /// No description provided for @patternDateShort.
  ///
  /// In en, this message translates to:
  /// **'d MMM yyyy'**
  String get patternDateShort;

  /// No description provided for @patternDateTimeThisYear.
  ///
  /// In en, this message translates to:
  /// **'d MMM, HH:mm'**
  String get patternDateTimeThisYear;

  /// No description provided for @patternDateTimeFull.
  ///
  /// In en, this message translates to:
  /// **'d MMM yyyy, HH:mm'**
  String get patternDateTimeFull;

  /// No description provided for @freshnessPrefixInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory updated'**
  String get freshnessPrefixInventory;

  /// No description provided for @freshnessPrefixPrice.
  ///
  /// In en, this message translates to:
  /// **'Price updated'**
  String get freshnessPrefixPrice;

  /// No description provided for @freshnessPrefixPosSync.
  ///
  /// In en, this message translates to:
  /// **'Last POS sync'**
  String get freshnessPrefixPosSync;

  /// No description provided for @freshnessJustNow.
  ///
  /// In en, this message translates to:
  /// **'{prefix} just now'**
  String freshnessJustNow(String prefix);

  /// No description provided for @freshnessMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{prefix} {count} min ago'**
  String freshnessMinutesAgo(String prefix, int count);

  /// No description provided for @freshnessToday.
  ///
  /// In en, this message translates to:
  /// **'{prefix} today'**
  String freshnessToday(String prefix);

  /// No description provided for @freshnessYesterday.
  ///
  /// In en, this message translates to:
  /// **'{prefix} yesterday'**
  String freshnessYesterday(String prefix);

  /// No description provided for @freshnessOnDate.
  ///
  /// In en, this message translates to:
  /// **'{prefix} {date}'**
  String freshnessOnDate(String prefix, String date);

  /// No description provided for @inventoryNotUpdatedYet.
  ///
  /// In en, this message translates to:
  /// **'Inventory not updated yet'**
  String get inventoryNotUpdatedYet;

  /// No description provided for @priceNotUpdatedYet.
  ///
  /// In en, this message translates to:
  /// **'Price not updated yet'**
  String get priceNotUpdatedYet;

  /// No description provided for @noPosSyncYet.
  ///
  /// In en, this message translates to:
  /// **'No POS sync yet'**
  String get noPosSyncYet;

  /// No description provided for @connectivityBannerReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get connectivityBannerReconnecting;

  /// No description provided for @connectivityBannerRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get connectivityBannerRetry;

  /// No description provided for @aboutScreenConnectYourBillingSoftwareAnd.
  ///
  /// In en, this message translates to:
  /// **'Connect your billing software and pull bill items'**
  String get aboutScreenConnectYourBillingSoftwareAnd;

  /// No description provided for @aboutScreenImportAWholeCatalogueWith.
  ///
  /// In en, this message translates to:
  /// **'Import a whole catalogue with a preview first'**
  String get aboutScreenImportAWholeCatalogueWith;

  /// No description provided for @aboutScreenPasslyBusinessForShopkeepers.
  ///
  /// In en, this message translates to:
  /// **'Passly Business, for shopkeepers'**
  String get aboutScreenPasslyBusinessForShopkeepers;

  /// No description provided for @aboutScreenPriceListsDiscountsAndPrice.
  ///
  /// In en, this message translates to:
  /// **'Price lists, discounts and price history'**
  String get aboutScreenPriceListsDiscountsAndPrice;

  /// No description provided for @aboutScreenProductsBarcodeScanningStockAnd.
  ///
  /// In en, this message translates to:
  /// **'Products, barcode scanning, stock and freshness'**
  String get aboutScreenProductsBarcodeScanningStockAnd;

  /// No description provided for @aboutScreenVersionLabelPassly.
  ///
  /// In en, this message translates to:
  /// **'{versionLabel} - Passly'**
  String aboutScreenVersionLabelPassly(Object versionLabel);

  /// No description provided for @aboutScreenViewsClicksAndWhatCustomers.
  ///
  /// In en, this message translates to:
  /// **'Views, clicks and what customers searched for'**
  String get aboutScreenViewsClicksAndWhatCustomers;

  /// No description provided for @accountScreenAccountSecurityAppLegalAnd.
  ///
  /// In en, this message translates to:
  /// **'Account, security, app, legal and support'**
  String get accountScreenAccountSecurityAppLegalAnd;

  /// No description provided for @accountScreenHyperlocalShopkeeperV100.
  ///
  /// In en, this message translates to:
  /// **'Hyperlocal Shopkeeper v1.0.0'**
  String get accountScreenHyperlocalShopkeeperV100;

  /// No description provided for @accountScreenValueStatusValue2.
  ///
  /// In en, this message translates to:
  /// **'{value} · {status}{value2}'**
  String accountScreenValueStatusValue2(
    Object value,
    Object status,
    Object value2,
  );

  /// No description provided for @accountSettingsScreenAnswersToTheMostCommon.
  ///
  /// In en, this message translates to:
  /// **'Answers to the most common questions'**
  String get accountSettingsScreenAnswersToTheMostCommon;

  /// No description provided for @accountSettingsScreenAppLanguageForThisDevice.
  ///
  /// In en, this message translates to:
  /// **'App language for this device'**
  String get accountSettingsScreenAppLanguageForThisDevice;

  /// No description provided for @accountSettingsScreenDeliveryCategoriesAndPermissions.
  ///
  /// In en, this message translates to:
  /// **'Delivery, categories and permissions'**
  String get accountSettingsScreenDeliveryCategoriesAndPermissions;

  /// No description provided for @accountSettingsScreenEveryDeviceSignedInTo.
  ///
  /// In en, this message translates to:
  /// **'Every device signed in to this account'**
  String get accountSettingsScreenEveryDeviceSignedInTo;

  /// No description provided for @accountSettingsScreenGuidesAndWaysToReach.
  ///
  /// In en, this message translates to:
  /// **'Guides and ways to reach the team'**
  String get accountSettingsScreenGuidesAndWaysToReach;

  /// No description provided for @accountSettingsScreenLightDarkOrFollowThis.
  ///
  /// In en, this message translates to:
  /// **'Light, dark or follow this device'**
  String get accountSettingsScreenLightDarkOrFollowThis;

  /// No description provided for @accountSettingsScreenLookingForYourBusinesses.
  ///
  /// In en, this message translates to:
  /// **'Looking for your businesses?'**
  String get accountSettingsScreenLookingForYourBusinesses;

  /// No description provided for @accountSettingsScreenShopSettingsHolidaysAndSwitching.
  ///
  /// In en, this message translates to:
  /// **'Shop settings, holidays and switching between shops belong to the Account tab — they change shop data, not your account or this app.'**
  String get accountSettingsScreenShopSettingsHolidaysAndSwitching;

  /// No description provided for @accountSettingsScreenSignInMethodAccountStatus.
  ///
  /// In en, this message translates to:
  /// **'Sign-in method, account status and safety'**
  String get accountSettingsScreenSignInMethodAccountStatus;

  /// No description provided for @accountSettingsScreenStatusOfTheReportsYou.
  ///
  /// In en, this message translates to:
  /// **'Status of the reports you sent'**
  String get accountSettingsScreenStatusOfTheReportsYou;

  /// No description provided for @accountSettingsScreenTheAgreementForUsingPassly.
  ///
  /// In en, this message translates to:
  /// **'The agreement for using Passly Business'**
  String get accountSettingsScreenTheAgreementForUsingPassly;

  /// No description provided for @accountSettingsScreenVersionLicencesAndCredits.
  ///
  /// In en, this message translates to:
  /// **'Version, licences and credits'**
  String get accountSettingsScreenVersionLicencesAndCredits;

  /// No description provided for @accountSettingsScreenWhatIsKeptOnThis.
  ///
  /// In en, this message translates to:
  /// **'What is kept on this device'**
  String get accountSettingsScreenWhatIsKeptOnThis;

  /// No description provided for @accountStatusScreenIfYouBelieveThisIs.
  ///
  /// In en, this message translates to:
  /// **'If you believe this is a mistake, reach out to the Hyperlocal support team to reactivate your account.'**
  String get accountStatusScreenIfYouBelieveThisIs;

  /// No description provided for @allFeaturesScreenBusinessScreensOpenOnceYour.
  ///
  /// In en, this message translates to:
  /// **'Business screens open once your shop is set up.'**
  String get allFeaturesScreenBusinessScreensOpenOnceYour;

  /// No description provided for @allFeaturesScreenEachScreenShowsLiveData.
  ///
  /// In en, this message translates to:
  /// **'Each screen shows live data for your selected shop.'**
  String get allFeaturesScreenEachScreenShowsLiveData;

  /// No description provided for @allFeaturesScreenEverythingYouManageInOne.
  ///
  /// In en, this message translates to:
  /// **'Everything you manage, in one place'**
  String get allFeaturesScreenEverythingYouManageInOne;

  /// No description provided for @barcodeScannerScreenMultipleProductsShareThisBarcode.
  ///
  /// In en, this message translates to:
  /// **'Multiple products share this barcode'**
  String get barcodeScannerScreenMultipleProductsShareThisBarcode;

  /// No description provided for @barcodeScannerScreenPleaseSelectTheProductYou.
  ///
  /// In en, this message translates to:
  /// **'Please select the product you scanned:'**
  String get barcodeScannerScreenPleaseSelectTheProductYou;

  /// No description provided for @barcodeScannerScreenPositionAProductBarcodeInside.
  ///
  /// In en, this message translates to:
  /// **'Position a product barcode inside the frame — it is detected automatically.'**
  String get barcodeScannerScreenPositionAProductBarcodeInside;

  /// No description provided for @barcodeScannerScreenProductAddedToInventory.
  ///
  /// In en, this message translates to:
  /// **'Product added to inventory'**
  String get barcodeScannerScreenProductAddedToInventory;

  /// No description provided for @barcodeSheetsBarcodeBarcodeValue.
  ///
  /// In en, this message translates to:
  /// **'Barcode {barcode}{value}'**
  String barcodeSheetsBarcodeBarcodeValue(Object barcode, Object value);

  /// No description provided for @barcodeSheetsCheckTheBarcodeDigitsOr.
  ///
  /// In en, this message translates to:
  /// **'Check the barcode digits, or add the item manually — it will be created under your shop.'**
  String get barcodeSheetsCheckTheBarcodeDigitsOr;

  /// No description provided for @barcodeSheetsCouldNotSaveTheProduct.
  ///
  /// In en, this message translates to:
  /// **'Could not save the product'**
  String get barcodeSheetsCouldNotSaveTheProduct;

  /// No description provided for @barcodeSheetsEAN8UPCAEAN.
  ///
  /// In en, this message translates to:
  /// **'EAN-8, UPC-A, EAN-13 or GTIN-14 — digits only.'**
  String get barcodeSheetsEAN8UPCAEAN;

  /// No description provided for @barcodeSheetsMRPCannotBeLowerThan.
  ///
  /// In en, this message translates to:
  /// **'MRP cannot be lower than the selling price'**
  String get barcodeSheetsMRPCannotBeLowerThan;

  /// No description provided for @barcodeSheetsNoCatalogProductMatchesBarcode.
  ///
  /// In en, this message translates to:
  /// **'No catalog product matches barcode {barcode}.'**
  String barcodeSheetsNoCatalogProductMatchesBarcode(Object barcode);

  /// No description provided for @barcodeSheetsSellingPrice.
  ///
  /// In en, this message translates to:
  /// **'Selling price *'**
  String get barcodeSheetsSellingPrice;

  /// No description provided for @barcodeSheetsThisProductIsAlreadyIn.
  ///
  /// In en, this message translates to:
  /// **'This product is already in your inventory'**
  String get barcodeSheetsThisProductIsAlreadyIn;

  /// No description provided for @barcodeSheetsThisProductIsNotCurrently.
  ///
  /// In en, this message translates to:
  /// **'This product is not currently published in the shared catalog. You cannot list it right now.'**
  String get barcodeSheetsThisProductIsNotCurrently;

  /// No description provided for @barcodeSheetsUnpublishedProductsStayAsDrafts.
  ///
  /// In en, this message translates to:
  /// **'Unpublished products stay as drafts'**
  String get barcodeSheetsUnpublishedProductsStayAsDrafts;

  /// No description provided for @businessCategoryScreenApprovedBusinessCategories.
  ///
  /// In en, this message translates to:
  /// **'Approved business categories'**
  String get businessCategoryScreenApprovedBusinessCategories;

  /// No description provided for @businessCategoryScreenCouldNotLoadTheRequirements.
  ///
  /// In en, this message translates to:
  /// **'Could not load the requirements for this category.'**
  String get businessCategoryScreenCouldNotLoadTheRequirements;

  /// No description provided for @businessCategoryScreenNoCategorySpecificDocumentsAre.
  ///
  /// In en, this message translates to:
  /// **'No category-specific documents are required.'**
  String get businessCategoryScreenNoCategorySpecificDocumentsAre;

  /// No description provided for @businessCategoryScreenTheCategoryIsSetAt.
  ///
  /// In en, this message translates to:
  /// **'The category is set at registration and verified by the platform — changing it starts a new verification, so contact support.'**
  String get businessCategoryScreenTheCategoryIsSetAt;

  /// No description provided for @businessInfoScreenTheseDetailsComeFromYour.
  ///
  /// In en, this message translates to:
  /// **'These details come from your shop record. Use Edit shop to change the contact fields.'**
  String get businessInfoScreenTheseDetailsComeFromYour;

  /// No description provided for @common123456.
  ///
  /// In en, this message translates to:
  /// **'123456'**
  String get common123456;

  /// No description provided for @common500.
  ///
  /// In en, this message translates to:
  /// **'500'**
  String get common500;

  /// No description provided for @common6DigitCode.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get common6DigitCode;

  /// No description provided for @common6DigitPincode.
  ///
  /// In en, this message translates to:
  /// **'6-digit pincode'**
  String get common6DigitPincode;

  /// No description provided for @common9999999999.
  ///
  /// In en, this message translates to:
  /// **'99999 99999'**
  String get common9999999999;

  /// No description provided for @common99999999992.
  ///
  /// In en, this message translates to:
  /// **'9999999999'**
  String get common99999999992;

  /// No description provided for @common99999999993.
  ///
  /// In en, this message translates to:
  /// **'9999999999'**
  String get common99999999993;

  /// No description provided for @commonAPIBaseURL.
  ///
  /// In en, this message translates to:
  /// **'API base URL'**
  String get commonAPIBaseURL;

  /// No description provided for @commonAPIKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get commonAPIKey;

  /// No description provided for @commonAPISecret.
  ///
  /// In en, this message translates to:
  /// **'API secret'**
  String get commonAPISecret;

  /// No description provided for @commonAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get commonAbout;

  /// No description provided for @commonAbout2.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get commonAbout2;

  /// No description provided for @commonAcceptingOrders.
  ///
  /// In en, this message translates to:
  /// **'Accepting orders'**
  String get commonAcceptingOrders;

  /// No description provided for @commonAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Access denied'**
  String get commonAccessDenied;

  /// No description provided for @commonAccessOnThisAccount.
  ///
  /// In en, this message translates to:
  /// **'Access on this account'**
  String get commonAccessOnThisAccount;

  /// No description provided for @commonAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get commonAccount;

  /// No description provided for @commonAccount2.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get commonAccount2;

  /// No description provided for @commonAccountProtection.
  ///
  /// In en, this message translates to:
  /// **'Account protection'**
  String get commonAccountProtection;

  /// No description provided for @commonAccountSafety.
  ///
  /// In en, this message translates to:
  /// **'Account safety'**
  String get commonAccountSafety;

  /// No description provided for @commonAccountStatus.
  ///
  /// In en, this message translates to:
  /// **'Account status'**
  String get commonAccountStatus;

  /// No description provided for @commonActivateOffer.
  ///
  /// In en, this message translates to:
  /// **'Activate offer'**
  String get commonActivateOffer;

  /// No description provided for @commonActivateOffer2.
  ///
  /// In en, this message translates to:
  /// **'Activate offer'**
  String get commonActivateOffer2;

  /// No description provided for @commonActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get commonActive;

  /// No description provided for @commonActive2.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get commonActive2;

  /// No description provided for @commonActiveProducts.
  ///
  /// In en, this message translates to:
  /// **'Active products'**
  String get commonActiveProducts;

  /// No description provided for @commonActiveSession.
  ///
  /// In en, this message translates to:
  /// **'Active session'**
  String get commonActiveSession;

  /// No description provided for @commonActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get commonActivity;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonAddAHoliday.
  ///
  /// In en, this message translates to:
  /// **'Add a holiday'**
  String get commonAddAHoliday;

  /// No description provided for @commonAddATerminal.
  ///
  /// In en, this message translates to:
  /// **'Add a terminal'**
  String get commonAddATerminal;

  /// No description provided for @commonAddHoliday.
  ///
  /// In en, this message translates to:
  /// **'Add holiday'**
  String get commonAddHoliday;

  /// No description provided for @commonAddProduct.
  ///
  /// In en, this message translates to:
  /// **'Add Product'**
  String get commonAddProduct;

  /// No description provided for @commonAddProduct2.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get commonAddProduct2;

  /// No description provided for @commonAddTerminal.
  ///
  /// In en, this message translates to:
  /// **'Add terminal'**
  String get commonAddTerminal;

  /// No description provided for @commonAddToInventory.
  ///
  /// In en, this message translates to:
  /// **'Add to inventory'**
  String get commonAddToInventory;

  /// No description provided for @commonAddYourShop.
  ///
  /// In en, this message translates to:
  /// **'Add Your Shop'**
  String get commonAddYourShop;

  /// No description provided for @commonAdditionalInformation.
  ///
  /// In en, this message translates to:
  /// **'Additional information'**
  String get commonAdditionalInformation;

  /// No description provided for @commonAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get commonAddress;

  /// No description provided for @commonAdjustPin.
  ///
  /// In en, this message translates to:
  /// **'Adjust Pin'**
  String get commonAdjustPin;

  /// No description provided for @commonAlertsAndPermissions.
  ///
  /// In en, this message translates to:
  /// **'Alerts and permissions'**
  String get commonAlertsAndPermissions;

  /// No description provided for @commonAlertsTab.
  ///
  /// In en, this message translates to:
  /// **'Alerts tab'**
  String get commonAlertsTab;

  /// No description provided for @commonAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get commonAll;

  /// No description provided for @commonAll2.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get commonAll2;

  /// No description provided for @commonAll3.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get commonAll3;

  /// No description provided for @commonAllClear.
  ///
  /// In en, this message translates to:
  /// **'All clear'**
  String get commonAllClear;

  /// No description provided for @commonAllFeatures.
  ///
  /// In en, this message translates to:
  /// **'All features'**
  String get commonAllFeatures;

  /// No description provided for @commonAllFeatures2.
  ///
  /// In en, this message translates to:
  /// **'All Features'**
  String get commonAllFeatures2;

  /// No description provided for @commonAllFeatures3.
  ///
  /// In en, this message translates to:
  /// **'All features'**
  String get commonAllFeatures3;

  /// No description provided for @commonAllItemsWellStocked.
  ///
  /// In en, this message translates to:
  /// **'All items well stocked'**
  String get commonAllItemsWellStocked;

  /// No description provided for @commonAlternatePhone.
  ///
  /// In en, this message translates to:
  /// **'Alternate phone'**
  String get commonAlternatePhone;

  /// No description provided for @commonApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get commonApp;

  /// No description provided for @commonAppVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get commonAppVersion;

  /// No description provided for @commonApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// No description provided for @commonApplyManualCorrection.
  ///
  /// In en, this message translates to:
  /// **'Apply manual correction'**
  String get commonApplyManualCorrection;

  /// No description provided for @commonApplyToProducts.
  ///
  /// In en, this message translates to:
  /// **'Apply to products'**
  String get commonApplyToProducts;

  /// No description provided for @commonApplyingImport.
  ///
  /// In en, this message translates to:
  /// **'Applying import'**
  String get commonApplyingImport;

  /// No description provided for @commonApproval.
  ///
  /// In en, this message translates to:
  /// **'Approval'**
  String get commonApproval;

  /// No description provided for @commonAuthentication.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get commonAuthentication;

  /// No description provided for @commonAvailability.
  ///
  /// In en, this message translates to:
  /// **'Availability'**
  String get commonAvailability;

  /// No description provided for @commonAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get commonAvailable;

  /// No description provided for @commonAvailableForSale.
  ///
  /// In en, this message translates to:
  /// **'Available for sale'**
  String get commonAvailableForSale;

  /// No description provided for @commonAvailableToCustomers.
  ///
  /// In en, this message translates to:
  /// **'Available to customers'**
  String get commonAvailableToCustomers;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonBack2.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack2;

  /// No description provided for @commonBack3.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack3;

  /// No description provided for @commonBack4.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack4;

  /// No description provided for @commonBack5.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack5;

  /// No description provided for @commonBack6.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack6;

  /// No description provided for @commonBackToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get commonBackToHome;

  /// No description provided for @commonBackToImportCenter.
  ///
  /// In en, this message translates to:
  /// **'Back to Import Center'**
  String get commonBackToImportCenter;

  /// No description provided for @commonBackToImportCenter2.
  ///
  /// In en, this message translates to:
  /// **'Back to Import Center'**
  String get commonBackToImportCenter2;

  /// No description provided for @commonBackToIntegration.
  ///
  /// In en, this message translates to:
  /// **'Back to integration'**
  String get commonBackToIntegration;

  /// No description provided for @commonBackToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get commonBackToSignIn;

  /// No description provided for @commonBackToSignIn2.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get commonBackToSignIn2;

  /// No description provided for @commonBackToTheIntegration.
  ///
  /// In en, this message translates to:
  /// **'Back to the integration'**
  String get commonBackToTheIntegration;

  /// No description provided for @commonBackgroundSync.
  ///
  /// In en, this message translates to:
  /// **'Background sync'**
  String get commonBackgroundSync;

  /// No description provided for @commonBankVerification.
  ///
  /// In en, this message translates to:
  /// **'Bank Verification'**
  String get commonBankVerification;

  /// No description provided for @commonBarcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get commonBarcode;

  /// No description provided for @commonBarcodeOptional.
  ///
  /// In en, this message translates to:
  /// **'Barcode (optional)'**
  String get commonBarcodeOptional;

  /// No description provided for @commonBrand.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get commonBrand;

  /// No description provided for @commonBrandOptional.
  ///
  /// In en, this message translates to:
  /// **'Brand (optional)'**
  String get commonBrandOptional;

  /// No description provided for @commonBulkExcelImport.
  ///
  /// In en, this message translates to:
  /// **'Bulk Excel import'**
  String get commonBulkExcelImport;

  /// No description provided for @commonBusinessCategory.
  ///
  /// In en, this message translates to:
  /// **'Business Category'**
  String get commonBusinessCategory;

  /// No description provided for @commonBusinessCategory2.
  ///
  /// In en, this message translates to:
  /// **'Business category'**
  String get commonBusinessCategory2;

  /// No description provided for @commonBusinessDashboard.
  ///
  /// In en, this message translates to:
  /// **'Business dashboard'**
  String get commonBusinessDashboard;

  /// No description provided for @commonBusinessDescription.
  ///
  /// In en, this message translates to:
  /// **'Business Description'**
  String get commonBusinessDescription;

  /// No description provided for @commonBusinessInformation.
  ///
  /// In en, this message translates to:
  /// **'Business information'**
  String get commonBusinessInformation;

  /// No description provided for @commonBusinessInformation2.
  ///
  /// In en, this message translates to:
  /// **'Business information'**
  String get commonBusinessInformation2;

  /// No description provided for @commonBusinessInsights.
  ///
  /// In en, this message translates to:
  /// **'Business insights'**
  String get commonBusinessInsights;

  /// No description provided for @commonBusinessPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Business phone number'**
  String get commonBusinessPhoneNumber;

  /// No description provided for @commonBusinessType.
  ///
  /// In en, this message translates to:
  /// **'Business Type'**
  String get commonBusinessType;

  /// No description provided for @commonBusinessType2.
  ///
  /// In en, this message translates to:
  /// **'Business Type'**
  String get commonBusinessType2;

  /// No description provided for @commonBySource.
  ///
  /// In en, this message translates to:
  /// **'By source'**
  String get commonBySource;

  /// No description provided for @commonCallViews.
  ///
  /// In en, this message translates to:
  /// **'Call views'**
  String get commonCallViews;

  /// No description provided for @commonCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get commonCamera;

  /// No description provided for @commonCatalogReference.
  ///
  /// In en, this message translates to:
  /// **'Catalog reference'**
  String get commonCatalogReference;

  /// No description provided for @commonCatalogueAndInventory.
  ///
  /// In en, this message translates to:
  /// **'Catalogue and inventory'**
  String get commonCatalogueAndInventory;

  /// No description provided for @commonCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get commonCategory;

  /// No description provided for @commonCategory2.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get commonCategory2;

  /// No description provided for @commonCategory3.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get commonCategory3;

  /// No description provided for @commonCategoryOptional.
  ///
  /// In en, this message translates to:
  /// **'Category (optional)'**
  String get commonCategoryOptional;

  /// No description provided for @commonChangeNumber.
  ///
  /// In en, this message translates to:
  /// **'Change number'**
  String get commonChangeNumber;

  /// No description provided for @commonChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get commonChannels;

  /// No description provided for @commonChannels2.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get commonChannels2;

  /// No description provided for @commonCheckTheSyncHistory.
  ///
  /// In en, this message translates to:
  /// **'Check the sync history'**
  String get commonCheckTheSyncHistory;

  /// No description provided for @commonChooseAnExistingPhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose an existing photo'**
  String get commonChooseAnExistingPhoto;

  /// No description provided for @commonChooseAnotherFile.
  ///
  /// In en, this message translates to:
  /// **'Choose another file'**
  String get commonChooseAnotherFile;

  /// No description provided for @commonChooseAnotherProduct.
  ///
  /// In en, this message translates to:
  /// **'Choose another product'**
  String get commonChooseAnotherProduct;

  /// No description provided for @commonChooseAnotherProduct2.
  ///
  /// In en, this message translates to:
  /// **'Choose another product'**
  String get commonChooseAnotherProduct2;

  /// No description provided for @commonChooseAnotherProduct3.
  ///
  /// In en, this message translates to:
  /// **'Choose another product'**
  String get commonChooseAnotherProduct3;

  /// No description provided for @commonChooseAnotherProduct4.
  ///
  /// In en, this message translates to:
  /// **'Choose another product'**
  String get commonChooseAnotherProduct4;

  /// No description provided for @commonChooseExcelFile.
  ///
  /// In en, this message translates to:
  /// **'Choose Excel file'**
  String get commonChooseExcelFile;

  /// No description provided for @commonChooseExcelFile2.
  ///
  /// In en, this message translates to:
  /// **'Choose Excel file'**
  String get commonChooseExcelFile2;

  /// No description provided for @commonChooseLocationOnMap.
  ///
  /// In en, this message translates to:
  /// **'Choose Location on Map'**
  String get commonChooseLocationOnMap;

  /// No description provided for @commonChooseScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Choose screenshot'**
  String get commonChooseScreenshot;

  /// No description provided for @commonChooseWhatYouReceive.
  ///
  /// In en, this message translates to:
  /// **'Choose what you receive'**
  String get commonChooseWhatYouReceive;

  /// No description provided for @commonCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get commonCity;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @commonClear2.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear2;

  /// No description provided for @commonClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get commonClearFilters;

  /// No description provided for @commonClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get commonClearSearch;

  /// No description provided for @commonClearSearch2.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get commonClearSearch2;

  /// No description provided for @commonClearSearch3.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get commonClearSearch3;

  /// No description provided for @commonClicksToday.
  ///
  /// In en, this message translates to:
  /// **'Clicks today'**
  String get commonClicksToday;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonClose2.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose2;

  /// No description provided for @commonClose3.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose3;

  /// No description provided for @commonClose4.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose4;

  /// No description provided for @commonClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get commonClosed;

  /// No description provided for @commonCloses.
  ///
  /// In en, this message translates to:
  /// **'Closes'**
  String get commonCloses;

  /// No description provided for @commonClosingTime.
  ///
  /// In en, this message translates to:
  /// **'Closing Time'**
  String get commonClosingTime;

  /// No description provided for @commonCompleteYourProfile.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile'**
  String get commonCompleteYourProfile;

  /// No description provided for @commonCompliance.
  ///
  /// In en, this message translates to:
  /// **'Compliance'**
  String get commonCompliance;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get commonConfirmPassword;

  /// No description provided for @commonConfirmPassword2.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get commonConfirmPassword2;

  /// No description provided for @commonConfirmShopLocation.
  ///
  /// In en, this message translates to:
  /// **'Confirm shop location'**
  String get commonConfirmShopLocation;

  /// No description provided for @commonConfirmShopLocation2.
  ///
  /// In en, this message translates to:
  /// **'Confirm Shop Location'**
  String get commonConfirmShopLocation2;

  /// No description provided for @commonConflicts.
  ///
  /// In en, this message translates to:
  /// **'Conflicts'**
  String get commonConflicts;

  /// No description provided for @commonConnectPOS.
  ///
  /// In en, this message translates to:
  /// **'Connect POS'**
  String get commonConnectPOS;

  /// No description provided for @commonConnectionType.
  ///
  /// In en, this message translates to:
  /// **'Connection type'**
  String get commonConnectionType;

  /// No description provided for @commonConnector.
  ///
  /// In en, this message translates to:
  /// **'Connector'**
  String get commonConnector;

  /// No description provided for @commonContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get commonContact;

  /// No description provided for @commonContactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get commonContactSupport;

  /// No description provided for @commonContactSupport2.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get commonContactSupport2;

  /// No description provided for @commonContactSupport3.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get commonContactSupport3;

  /// No description provided for @commonContactSupport4.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get commonContactSupport4;

  /// No description provided for @commonContactUs.
  ///
  /// In en, this message translates to:
  /// **'Contact us'**
  String get commonContactUs;

  /// No description provided for @commonContinueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get commonContinueWithGoogle;

  /// No description provided for @commonCoordinates.
  ///
  /// In en, this message translates to:
  /// **'Coordinates'**
  String get commonCoordinates;

  /// No description provided for @commonCopyEMailAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy e-mail address'**
  String get commonCopyEMailAddress;

  /// No description provided for @commonCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get commonCopyLink;

  /// No description provided for @commonCopyPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Copy phone number'**
  String get commonCopyPhoneNumber;

  /// No description provided for @commonCopyReportInstead.
  ///
  /// In en, this message translates to:
  /// **'Copy report instead'**
  String get commonCopyReportInstead;

  /// No description provided for @commonCopyRequest.
  ///
  /// In en, this message translates to:
  /// **'Copy request'**
  String get commonCopyRequest;

  /// No description provided for @commonCopyTicketNumber.
  ///
  /// In en, this message translates to:
  /// **'Copy ticket number'**
  String get commonCopyTicketNumber;

  /// No description provided for @commonCouldNotLoadInventory.
  ///
  /// In en, this message translates to:
  /// **'Could not load inventory'**
  String get commonCouldNotLoadInventory;

  /// No description provided for @commonCouldNotLoadInventory2.
  ///
  /// In en, this message translates to:
  /// **'Could not load inventory'**
  String get commonCouldNotLoadInventory2;

  /// No description provided for @commonCouldNotLoadReports.
  ///
  /// In en, this message translates to:
  /// **'Could not load reports'**
  String get commonCouldNotLoadReports;

  /// No description provided for @commonCouldNotLoadThisShop.
  ///
  /// In en, this message translates to:
  /// **'Could not load this shop'**
  String get commonCouldNotLoadThisShop;

  /// No description provided for @commonCounter1.
  ///
  /// In en, this message translates to:
  /// **'Counter 1'**
  String get commonCounter1;

  /// No description provided for @commonCreateANewAccount.
  ///
  /// In en, this message translates to:
  /// **'Create a new account'**
  String get commonCreateANewAccount;

  /// No description provided for @commonCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get commonCreateAccount;

  /// No description provided for @commonCreateBusinessAccount.
  ///
  /// In en, this message translates to:
  /// **'Create business account'**
  String get commonCreateBusinessAccount;

  /// No description provided for @commonCreateNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Create new password'**
  String get commonCreateNewPassword;

  /// No description provided for @commonCreateOffer.
  ///
  /// In en, this message translates to:
  /// **'Create offer'**
  String get commonCreateOffer;

  /// No description provided for @commonCreateOffer2.
  ///
  /// In en, this message translates to:
  /// **'Create offer'**
  String get commonCreateOffer2;

  /// No description provided for @commonCreateOffer3.
  ///
  /// In en, this message translates to:
  /// **'Create offer'**
  String get commonCreateOffer3;

  /// No description provided for @commonCreateOffer4.
  ///
  /// In en, this message translates to:
  /// **'Create offer'**
  String get commonCreateOffer4;

  /// No description provided for @commonCreateOffer5.
  ///
  /// In en, this message translates to:
  /// **'Create offer'**
  String get commonCreateOffer5;

  /// No description provided for @commonCreateOffer6.
  ///
  /// In en, this message translates to:
  /// **'Create offer'**
  String get commonCreateOffer6;

  /// No description provided for @commonCreateProduct.
  ///
  /// In en, this message translates to:
  /// **'Create product'**
  String get commonCreateProduct;

  /// No description provided for @commonCreateProfile.
  ///
  /// In en, this message translates to:
  /// **'Create Profile'**
  String get commonCreateProfile;

  /// No description provided for @commonCreatingProfile.
  ///
  /// In en, this message translates to:
  /// **'Creating Profile...'**
  String get commonCreatingProfile;

  /// No description provided for @commonCurrentBusiness.
  ///
  /// In en, this message translates to:
  /// **'Current business'**
  String get commonCurrentBusiness;

  /// No description provided for @commonCustomerInteractions.
  ///
  /// In en, this message translates to:
  /// **'Customer interactions'**
  String get commonCustomerInteractions;

  /// No description provided for @commonCustomerRating.
  ///
  /// In en, this message translates to:
  /// **'Customer rating'**
  String get commonCustomerRating;

  /// No description provided for @commonCustomerSearches.
  ///
  /// In en, this message translates to:
  /// **'Customer searches'**
  String get commonCustomerSearches;

  /// No description provided for @commonDataStorage.
  ///
  /// In en, this message translates to:
  /// **'Data & storage'**
  String get commonDataStorage;

  /// No description provided for @commonDecrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get commonDecrease;

  /// No description provided for @commonDeepLink.
  ///
  /// In en, this message translates to:
  /// **'Deep link'**
  String get commonDeepLink;

  /// No description provided for @commonDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get commonDelivery;

  /// No description provided for @commonDeliveryAvailable.
  ///
  /// In en, this message translates to:
  /// **'Delivery available'**
  String get commonDeliveryAvailable;

  /// No description provided for @commonDeliveryFee.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee'**
  String get commonDeliveryFee;

  /// No description provided for @commonDeliveryRadiusKm.
  ///
  /// In en, this message translates to:
  /// **'Delivery radius (km)'**
  String get commonDeliveryRadiusKm;

  /// No description provided for @commonDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get commonDescription;

  /// No description provided for @commonDescription2.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get commonDescription2;

  /// No description provided for @commonDescriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get commonDescriptionOptional;

  /// No description provided for @commonDetectedAddress.
  ///
  /// In en, this message translates to:
  /// **'Detected Address'**
  String get commonDetectedAddress;

  /// No description provided for @commonDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get commonDevices;

  /// No description provided for @commonDisableOffer.
  ///
  /// In en, this message translates to:
  /// **'Disable offer'**
  String get commonDisableOffer;

  /// No description provided for @commonDisableOffer2.
  ///
  /// In en, this message translates to:
  /// **'Disable offer'**
  String get commonDisableOffer2;

  /// No description provided for @commonDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get commonDisabled;

  /// No description provided for @commonDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get commonDiscard;

  /// No description provided for @commonDiscard2.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get commonDiscard2;

  /// No description provided for @commonDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get commonDisconnect;

  /// No description provided for @commonDisconnectPOS.
  ///
  /// In en, this message translates to:
  /// **'Disconnect POS?'**
  String get commonDisconnectPOS;

  /// No description provided for @commonDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get commonDismiss;

  /// No description provided for @commonDocumentVerification.
  ///
  /// In en, this message translates to:
  /// **'Document Verification'**
  String get commonDocumentVerification;

  /// No description provided for @commonDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get commonDocuments;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonDone2.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone2;

  /// No description provided for @commonDownloadSample.
  ///
  /// In en, this message translates to:
  /// **'Download sample'**
  String get commonDownloadSample;

  /// No description provided for @commonEG8901234567890.
  ///
  /// In en, this message translates to:
  /// **'e.g. 8901234567890'**
  String get commonEG8901234567890;

  /// No description provided for @commonEGKiranaCorner.
  ///
  /// In en, this message translates to:
  /// **'e.g. Kirana Corner'**
  String get commonEGKiranaCorner;

  /// No description provided for @commonEGMonsoonSale.
  ///
  /// In en, this message translates to:
  /// **'e.g. Monsoon Sale'**
  String get commonEGMonsoonSale;

  /// No description provided for @commonEMail.
  ///
  /// In en, this message translates to:
  /// **'E-mail'**
  String get commonEMail;

  /// No description provided for @commonEMail2.
  ///
  /// In en, this message translates to:
  /// **'E-mail'**
  String get commonEMail2;

  /// No description provided for @commonEasyManagement.
  ///
  /// In en, this message translates to:
  /// **'Easy Management'**
  String get commonEasyManagement;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonEditProduct.
  ///
  /// In en, this message translates to:
  /// **'Edit product'**
  String get commonEditProduct;

  /// No description provided for @commonEditProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get commonEditProfile;

  /// No description provided for @commonEditShop.
  ///
  /// In en, this message translates to:
  /// **'Edit shop'**
  String get commonEditShop;

  /// No description provided for @commonEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get commonEmail;

  /// No description provided for @commonEmail2.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get commonEmail2;

  /// No description provided for @commonEmailOptional.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get commonEmailOptional;

  /// No description provided for @commonEmailOrPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Email or phone number'**
  String get commonEmailOrPhoneNumber;

  /// No description provided for @commonEndDate.
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get commonEndDate;

  /// No description provided for @commonEnterBarcode.
  ///
  /// In en, this message translates to:
  /// **'Enter barcode'**
  String get commonEnterBarcode;

  /// No description provided for @commonEnterBarcodeManually.
  ///
  /// In en, this message translates to:
  /// **'Enter barcode manually'**
  String get commonEnterBarcodeManually;

  /// No description provided for @commonEnterGSTIN.
  ///
  /// In en, this message translates to:
  /// **'Enter GSTIN'**
  String get commonEnterGSTIN;

  /// No description provided for @commonEnterLocationManually.
  ///
  /// In en, this message translates to:
  /// **'Enter Location Manually'**
  String get commonEnterLocationManually;

  /// No description provided for @commonEnterManually.
  ///
  /// In en, this message translates to:
  /// **'Enter Manually'**
  String get commonEnterManually;

  /// No description provided for @commonEnterManually2.
  ///
  /// In en, this message translates to:
  /// **'Enter manually'**
  String get commonEnterManually2;

  /// No description provided for @commonEnterUdyamNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter Udyam Number'**
  String get commonEnterUdyamNumber;

  /// No description provided for @commonErrors.
  ///
  /// In en, this message translates to:
  /// **'errors'**
  String get commonErrors;

  /// No description provided for @commonErrors2.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get commonErrors2;

  /// No description provided for @commonEveryYear.
  ///
  /// In en, this message translates to:
  /// **'Every year'**
  String get commonEveryYear;

  /// No description provided for @commonExcelCSV.
  ///
  /// In en, this message translates to:
  /// **'Excel / CSV'**
  String get commonExcelCSV;

  /// No description provided for @commonExcelImports.
  ///
  /// In en, this message translates to:
  /// **'Excel imports'**
  String get commonExcelImports;

  /// No description provided for @commonExcelImports2.
  ///
  /// In en, this message translates to:
  /// **'Excel imports'**
  String get commonExcelImports2;

  /// No description provided for @commonExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get commonExpired;

  /// No description provided for @commonExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get commonExpires;

  /// No description provided for @commonFAQs.
  ///
  /// In en, this message translates to:
  /// **'FAQs'**
  String get commonFAQs;

  /// No description provided for @commonFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get commonFailed;

  /// No description provided for @commonFailed2.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get commonFailed2;

  /// No description provided for @commonFailed3.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get commonFailed3;

  /// No description provided for @commonFailedImport.
  ///
  /// In en, this message translates to:
  /// **'Failed import'**
  String get commonFailedImport;

  /// No description provided for @commonFailedToLoad.
  ///
  /// In en, this message translates to:
  /// **'Failed to load'**
  String get commonFailedToLoad;

  /// No description provided for @commonFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get commonFilters;

  /// No description provided for @commonFilters2.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get commonFilters2;

  /// No description provided for @commonForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password'**
  String get commonForgotPassword;

  /// No description provided for @commonForgotPassword2.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get commonForgotPassword2;

  /// No description provided for @commonFreeDeliveryAbove.
  ///
  /// In en, this message translates to:
  /// **'Free delivery above'**
  String get commonFreeDeliveryAbove;

  /// No description provided for @commonFresh.
  ///
  /// In en, this message translates to:
  /// **'Fresh'**
  String get commonFresh;

  /// No description provided for @commonFresh2.
  ///
  /// In en, this message translates to:
  /// **'fresh'**
  String get commonFresh2;

  /// No description provided for @commonFreshness.
  ///
  /// In en, this message translates to:
  /// **'Freshness'**
  String get commonFreshness;

  /// No description provided for @commonFulfilment.
  ///
  /// In en, this message translates to:
  /// **'Fulfilment'**
  String get commonFulfilment;

  /// No description provided for @commonFullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get commonFullName;

  /// No description provided for @commonFullName2.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get commonFullName2;

  /// No description provided for @commonFullSync.
  ///
  /// In en, this message translates to:
  /// **'Full sync'**
  String get commonFullSync;

  /// No description provided for @commonGSTINOptional.
  ///
  /// In en, this message translates to:
  /// **'GSTIN (optional)'**
  String get commonGSTINOptional;

  /// No description provided for @commonGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get commonGallery;

  /// No description provided for @commonGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get commonGetStarted;

  /// No description provided for @commonGoToConnectionSetup.
  ///
  /// In en, this message translates to:
  /// **'Go to connection setup'**
  String get commonGoToConnectionSetup;

  /// No description provided for @commonGoToConnectionSetup2.
  ///
  /// In en, this message translates to:
  /// **'Go to connection setup'**
  String get commonGoToConnectionSetup2;

  /// No description provided for @commonGoToDashboard.
  ///
  /// In en, this message translates to:
  /// **'Go to Dashboard'**
  String get commonGoToDashboard;

  /// No description provided for @commonHelpCenter.
  ///
  /// In en, this message translates to:
  /// **'Help Center'**
  String get commonHelpCenter;

  /// No description provided for @commonHelpCentre.
  ///
  /// In en, this message translates to:
  /// **'Help centre'**
  String get commonHelpCentre;

  /// No description provided for @commonHelpCentre2.
  ///
  /// In en, this message translates to:
  /// **'Help centre'**
  String get commonHelpCentre2;

  /// No description provided for @commonHelpCentre3.
  ///
  /// In en, this message translates to:
  /// **'Help centre'**
  String get commonHelpCentre3;

  /// No description provided for @commonHelpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get commonHelpSupport;

  /// No description provided for @commonHelpSupport2.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get commonHelpSupport2;

  /// No description provided for @commonHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get commonHistory;

  /// No description provided for @commonHolidays.
  ///
  /// In en, this message translates to:
  /// **'Holidays'**
  String get commonHolidays;

  /// No description provided for @commonHowCanWeHelp.
  ///
  /// In en, this message translates to:
  /// **'How can we help?'**
  String get commonHowCanWeHelp;

  /// No description provided for @commonHyperLocal.
  ///
  /// In en, this message translates to:
  /// **'HyperLocal'**
  String get commonHyperLocal;

  /// No description provided for @commonHyperlocalShopkeeper.
  ///
  /// In en, this message translates to:
  /// **'Hyperlocal Shopkeeper'**
  String get commonHyperlocalShopkeeper;

  /// No description provided for @commonIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get commonIdentity;

  /// No description provided for @commonImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get commonImage;

  /// No description provided for @commonImportAnotherFile.
  ///
  /// In en, this message translates to:
  /// **'Import another file'**
  String get commonImportAnotherFile;

  /// No description provided for @commonImportCenter.
  ///
  /// In en, this message translates to:
  /// **'Import Center'**
  String get commonImportCenter;

  /// No description provided for @commonImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get commonImportFailed;

  /// No description provided for @commonImportFailed2.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get commonImportFailed2;

  /// No description provided for @commonImportFromExcel.
  ///
  /// In en, this message translates to:
  /// **'Import from Excel'**
  String get commonImportFromExcel;

  /// No description provided for @commonImportFromExcel2.
  ///
  /// In en, this message translates to:
  /// **'Import from Excel'**
  String get commonImportFromExcel2;

  /// No description provided for @commonImportHistory.
  ///
  /// In en, this message translates to:
  /// **'Import history'**
  String get commonImportHistory;

  /// No description provided for @commonImportResult.
  ///
  /// In en, this message translates to:
  /// **'Import result'**
  String get commonImportResult;

  /// No description provided for @commonImportantNotification.
  ///
  /// In en, this message translates to:
  /// **'Important notification'**
  String get commonImportantNotification;

  /// No description provided for @commonInAppAlerts.
  ///
  /// In en, this message translates to:
  /// **'In-app alerts'**
  String get commonInAppAlerts;

  /// No description provided for @commonInStock.
  ///
  /// In en, this message translates to:
  /// **'In Stock'**
  String get commonInStock;

  /// No description provided for @commonInStock2.
  ///
  /// In en, this message translates to:
  /// **'In Stock'**
  String get commonInStock2;

  /// No description provided for @commonInStock3.
  ///
  /// In en, this message translates to:
  /// **'In stock'**
  String get commonInStock3;

  /// No description provided for @commonInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get commonInactive;

  /// No description provided for @commonIncrease.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get commonIncrease;

  /// No description provided for @commonIncremental.
  ///
  /// In en, this message translates to:
  /// **'Incremental'**
  String get commonIncremental;

  /// No description provided for @commonInsightsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Insights unavailable'**
  String get commonInsightsUnavailable;

  /// No description provided for @commonInteractions.
  ///
  /// In en, this message translates to:
  /// **'Interactions'**
  String get commonInteractions;

  /// No description provided for @commonInteractionsToday.
  ///
  /// In en, this message translates to:
  /// **'Interactions today'**
  String get commonInteractionsToday;

  /// No description provided for @commonInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get commonInventory;

  /// No description provided for @commonInventory2.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get commonInventory2;

  /// No description provided for @commonInventory3.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get commonInventory3;

  /// No description provided for @commonInventoryFreshness.
  ///
  /// In en, this message translates to:
  /// **'Inventory freshness'**
  String get commonInventoryFreshness;

  /// No description provided for @commonInventoryStale.
  ///
  /// In en, this message translates to:
  /// **'Inventory stale'**
  String get commonInventoryStale;

  /// No description provided for @commonInventoryStatus.
  ///
  /// In en, this message translates to:
  /// **'Inventory status'**
  String get commonInventoryStatus;

  /// No description provided for @commonInventorySyncStatus.
  ///
  /// In en, this message translates to:
  /// **'Inventory sync status'**
  String get commonInventorySyncStatus;

  /// No description provided for @commonItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get commonItems;

  /// No description provided for @commonLandmarkOptional.
  ///
  /// In en, this message translates to:
  /// **'Landmark (optional)'**
  String get commonLandmarkOptional;

  /// No description provided for @commonLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get commonLanguage;

  /// No description provided for @commonLastImport.
  ///
  /// In en, this message translates to:
  /// **'Last import'**
  String get commonLastImport;

  /// No description provided for @commonLastInventoryUpdate.
  ///
  /// In en, this message translates to:
  /// **'Last inventory update'**
  String get commonLastInventoryUpdate;

  /// No description provided for @commonLastPOSSync.
  ///
  /// In en, this message translates to:
  /// **'Last POS sync'**
  String get commonLastPOSSync;

  /// No description provided for @commonLatitude.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get commonLatitude;

  /// No description provided for @commonLatitude2.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get commonLatitude2;

  /// No description provided for @commonLegal.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get commonLegal;

  /// No description provided for @commonLinkedProducts.
  ///
  /// In en, this message translates to:
  /// **'Linked products'**
  String get commonLinkedProducts;

  /// No description provided for @commonLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get commonLocation;

  /// No description provided for @commonLog.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get commonLog;

  /// No description provided for @commonLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get commonLogOut;

  /// No description provided for @commonLogOut2.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get commonLogOut2;

  /// No description provided for @commonLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get commonLogout;

  /// No description provided for @commonLongitude.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get commonLongitude;

  /// No description provided for @commonLongitude2.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get commonLongitude2;

  /// No description provided for @commonLookUp.
  ///
  /// In en, this message translates to:
  /// **'Look up'**
  String get commonLookUp;

  /// No description provided for @commonLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get commonLow;

  /// No description provided for @commonLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get commonLowStock;

  /// No description provided for @commonLowStock2.
  ///
  /// In en, this message translates to:
  /// **'Low Stock'**
  String get commonLowStock2;

  /// No description provided for @commonLowStock3.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get commonLowStock3;

  /// No description provided for @commonLowStock4.
  ///
  /// In en, this message translates to:
  /// **'Low Stock'**
  String get commonLowStock4;

  /// No description provided for @commonLowStock5.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get commonLowStock5;

  /// No description provided for @commonMRP.
  ///
  /// In en, this message translates to:
  /// **'MRP'**
  String get commonMRP;

  /// No description provided for @commonMRPOptional.
  ///
  /// In en, this message translates to:
  /// **'MRP (optional)'**
  String get commonMRPOptional;

  /// No description provided for @commonMRPOptional2.
  ///
  /// In en, this message translates to:
  /// **'MRP (optional)'**
  String get commonMRPOptional2;

  /// No description provided for @commonMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get commonMarkAllRead;

  /// No description provided for @commonMarkRead.
  ///
  /// In en, this message translates to:
  /// **'Mark read'**
  String get commonMarkRead;

  /// No description provided for @commonMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get commonMax;

  /// No description provided for @commonMessageSent.
  ///
  /// In en, this message translates to:
  /// **'Message sent'**
  String get commonMessageSent;

  /// No description provided for @commonMessageTheSupportTeam.
  ///
  /// In en, this message translates to:
  /// **'Message the support team'**
  String get commonMessageTheSupportTeam;

  /// No description provided for @commonMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get commonMessages;

  /// No description provided for @commonMin.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get commonMin;

  /// No description provided for @commonMinOrderAmount.
  ///
  /// In en, this message translates to:
  /// **'Min order amount'**
  String get commonMinOrderAmount;

  /// No description provided for @commonMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get commonMobileNumber;

  /// No description provided for @commonMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get commonMore;

  /// No description provided for @commonMoreDetailsOptional.
  ///
  /// In en, this message translates to:
  /// **'More details (optional)'**
  String get commonMoreDetailsOptional;

  /// No description provided for @commonMoreVisibility.
  ///
  /// In en, this message translates to:
  /// **'More Visibility'**
  String get commonMoreVisibility;

  /// No description provided for @commonMyBusiness.
  ///
  /// In en, this message translates to:
  /// **'My business'**
  String get commonMyBusiness;

  /// No description provided for @commonMyBusiness2.
  ///
  /// In en, this message translates to:
  /// **'My business'**
  String get commonMyBusiness2;

  /// No description provided for @commonMyProfile.
  ///
  /// In en, this message translates to:
  /// **'My profile'**
  String get commonMyProfile;

  /// No description provided for @commonMySupportTickets.
  ///
  /// In en, this message translates to:
  /// **'My support tickets'**
  String get commonMySupportTickets;

  /// No description provided for @commonMySupportTickets2.
  ///
  /// In en, this message translates to:
  /// **'My support tickets'**
  String get commonMySupportTickets2;

  /// No description provided for @commonMyTickets.
  ///
  /// In en, this message translates to:
  /// **'My Tickets'**
  String get commonMyTickets;

  /// No description provided for @commonMyTickets2.
  ///
  /// In en, this message translates to:
  /// **'My tickets'**
  String get commonMyTickets2;

  /// No description provided for @commonName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get commonName;

  /// No description provided for @commonNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get commonNameOptional;

  /// No description provided for @commonNeedClarification.
  ///
  /// In en, this message translates to:
  /// **'Need clarification?'**
  String get commonNeedClarification;

  /// No description provided for @commonNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get commonNeedsAttention;

  /// No description provided for @commonNeedsUpdate.
  ///
  /// In en, this message translates to:
  /// **'Needs update'**
  String get commonNeedsUpdate;

  /// No description provided for @commonNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get commonNewPassword;

  /// No description provided for @commonNewProduct.
  ///
  /// In en, this message translates to:
  /// **'New product'**
  String get commonNewProduct;

  /// No description provided for @commonNewQuantity.
  ///
  /// In en, this message translates to:
  /// **'New quantity'**
  String get commonNewQuantity;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonNoAccessToThisShop.
  ///
  /// In en, this message translates to:
  /// **'No access to this shop'**
  String get commonNoAccessToThisShop;

  /// No description provided for @commonNoAccessToThisShop2.
  ///
  /// In en, this message translates to:
  /// **'No access to this shop'**
  String get commonNoAccessToThisShop2;

  /// No description provided for @commonNoConnectorYet.
  ///
  /// In en, this message translates to:
  /// **'No connector yet.'**
  String get commonNoConnectorYet;

  /// No description provided for @commonNoConnectorYet2.
  ///
  /// In en, this message translates to:
  /// **'No connector yet'**
  String get commonNoConnectorYet2;

  /// No description provided for @commonNoConnectorYet3.
  ///
  /// In en, this message translates to:
  /// **'No connector yet'**
  String get commonNoConnectorYet3;

  /// No description provided for @commonNoCustomerActivityYet.
  ///
  /// In en, this message translates to:
  /// **'No customer activity yet'**
  String get commonNoCustomerActivityYet;

  /// No description provided for @commonNoHistoryRecordedYet.
  ///
  /// In en, this message translates to:
  /// **'No history recorded yet.'**
  String get commonNoHistoryRecordedYet;

  /// No description provided for @commonNoHistoryYet.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get commonNoHistoryYet;

  /// No description provided for @commonNoHolidaysScheduled.
  ///
  /// In en, this message translates to:
  /// **'No holidays scheduled.'**
  String get commonNoHolidaysScheduled;

  /// No description provided for @commonNoImage.
  ///
  /// In en, this message translates to:
  /// **'No image'**
  String get commonNoImage;

  /// No description provided for @commonNoImage2.
  ///
  /// In en, this message translates to:
  /// **'No image'**
  String get commonNoImage2;

  /// No description provided for @commonNoImportsYet.
  ///
  /// In en, this message translates to:
  /// **'No imports yet'**
  String get commonNoImportsYet;

  /// No description provided for @commonNoOtherDevices.
  ///
  /// In en, this message translates to:
  /// **'No other devices'**
  String get commonNoOtherDevices;

  /// No description provided for @commonNoPinStoredYet.
  ///
  /// In en, this message translates to:
  /// **'No pin stored yet'**
  String get commonNoPinStoredYet;

  /// No description provided for @commonNoPriceChangesYet.
  ///
  /// In en, this message translates to:
  /// **'No price changes yet'**
  String get commonNoPriceChangesYet;

  /// No description provided for @commonNoProductsYet.
  ///
  /// In en, this message translates to:
  /// **'No products yet'**
  String get commonNoProductsYet;

  /// No description provided for @commonNoProductsYet2.
  ///
  /// In en, this message translates to:
  /// **'No products yet'**
  String get commonNoProductsYet2;

  /// No description provided for @commonNoShopSelected.
  ///
  /// In en, this message translates to:
  /// **'No shop selected'**
  String get commonNoShopSelected;

  /// No description provided for @commonNoShopSelected2.
  ///
  /// In en, this message translates to:
  /// **'No shop selected'**
  String get commonNoShopSelected2;

  /// No description provided for @commonNoShopSelected3.
  ///
  /// In en, this message translates to:
  /// **'No shop selected'**
  String get commonNoShopSelected3;

  /// No description provided for @commonNoShopSelected4.
  ///
  /// In en, this message translates to:
  /// **'No shop selected'**
  String get commonNoShopSelected4;

  /// No description provided for @commonNoShopSelected5.
  ///
  /// In en, this message translates to:
  /// **'No shop selected'**
  String get commonNoShopSelected5;

  /// No description provided for @commonNoSyncsYet.
  ///
  /// In en, this message translates to:
  /// **'No syncs yet'**
  String get commonNoSyncsYet;

  /// No description provided for @commonNoTicketsYet.
  ///
  /// In en, this message translates to:
  /// **'No tickets yet'**
  String get commonNoTicketsYet;

  /// No description provided for @commonNotEstablishedYet.
  ///
  /// In en, this message translates to:
  /// **'Not established yet'**
  String get commonNotEstablishedYet;

  /// No description provided for @commonNoteOptional.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get commonNoteOptional;

  /// No description provided for @commonNothingChangedYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed yet.'**
  String get commonNothingChangedYet;

  /// No description provided for @commonNothingToApply.
  ///
  /// In en, this message translates to:
  /// **'Nothing to apply'**
  String get commonNothingToApply;

  /// No description provided for @commonNothingToPreview.
  ///
  /// In en, this message translates to:
  /// **'Nothing to preview'**
  String get commonNothingToPreview;

  /// No description provided for @commonNotification.
  ///
  /// In en, this message translates to:
  /// **'Notification'**
  String get commonNotification;

  /// No description provided for @commonNotificationPreferences.
  ///
  /// In en, this message translates to:
  /// **'Notification preferences'**
  String get commonNotificationPreferences;

  /// No description provided for @commonNotificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification settings'**
  String get commonNotificationSettings;

  /// No description provided for @commonNotificationSettings2.
  ///
  /// In en, this message translates to:
  /// **'Notification settings'**
  String get commonNotificationSettings2;

  /// No description provided for @commonNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get commonNotifications;

  /// No description provided for @commonNotifications2.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get commonNotifications2;

  /// No description provided for @commonOTPVerification.
  ///
  /// In en, this message translates to:
  /// **'OTP Verification'**
  String get commonOTPVerification;

  /// No description provided for @commonOfferDetails.
  ///
  /// In en, this message translates to:
  /// **'Offer details'**
  String get commonOfferDetails;

  /// No description provided for @commonOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Offer title'**
  String get commonOfferTitle;

  /// No description provided for @commonOfferType.
  ///
  /// In en, this message translates to:
  /// **'Offer type'**
  String get commonOfferType;

  /// No description provided for @commonOffers.
  ///
  /// In en, this message translates to:
  /// **'Offers'**
  String get commonOffers;

  /// No description provided for @commonOffersAndPricing.
  ///
  /// In en, this message translates to:
  /// **'Offers and pricing'**
  String get commonOffersAndPricing;

  /// No description provided for @commonOffersPricing.
  ///
  /// In en, this message translates to:
  /// **'Offers & pricing'**
  String get commonOffersPricing;

  /// No description provided for @commonOnlyRecentlyUpdated.
  ///
  /// In en, this message translates to:
  /// **'Only recently updated'**
  String get commonOnlyRecentlyUpdated;

  /// No description provided for @commonOpenImportHistory.
  ///
  /// In en, this message translates to:
  /// **'Open import history'**
  String get commonOpenImportHistory;

  /// No description provided for @commonOpenProduct.
  ///
  /// In en, this message translates to:
  /// **'Open Product'**
  String get commonOpenProduct;

  /// No description provided for @commonOpenSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Open System Settings'**
  String get commonOpenSystemSettings;

  /// No description provided for @commonOpenSystemSettings2.
  ///
  /// In en, this message translates to:
  /// **'Open System Settings'**
  String get commonOpenSystemSettings2;

  /// No description provided for @commonOpeningTime.
  ///
  /// In en, this message translates to:
  /// **'Opening Time'**
  String get commonOpeningTime;

  /// No description provided for @commonOpens.
  ///
  /// In en, this message translates to:
  /// **'Opens'**
  String get commonOpens;

  /// No description provided for @commonOperatingHours.
  ///
  /// In en, this message translates to:
  /// **'Operating hours'**
  String get commonOperatingHours;

  /// No description provided for @commonOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get commonOptional;

  /// No description provided for @commonOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get commonOr;

  /// No description provided for @commonOr2.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get commonOr2;

  /// No description provided for @commonOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get commonOrders;

  /// No description provided for @commonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get commonOther;

  /// No description provided for @commonOtherDevices.
  ///
  /// In en, this message translates to:
  /// **'Other devices'**
  String get commonOtherDevices;

  /// No description provided for @commonOut.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get commonOut;

  /// No description provided for @commonOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of Stock'**
  String get commonOutOfStock;

  /// No description provided for @commonOutOfStock2.
  ///
  /// In en, this message translates to:
  /// **'Out of Stock'**
  String get commonOutOfStock2;

  /// No description provided for @commonOutOfStock3.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get commonOutOfStock3;

  /// No description provided for @commonOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get commonOverview;

  /// No description provided for @commonPOSConnected.
  ///
  /// In en, this message translates to:
  /// **'POS connected'**
  String get commonPOSConnected;

  /// No description provided for @commonPOSConnectionSetup.
  ///
  /// In en, this message translates to:
  /// **'POS connection setup'**
  String get commonPOSConnectionSetup;

  /// No description provided for @commonPOSIntegration.
  ///
  /// In en, this message translates to:
  /// **'POS integration'**
  String get commonPOSIntegration;

  /// No description provided for @commonPOSProblem.
  ///
  /// In en, this message translates to:
  /// **'POS problem'**
  String get commonPOSProblem;

  /// No description provided for @commonPOSProvider.
  ///
  /// In en, this message translates to:
  /// **'POS provider'**
  String get commonPOSProvider;

  /// No description provided for @commonPOSProvider2.
  ///
  /// In en, this message translates to:
  /// **'POS provider'**
  String get commonPOSProvider2;

  /// No description provided for @commonPOSSync.
  ///
  /// In en, this message translates to:
  /// **'POS sync'**
  String get commonPOSSync;

  /// No description provided for @commonPOSSync2.
  ///
  /// In en, this message translates to:
  /// **'POS sync'**
  String get commonPOSSync2;

  /// No description provided for @commonPOSSync3.
  ///
  /// In en, this message translates to:
  /// **'POS Sync'**
  String get commonPOSSync3;

  /// No description provided for @commonPOSSync4.
  ///
  /// In en, this message translates to:
  /// **'POS sync'**
  String get commonPOSSync4;

  /// No description provided for @commonPOSSync5.
  ///
  /// In en, this message translates to:
  /// **'POS sync'**
  String get commonPOSSync5;

  /// No description provided for @commonPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get commonPassword;

  /// No description provided for @commonPassword2.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get commonPassword2;

  /// No description provided for @commonPast.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get commonPast;

  /// No description provided for @commonPeakHours.
  ///
  /// In en, this message translates to:
  /// **'Peak hours'**
  String get commonPeakHours;

  /// No description provided for @commonPeakHours2.
  ///
  /// In en, this message translates to:
  /// **'Peak hours'**
  String get commonPeakHours2;

  /// No description provided for @commonPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get commonPhone;

  /// No description provided for @commonPhone2.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get commonPhone2;

  /// No description provided for @commonPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get commonPhoneNumber;

  /// No description provided for @commonPhoneNumberOrEmail.
  ///
  /// In en, this message translates to:
  /// **'Phone number or email'**
  String get commonPhoneNumberOrEmail;

  /// No description provided for @commonPickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get commonPickup;

  /// No description provided for @commonPickupAvailable.
  ///
  /// In en, this message translates to:
  /// **'Pickup available'**
  String get commonPickupAvailable;

  /// No description provided for @commonPincode.
  ///
  /// In en, this message translates to:
  /// **'Pincode'**
  String get commonPincode;

  /// No description provided for @commonPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get commonPlatform;

  /// No description provided for @commonPreparingScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Preparing screenshot...'**
  String get commonPreparingScreenshot;

  /// No description provided for @commonPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get commonPrice;

  /// No description provided for @commonPriceAndMRP.
  ///
  /// In en, this message translates to:
  /// **'Price and MRP'**
  String get commonPriceAndMRP;

  /// No description provided for @commonPriceHistory.
  ///
  /// In en, this message translates to:
  /// **'Price history'**
  String get commonPriceHistory;

  /// No description provided for @commonPriceHistory2.
  ///
  /// In en, this message translates to:
  /// **'Price history'**
  String get commonPriceHistory2;

  /// No description provided for @commonPriceList.
  ///
  /// In en, this message translates to:
  /// **'Price list'**
  String get commonPriceList;

  /// No description provided for @commonPriceRange.
  ///
  /// In en, this message translates to:
  /// **'Price range'**
  String get commonPriceRange;

  /// No description provided for @commonPriceUpdated.
  ///
  /// In en, this message translates to:
  /// **'Price updated'**
  String get commonPriceUpdated;

  /// No description provided for @commonPricing.
  ///
  /// In en, this message translates to:
  /// **'Pricing'**
  String get commonPricing;

  /// No description provided for @commonPricingOffers.
  ///
  /// In en, this message translates to:
  /// **'Pricing & Offers'**
  String get commonPricingOffers;

  /// No description provided for @commonPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get commonPriority;

  /// No description provided for @commonPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get commonPrivacyPolicy;

  /// No description provided for @commonPrivacyPolicy2.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get commonPrivacyPolicy2;

  /// No description provided for @commonPrivacyPolicy3.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get commonPrivacyPolicy3;

  /// No description provided for @commonProcessed.
  ///
  /// In en, this message translates to:
  /// **'Processed'**
  String get commonProcessed;

  /// No description provided for @commonProduct.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get commonProduct;

  /// No description provided for @commonProductClicks.
  ///
  /// In en, this message translates to:
  /// **'Product clicks'**
  String get commonProductClicks;

  /// No description provided for @commonProductCreated.
  ///
  /// In en, this message translates to:
  /// **'Product created'**
  String get commonProductCreated;

  /// No description provided for @commonProductNotFound.
  ///
  /// In en, this message translates to:
  /// **'Product not found'**
  String get commonProductNotFound;

  /// No description provided for @commonProductUpdated.
  ///
  /// In en, this message translates to:
  /// **'Product updated'**
  String get commonProductUpdated;

  /// No description provided for @commonProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get commonProducts;

  /// No description provided for @commonProducts2.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get commonProducts2;

  /// No description provided for @commonProductsInventory.
  ///
  /// In en, this message translates to:
  /// **'Products & inventory'**
  String get commonProductsInventory;

  /// No description provided for @commonProfileSetupIssue.
  ///
  /// In en, this message translates to:
  /// **'Profile setup issue'**
  String get commonProfileSetupIssue;

  /// No description provided for @commonPublishImmediately.
  ///
  /// In en, this message translates to:
  /// **'Publish immediately'**
  String get commonPublishImmediately;

  /// No description provided for @commonPublishImmediately2.
  ///
  /// In en, this message translates to:
  /// **'Publish immediately'**
  String get commonPublishImmediately2;

  /// No description provided for @commonPushNotifications.
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get commonPushNotifications;

  /// No description provided for @commonQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get commonQuantity;

  /// No description provided for @commonQuantityChange.
  ///
  /// In en, this message translates to:
  /// **'Quantity change'**
  String get commonQuantityChange;

  /// No description provided for @commonQuantityInitialStock.
  ///
  /// In en, this message translates to:
  /// **'Quantity (initial stock)'**
  String get commonQuantityInitialStock;

  /// No description provided for @commonQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get commonQuickActions;

  /// No description provided for @commonRatings.
  ///
  /// In en, this message translates to:
  /// **'Ratings'**
  String get commonRatings;

  /// No description provided for @commonReachUs.
  ///
  /// In en, this message translates to:
  /// **'Reach us'**
  String get commonReachUs;

  /// No description provided for @commonReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get commonReason;

  /// No description provided for @commonReasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get commonReasonOptional;

  /// No description provided for @commonRecentImports.
  ///
  /// In en, this message translates to:
  /// **'Recent imports'**
  String get commonRecentImports;

  /// No description provided for @commonRecentImports2.
  ///
  /// In en, this message translates to:
  /// **'Recent imports'**
  String get commonRecentImports2;

  /// No description provided for @commonRecentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get commonRecentSearches;

  /// No description provided for @commonRecentUpdates.
  ///
  /// In en, this message translates to:
  /// **'Recent updates'**
  String get commonRecentUpdates;

  /// No description provided for @commonRecentUpdates2.
  ///
  /// In en, this message translates to:
  /// **'Recent Updates'**
  String get commonRecentUpdates2;

  /// No description provided for @commonRecentlyUpdated.
  ///
  /// In en, this message translates to:
  /// **'Recently updated'**
  String get commonRecentlyUpdated;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonRefresh2.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh2;

  /// No description provided for @commonRefresh3.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh3;

  /// No description provided for @commonRefresh4.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh4;

  /// No description provided for @commonRefresh5.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh5;

  /// No description provided for @commonRefresh6.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh6;

  /// No description provided for @commonRefresh7.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh7;

  /// No description provided for @commonRefresh8.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh8;

  /// No description provided for @commonRefresh9.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh9;

  /// No description provided for @commonRefreshNow.
  ///
  /// In en, this message translates to:
  /// **'Refresh now'**
  String get commonRefreshNow;

  /// No description provided for @commonRefreshRecentImports.
  ///
  /// In en, this message translates to:
  /// **'Refresh recent imports'**
  String get commonRefreshRecentImports;

  /// No description provided for @commonRefreshStatus.
  ///
  /// In en, this message translates to:
  /// **'Refresh status'**
  String get commonRefreshStatus;

  /// No description provided for @commonRegisterYourShop.
  ///
  /// In en, this message translates to:
  /// **'Register Your Shop'**
  String get commonRegisterYourShop;

  /// No description provided for @commonRegisteredAddress.
  ///
  /// In en, this message translates to:
  /// **'Registered address'**
  String get commonRegisteredAddress;

  /// No description provided for @commonRegisteredAs.
  ///
  /// In en, this message translates to:
  /// **'Registered as'**
  String get commonRegisteredAs;

  /// No description provided for @commonRegistrationSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Registration Submitted!'**
  String get commonRegistrationSubmitted;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonRemoveHoliday.
  ///
  /// In en, this message translates to:
  /// **'Remove holiday'**
  String get commonRemoveHoliday;

  /// No description provided for @commonRemovePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get commonRemovePhoto;

  /// No description provided for @commonRemoveScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Remove screenshot'**
  String get commonRemoveScreenshot;

  /// No description provided for @commonRepeatsEveryYear.
  ///
  /// In en, this message translates to:
  /// **'Repeats every year'**
  String get commonRepeatsEveryYear;

  /// No description provided for @commonReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get commonReplace;

  /// No description provided for @commonReportAnIssue.
  ///
  /// In en, this message translates to:
  /// **'Report an issue'**
  String get commonReportAnIssue;

  /// No description provided for @commonReportAnIssue2.
  ///
  /// In en, this message translates to:
  /// **'Report an issue'**
  String get commonReportAnIssue2;

  /// No description provided for @commonReportIssue.
  ///
  /// In en, this message translates to:
  /// **'Report Issue'**
  String get commonReportIssue;

  /// No description provided for @commonReportIssue2.
  ///
  /// In en, this message translates to:
  /// **'Report issue'**
  String get commonReportIssue2;

  /// No description provided for @commonReportSent.
  ///
  /// In en, this message translates to:
  /// **'Report sent'**
  String get commonReportSent;

  /// No description provided for @commonReportSomethingElse.
  ///
  /// In en, this message translates to:
  /// **'Report something else'**
  String get commonReportSomethingElse;

  /// No description provided for @commonReportsAndInsights.
  ///
  /// In en, this message translates to:
  /// **'Reports and insights'**
  String get commonReportsAndInsights;

  /// No description provided for @commonReportsInsights.
  ///
  /// In en, this message translates to:
  /// **'Reports & insights'**
  String get commonReportsInsights;

  /// No description provided for @commonReportsInsights2.
  ///
  /// In en, this message translates to:
  /// **'Reports & Insights'**
  String get commonReportsInsights2;

  /// No description provided for @commonReportsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Reports unavailable'**
  String get commonReportsUnavailable;

  /// No description provided for @commonResendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get commonResendCode;

  /// No description provided for @commonReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get commonReset;

  /// No description provided for @commonResetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get commonResetPassword;

  /// No description provided for @commonResetYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get commonResetYourPassword;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonRetry10.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry10;

  /// No description provided for @commonRetry11.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry11;

  /// No description provided for @commonRetry12.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry12;

  /// No description provided for @commonRetry2.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry2;

  /// No description provided for @commonRetry3.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry3;

  /// No description provided for @commonRetry4.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry4;

  /// No description provided for @commonRetry5.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry5;

  /// No description provided for @commonRetry6.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry6;

  /// No description provided for @commonRetry7.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry7;

  /// No description provided for @commonRetry8.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry8;

  /// No description provided for @commonRetry9.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry9;

  /// No description provided for @commonRetryCamera.
  ///
  /// In en, this message translates to:
  /// **'Retry camera'**
  String get commonRetryCamera;

  /// No description provided for @commonRetryThisSync.
  ///
  /// In en, this message translates to:
  /// **'Retry this sync'**
  String get commonRetryThisSync;

  /// No description provided for @commonReviewDetails.
  ///
  /// In en, this message translates to:
  /// **'Review details'**
  String get commonReviewDetails;

  /// No description provided for @commonReviewImport.
  ///
  /// In en, this message translates to:
  /// **'Review import'**
  String get commonReviewImport;

  /// No description provided for @commonReviewYourDetails.
  ///
  /// In en, this message translates to:
  /// **'Review your details'**
  String get commonReviewYourDetails;

  /// No description provided for @commonReviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get commonReviewed;

  /// No description provided for @commonRows.
  ///
  /// In en, this message translates to:
  /// **'rows'**
  String get commonRows;

  /// No description provided for @commonSKUOptional.
  ///
  /// In en, this message translates to:
  /// **'SKU (optional)'**
  String get commonSKUOptional;

  /// No description provided for @commonSMS.
  ///
  /// In en, this message translates to:
  /// **'SMS'**
  String get commonSMS;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonSaveAsDraft.
  ///
  /// In en, this message translates to:
  /// **'Save as draft'**
  String get commonSaveAsDraft;

  /// No description provided for @commonSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get commonSaveChanges;

  /// No description provided for @commonSaveChanges2.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get commonSaveChanges2;

  /// No description provided for @commonSaveOperatingHours.
  ///
  /// In en, this message translates to:
  /// **'Save operating hours'**
  String get commonSaveOperatingHours;

  /// No description provided for @commonSavePrice.
  ///
  /// In en, this message translates to:
  /// **'Save price'**
  String get commonSavePrice;

  /// No description provided for @commonSaveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save settings'**
  String get commonSaveSettings;

  /// No description provided for @commonSaveSettings2.
  ///
  /// In en, this message translates to:
  /// **'Save settings'**
  String get commonSaveSettings2;

  /// No description provided for @commonSaveStockUpdate.
  ///
  /// In en, this message translates to:
  /// **'Save stock update'**
  String get commonSaveStockUpdate;

  /// No description provided for @commonScanBarcode.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get commonScanBarcode;

  /// No description provided for @commonScanBarcode2.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get commonScanBarcode2;

  /// No description provided for @commonScanBarcode3.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get commonScanBarcode3;

  /// No description provided for @commonScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get commonScheduled;

  /// No description provided for @commonScreenshotOptional.
  ///
  /// In en, this message translates to:
  /// **'Screenshot (optional)'**
  String get commonScreenshotOptional;

  /// No description provided for @commonSearchHelp.
  ///
  /// In en, this message translates to:
  /// **'Search help'**
  String get commonSearchHelp;

  /// No description provided for @commonSearchNameOrSKU.
  ///
  /// In en, this message translates to:
  /// **'Search name or SKU'**
  String get commonSearchNameOrSKU;

  /// No description provided for @commonSecureTrusted.
  ///
  /// In en, this message translates to:
  /// **'Secure & Trusted'**
  String get commonSecureTrusted;

  /// No description provided for @commonSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get commonSecurity;

  /// No description provided for @commonSecurity2.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get commonSecurity2;

  /// No description provided for @commonSecurityAlerts.
  ///
  /// In en, this message translates to:
  /// **'Security alerts'**
  String get commonSecurityAlerts;

  /// No description provided for @commonSelectACategory.
  ///
  /// In en, this message translates to:
  /// **'Select a category'**
  String get commonSelectACategory;

  /// No description provided for @commonSelectAType.
  ///
  /// In en, this message translates to:
  /// **'Select a type'**
  String get commonSelectAType;

  /// No description provided for @commonSelectBusinessCategory.
  ///
  /// In en, this message translates to:
  /// **'Select Business Category'**
  String get commonSelectBusinessCategory;

  /// No description provided for @commonSelectXlsxFile.
  ///
  /// In en, this message translates to:
  /// **'Select .xlsx file'**
  String get commonSelectXlsxFile;

  /// No description provided for @commonSellingPrice.
  ///
  /// In en, this message translates to:
  /// **'Selling price'**
  String get commonSellingPrice;

  /// No description provided for @commonSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get commonSendCode;

  /// No description provided for @commonSendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get commonSendResetLink;

  /// No description provided for @commonSession.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get commonSession;

  /// No description provided for @commonSessionsDevices.
  ///
  /// In en, this message translates to:
  /// **'Sessions & devices'**
  String get commonSessionsDevices;

  /// No description provided for @commonSessionsDevices2.
  ///
  /// In en, this message translates to:
  /// **'Sessions & devices'**
  String get commonSessionsDevices2;

  /// No description provided for @commonSetUpYourFirstShop.
  ///
  /// In en, this message translates to:
  /// **'Set up your first shop'**
  String get commonSetUpYourFirstShop;

  /// No description provided for @commonSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get commonSettings;

  /// No description provided for @commonSettings2.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get commonSettings2;

  /// No description provided for @commonSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get commonSettingsSaved;

  /// No description provided for @commonShopAlerts.
  ///
  /// In en, this message translates to:
  /// **'Shop alerts'**
  String get commonShopAlerts;

  /// No description provided for @commonShopBusinessName.
  ///
  /// In en, this message translates to:
  /// **'Shop / Business Name'**
  String get commonShopBusinessName;

  /// No description provided for @commonShopBusinessName2.
  ///
  /// In en, this message translates to:
  /// **'Shop / Business Name'**
  String get commonShopBusinessName2;

  /// No description provided for @commonShopLocation.
  ///
  /// In en, this message translates to:
  /// **'Shop Location'**
  String get commonShopLocation;

  /// No description provided for @commonShopLocation2.
  ///
  /// In en, this message translates to:
  /// **'Shop location'**
  String get commonShopLocation2;

  /// No description provided for @commonShopName.
  ///
  /// In en, this message translates to:
  /// **'Shop name'**
  String get commonShopName;

  /// No description provided for @commonShopNoStreetArea.
  ///
  /// In en, this message translates to:
  /// **'Shop no., street, area'**
  String get commonShopNoStreetArea;

  /// No description provided for @commonShopProfile.
  ///
  /// In en, this message translates to:
  /// **'Shop profile'**
  String get commonShopProfile;

  /// No description provided for @commonShopProfile2.
  ///
  /// In en, this message translates to:
  /// **'Shop profile'**
  String get commonShopProfile2;

  /// No description provided for @commonShopProfile3.
  ///
  /// In en, this message translates to:
  /// **'Shop Profile'**
  String get commonShopProfile3;

  /// No description provided for @commonShopProfile4.
  ///
  /// In en, this message translates to:
  /// **'Shop profile'**
  String get commonShopProfile4;

  /// No description provided for @commonShopSettings.
  ///
  /// In en, this message translates to:
  /// **'Shop settings'**
  String get commonShopSettings;

  /// No description provided for @commonShopSettings2.
  ///
  /// In en, this message translates to:
  /// **'Shop settings'**
  String get commonShopSettings2;

  /// No description provided for @commonShopSettings3.
  ///
  /// In en, this message translates to:
  /// **'Shop settings'**
  String get commonShopSettings3;

  /// No description provided for @commonShopStatus.
  ///
  /// In en, this message translates to:
  /// **'Shop status'**
  String get commonShopStatus;

  /// No description provided for @commonShopVerification.
  ///
  /// In en, this message translates to:
  /// **'Shop verification'**
  String get commonShopVerification;

  /// No description provided for @commonShopViews.
  ///
  /// In en, this message translates to:
  /// **'Shop views'**
  String get commonShopViews;

  /// No description provided for @commonShopkeeperApp.
  ///
  /// In en, this message translates to:
  /// **'Shopkeeper App'**
  String get commonShopkeeperApp;

  /// No description provided for @commonShowAllJobs.
  ///
  /// In en, this message translates to:
  /// **'Show all jobs'**
  String get commonShowAllJobs;

  /// No description provided for @commonSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get commonSignIn;

  /// No description provided for @commonSignIn2.
  ///
  /// In en, this message translates to:
  /// **'Sign-in'**
  String get commonSignIn2;

  /// No description provided for @commonSignIn3.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get commonSignIn3;

  /// No description provided for @commonSignInInstead.
  ///
  /// In en, this message translates to:
  /// **'Sign in instead'**
  String get commonSignInInstead;

  /// No description provided for @commonSignInMethod.
  ///
  /// In en, this message translates to:
  /// **'Sign-in method'**
  String get commonSignInMethod;

  /// No description provided for @commonSignInWithPhone.
  ///
  /// In en, this message translates to:
  /// **'Sign in with phone'**
  String get commonSignInWithPhone;

  /// No description provided for @commonSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get commonSignOut;

  /// No description provided for @commonSignOut2.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get commonSignOut2;

  /// No description provided for @commonSignOut3.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get commonSignOut3;

  /// No description provided for @commonSignOutOfThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Sign out of this device'**
  String get commonSignOutOfThisDevice;

  /// No description provided for @commonSignOutOfThisDevice2.
  ///
  /// In en, this message translates to:
  /// **'Sign out of this device'**
  String get commonSignOutOfThisDevice2;

  /// No description provided for @commonSignOutThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Sign out this device?'**
  String get commonSignOutThisDevice;

  /// No description provided for @commonSignedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as'**
  String get commonSignedInAs;

  /// No description provided for @commonSignedInOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Signed in on this device'**
  String get commonSignedInOnThisDevice;

  /// No description provided for @commonSigningOut.
  ///
  /// In en, this message translates to:
  /// **'Signing out...'**
  String get commonSigningOut;

  /// No description provided for @commonSocialMediaOptional.
  ///
  /// In en, this message translates to:
  /// **'Social Media (optional)'**
  String get commonSocialMediaOptional;

  /// No description provided for @commonSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get commonSomethingWentWrong;

  /// No description provided for @commonSomethingWentWrong2.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get commonSomethingWentWrong2;

  /// No description provided for @commonSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get commonSort;

  /// No description provided for @commonStale.
  ///
  /// In en, this message translates to:
  /// **'stale'**
  String get commonStale;

  /// No description provided for @commonStartASync.
  ///
  /// In en, this message translates to:
  /// **'Start a sync'**
  String get commonStartASync;

  /// No description provided for @commonStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get commonStartDate;

  /// No description provided for @commonStartSync.
  ///
  /// In en, this message translates to:
  /// **'Start sync'**
  String get commonStartSync;

  /// No description provided for @commonState.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get commonState;

  /// No description provided for @commonStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get commonStatus;

  /// No description provided for @commonStaySignedIn.
  ///
  /// In en, this message translates to:
  /// **'Stay signed in'**
  String get commonStaySignedIn;

  /// No description provided for @commonStillStuck.
  ///
  /// In en, this message translates to:
  /// **'Still stuck?'**
  String get commonStillStuck;

  /// No description provided for @commonStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get commonStock;

  /// No description provided for @commonStockHealth.
  ///
  /// In en, this message translates to:
  /// **'Stock health'**
  String get commonStockHealth;

  /// No description provided for @commonStockHistory.
  ///
  /// In en, this message translates to:
  /// **'Stock history'**
  String get commonStockHistory;

  /// No description provided for @commonStockLevels.
  ///
  /// In en, this message translates to:
  /// **'Stock levels'**
  String get commonStockLevels;

  /// No description provided for @commonStockQuantity.
  ///
  /// In en, this message translates to:
  /// **'Stock quantity'**
  String get commonStockQuantity;

  /// No description provided for @commonStoredShopPin.
  ///
  /// In en, this message translates to:
  /// **'Stored shop pin'**
  String get commonStoredShopPin;

  /// No description provided for @commonSubcategoryOptional.
  ///
  /// In en, this message translates to:
  /// **'Subcategory (optional)'**
  String get commonSubcategoryOptional;

  /// No description provided for @commonSubmitRegistration.
  ///
  /// In en, this message translates to:
  /// **'Submit Registration'**
  String get commonSubmitRegistration;

  /// No description provided for @commonSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get commonSubmitted;

  /// No description provided for @commonSubscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get commonSubscription;

  /// No description provided for @commonSubscription2.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get commonSubscription2;

  /// No description provided for @commonSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get commonSupport;

  /// No description provided for @commonSupportHours.
  ///
  /// In en, this message translates to:
  /// **'Support hours'**
  String get commonSupportHours;

  /// No description provided for @commonSupportReplied.
  ///
  /// In en, this message translates to:
  /// **'Support replied'**
  String get commonSupportReplied;

  /// No description provided for @commonSwitchShop.
  ///
  /// In en, this message translates to:
  /// **'Switch shop'**
  String get commonSwitchShop;

  /// No description provided for @commonSyncAgain.
  ///
  /// In en, this message translates to:
  /// **'Sync again'**
  String get commonSyncAgain;

  /// No description provided for @commonSyncEvery.
  ///
  /// In en, this message translates to:
  /// **'Sync every'**
  String get commonSyncEvery;

  /// No description provided for @commonSyncHistory.
  ///
  /// In en, this message translates to:
  /// **'Sync history'**
  String get commonSyncHistory;

  /// No description provided for @commonSyncHistory2.
  ///
  /// In en, this message translates to:
  /// **'Sync history'**
  String get commonSyncHistory2;

  /// No description provided for @commonSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get commonSyncNow;

  /// No description provided for @commonSyncNow2.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get commonSyncNow2;

  /// No description provided for @commonSyncProgress.
  ///
  /// In en, this message translates to:
  /// **'Sync progress'**
  String get commonSyncProgress;

  /// No description provided for @commonSyncResult.
  ///
  /// In en, this message translates to:
  /// **'Sync result'**
  String get commonSyncResult;

  /// No description provided for @commonSyncSettings.
  ///
  /// In en, this message translates to:
  /// **'Sync settings'**
  String get commonSyncSettings;

  /// No description provided for @commonSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get commonSynced;

  /// No description provided for @commonSynced2.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get commonSynced2;

  /// No description provided for @commonTILL01.
  ///
  /// In en, this message translates to:
  /// **'TILL-01'**
  String get commonTILL01;

  /// No description provided for @commonTagline.
  ///
  /// In en, this message translates to:
  /// **'Tagline'**
  String get commonTagline;

  /// No description provided for @commonTaglineOptional.
  ///
  /// In en, this message translates to:
  /// **'Tagline (optional)'**
  String get commonTaglineOptional;

  /// No description provided for @commonTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get commonTakePhoto;

  /// No description provided for @commonTellUsWhatBroke.
  ///
  /// In en, this message translates to:
  /// **'Tell us what broke'**
  String get commonTellUsWhatBroke;

  /// No description provided for @commonTellUsWhatWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Tell us what went wrong'**
  String get commonTellUsWhatWentWrong;

  /// No description provided for @commonTerminals.
  ///
  /// In en, this message translates to:
  /// **'Terminals'**
  String get commonTerminals;

  /// No description provided for @commonTermsConditions.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get commonTermsConditions;

  /// No description provided for @commonTermsConditions2.
  ///
  /// In en, this message translates to:
  /// **'Terms & conditions'**
  String get commonTermsConditions2;

  /// No description provided for @commonTermsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of service'**
  String get commonTermsOfService;

  /// No description provided for @commonTermsOfService2.
  ///
  /// In en, this message translates to:
  /// **'Terms of service'**
  String get commonTermsOfService2;

  /// No description provided for @commonTermsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of use'**
  String get commonTermsOfUse;

  /// No description provided for @commonText.
  ///
  /// In en, this message translates to:
  /// **'-'**
  String get commonText;

  /// No description provided for @commonTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get commonTheme;

  /// No description provided for @commonThisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get commonThisDevice;

  /// No description provided for @commonThisTill.
  ///
  /// In en, this message translates to:
  /// **'This till'**
  String get commonThisTill;

  /// No description provided for @commonThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get commonThisWeek;

  /// No description provided for @commonTicketDetails.
  ///
  /// In en, this message translates to:
  /// **'Ticket details'**
  String get commonTicketDetails;

  /// No description provided for @commonTopProducts.
  ///
  /// In en, this message translates to:
  /// **'Top products'**
  String get commonTopProducts;

  /// No description provided for @commonTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get commonTotal;

  /// No description provided for @commonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get commonTryAgain;

  /// No description provided for @commonTryAgain2.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get commonTryAgain2;

  /// No description provided for @commonType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get commonType;

  /// No description provided for @commonType2.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get commonType2;

  /// No description provided for @commonUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get commonUnavailable;

  /// No description provided for @commonUnitSizeEG1.
  ///
  /// In en, this message translates to:
  /// **'Unit / size (e.g. 1 kg)'**
  String get commonUnitSizeEG1;

  /// No description provided for @commonUpdatePrice.
  ///
  /// In en, this message translates to:
  /// **'Update price'**
  String get commonUpdatePrice;

  /// No description provided for @commonUpdateStock.
  ///
  /// In en, this message translates to:
  /// **'Update Stock'**
  String get commonUpdateStock;

  /// No description provided for @commonUpdateStock2.
  ///
  /// In en, this message translates to:
  /// **'Update stock'**
  String get commonUpdateStock2;

  /// No description provided for @commonUpdateStock3.
  ///
  /// In en, this message translates to:
  /// **'Update stock'**
  String get commonUpdateStock3;

  /// No description provided for @commonUpdateStock4.
  ///
  /// In en, this message translates to:
  /// **'Update stock'**
  String get commonUpdateStock4;

  /// No description provided for @commonUpdateThePin.
  ///
  /// In en, this message translates to:
  /// **'Update the pin'**
  String get commonUpdateThePin;

  /// No description provided for @commonUpdatedInTheLast24h.
  ///
  /// In en, this message translates to:
  /// **'updated in the last 24h'**
  String get commonUpdatedInTheLast24h;

  /// No description provided for @commonUploadInventoryFile.
  ///
  /// In en, this message translates to:
  /// **'Upload inventory file'**
  String get commonUploadInventoryFile;

  /// No description provided for @commonValid.
  ///
  /// In en, this message translates to:
  /// **'valid'**
  String get commonValid;

  /// No description provided for @commonValid2.
  ///
  /// In en, this message translates to:
  /// **'Valid'**
  String get commonValid2;

  /// No description provided for @commonValid3.
  ///
  /// In en, this message translates to:
  /// **'Valid'**
  String get commonValid3;

  /// No description provided for @commonValidatingYourFile.
  ///
  /// In en, this message translates to:
  /// **'Validating your file...'**
  String get commonValidatingYourFile;

  /// No description provided for @commonValidity.
  ///
  /// In en, this message translates to:
  /// **'Validity'**
  String get commonValidity;

  /// No description provided for @commonVariantOptional.
  ///
  /// In en, this message translates to:
  /// **'Variant (optional)'**
  String get commonVariantOptional;

  /// No description provided for @commonVerification.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get commonVerification;

  /// No description provided for @commonVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get commonVerified;

  /// No description provided for @commonVerifyContinue.
  ///
  /// In en, this message translates to:
  /// **'Verify & continue'**
  String get commonVerifyContinue;

  /// No description provided for @commonVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get commonVersion;

  /// No description provided for @commonViewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get commonViewAll;

  /// No description provided for @commonViewAllQuestions.
  ///
  /// In en, this message translates to:
  /// **'View all questions'**
  String get commonViewAllQuestions;

  /// No description provided for @commonViewHistory.
  ///
  /// In en, this message translates to:
  /// **'View history'**
  String get commonViewHistory;

  /// No description provided for @commonViewHistory2.
  ///
  /// In en, this message translates to:
  /// **'View history'**
  String get commonViewHistory2;

  /// No description provided for @commonViewHistory3.
  ///
  /// In en, this message translates to:
  /// **'View history'**
  String get commonViewHistory3;

  /// No description provided for @commonViewImportHistory.
  ///
  /// In en, this message translates to:
  /// **'View import history'**
  String get commonViewImportHistory;

  /// No description provided for @commonViewImportHistory2.
  ///
  /// In en, this message translates to:
  /// **'View import history'**
  String get commonViewImportHistory2;

  /// No description provided for @commonViewMySupportTickets.
  ///
  /// In en, this message translates to:
  /// **'View my support tickets'**
  String get commonViewMySupportTickets;

  /// No description provided for @commonViewMySupportTickets2.
  ///
  /// In en, this message translates to:
  /// **'View my support tickets'**
  String get commonViewMySupportTickets2;

  /// No description provided for @commonViewResults.
  ///
  /// In en, this message translates to:
  /// **'View Results'**
  String get commonViewResults;

  /// No description provided for @commonViewRowReport.
  ///
  /// In en, this message translates to:
  /// **'View row report'**
  String get commonViewRowReport;

  /// No description provided for @commonViewSyncHistory.
  ///
  /// In en, this message translates to:
  /// **'View sync history'**
  String get commonViewSyncHistory;

  /// No description provided for @commonViewsToday.
  ///
  /// In en, this message translates to:
  /// **'Views today'**
  String get commonViewsToday;

  /// No description provided for @commonVisibility.
  ///
  /// In en, this message translates to:
  /// **'Visibility'**
  String get commonVisibility;

  /// No description provided for @commonVsYesterday.
  ///
  /// In en, this message translates to:
  /// **'vs yesterday'**
  String get commonVsYesterday;

  /// No description provided for @commonWebsiteOptional.
  ///
  /// In en, this message translates to:
  /// **'Website (optional)'**
  String get commonWebsiteOptional;

  /// No description provided for @commonWeeklySchedule.
  ///
  /// In en, this message translates to:
  /// **'Weekly schedule'**
  String get commonWeeklySchedule;

  /// No description provided for @commonWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get commonWelcomeBack;

  /// No description provided for @commonWelcomeBack2.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get commonWelcomeBack2;

  /// No description provided for @commonWelcomeToHyperLocal.
  ///
  /// In en, this message translates to:
  /// **'Welcome to HyperLocal!'**
  String get commonWelcomeToHyperLocal;

  /// No description provided for @commonWelcomeToPasslyBiz.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Passly Biz!'**
  String get commonWelcomeToPasslyBiz;

  /// No description provided for @commonWhatHappened.
  ///
  /// In en, this message translates to:
  /// **'What happened?'**
  String get commonWhatHappened;

  /// No description provided for @commonWhatHappensNext.
  ///
  /// In en, this message translates to:
  /// **'What happens next'**
  String get commonWhatHappensNext;

  /// No description provided for @commonWhatIsAffected.
  ///
  /// In en, this message translates to:
  /// **'What is affected?'**
  String get commonWhatIsAffected;

  /// No description provided for @commonWhatIsThisAbout.
  ///
  /// In en, this message translates to:
  /// **'What is this about?'**
  String get commonWhatIsThisAbout;

  /// No description provided for @commonWhatShouldBePulled.
  ///
  /// In en, this message translates to:
  /// **'What should be pulled?'**
  String get commonWhatShouldBePulled;

  /// No description provided for @commonWhatWeCollectAndWhy.
  ///
  /// In en, this message translates to:
  /// **'What we collect and why'**
  String get commonWhatWeCollectAndWhy;

  /// No description provided for @commonWhatYouCanDo.
  ///
  /// In en, this message translates to:
  /// **'What you can do'**
  String get commonWhatYouCanDo;

  /// No description provided for @commonWhatYouCanDoHere.
  ///
  /// In en, this message translates to:
  /// **'What you can do here'**
  String get commonWhatYouCanDoHere;

  /// No description provided for @commonWhatsAppNumber.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp number'**
  String get commonWhatsAppNumber;

  /// No description provided for @commonWhereYouAreSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Where you are signed in'**
  String get commonWhereYouAreSignedIn;

  /// No description provided for @commonWriteAnotherMessage.
  ///
  /// In en, this message translates to:
  /// **'Write another message'**
  String get commonWriteAnotherMessage;

  /// No description provided for @commonWriteToUs.
  ///
  /// In en, this message translates to:
  /// **'Write to us'**
  String get commonWriteToUs;

  /// No description provided for @commonYouHaveUnsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes'**
  String get commonYouHaveUnsavedChanges;

  /// No description provided for @commonYourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get commonYourName;

  /// No description provided for @commonYourReport.
  ///
  /// In en, this message translates to:
  /// **'Your report'**
  String get commonYourReport;

  /// No description provided for @connectivityBannerYouReOfflineChangesCan.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — changes can\'t be saved until you\'re back online.'**
  String get connectivityBannerYouReOfflineChangesCan;

  /// No description provided for @contactSupportScreenDescribeTheProblemInYour.
  ///
  /// In en, this message translates to:
  /// **'Describe the problem in your own words'**
  String get contactSupportScreenDescribeTheProblemInYour;

  /// No description provided for @contactSupportScreenIncludeMyAccountAndShop.
  ///
  /// In en, this message translates to:
  /// **'Include my account and shop'**
  String get contactSupportScreenIncludeMyAccountAndShop;

  /// No description provided for @contactSupportScreenPasteTheCopiedTextInto.
  ///
  /// In en, this message translates to:
  /// **'Paste the copied text into an e-mail to {email}.'**
  String contactSupportScreenPasteTheCopiedTextInto(Object email);

  /// No description provided for @contactSupportScreenSavesARoundTripSupport.
  ///
  /// In en, this message translates to:
  /// **'Saves a round-trip - support can look up the right shop'**
  String get contactSupportScreenSavesARoundTripSupport;

  /// No description provided for @contactSupportScreenSendingFilesASupportTicket.
  ///
  /// In en, this message translates to:
  /// **'Sending files a support ticket with your topic, account and shop attached - the same details support needs to answer quickly. Its status stays visible under My support tickets, and the text can still be copied to send it by e-mail.'**
  String get contactSupportScreenSendingFilesASupportTicket;

  /// No description provided for @contactSupportScreenStatusStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status: {statusLabel}'**
  String contactSupportScreenStatusStatusLabel(Object statusLabel);

  /// No description provided for @contactSupportScreenYourMessageBecomesATracked.
  ///
  /// In en, this message translates to:
  /// **'Your message becomes a tracked ticket'**
  String get contactSupportScreenYourMessageBecomesATracked;

  /// No description provided for @contactSupportScreenYourMessageIsInThe.
  ///
  /// In en, this message translates to:
  /// **'Your message is in the support queue.'**
  String get contactSupportScreenYourMessageIsInThe;

  /// No description provided for @createOfferScreenOfferCreatedAndLinkedTo.
  ///
  /// In en, this message translates to:
  /// **'Offer created and linked to your products'**
  String get createOfferScreenOfferCreatedAndLinkedTo;

  /// No description provided for @createOfferScreenOffersNotAvailableOnYour.
  ///
  /// In en, this message translates to:
  /// **'Offers not available on your plan'**
  String get createOfferScreenOffersNotAvailableOnYour;

  /// No description provided for @createOfferScreenPrice.
  ///
  /// In en, this message translates to:
  /// **'₹{price}'**
  String createOfferScreenPrice(Object price);

  /// No description provided for @createOfferScreenTermsConditionsOptional.
  ///
  /// In en, this message translates to:
  /// **'Terms & conditions (optional)'**
  String get createOfferScreenTermsConditionsOptional;

  /// No description provided for @createOfferScreenUpgradeYourPlanToCreate.
  ///
  /// In en, this message translates to:
  /// **'Upgrade your plan to create discount offers. Your current plan does not include offers.'**
  String get createOfferScreenUpgradeYourPlanToCreate;

  /// No description provided for @createProfileScreenAShortDescriptionOfYour.
  ///
  /// In en, this message translates to:
  /// **'A short description of your shop'**
  String get createProfileScreenAShortDescriptionOfYour;

  /// No description provided for @createProfileScreenContactNumberOptional.
  ///
  /// In en, this message translates to:
  /// **'Contact Number (optional)'**
  String get createProfileScreenContactNumberOptional;

  /// No description provided for @createProfileScreenCreateYourShopkeeperProfile.
  ///
  /// In en, this message translates to:
  /// **'Create Your Shopkeeper Profile'**
  String get createProfileScreenCreateYourShopkeeperProfile;

  /// No description provided for @createProfileScreenSetUpYourShopTo.
  ///
  /// In en, this message translates to:
  /// **'Set up your shop to start managing products and inventory.'**
  String get createProfileScreenSetUpYourShopTo;

  /// No description provided for @createProfileScreenYouExampleCom.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get createProfileScreenYouExampleCom;

  /// No description provided for @dashboardScreenCompleteShopVerificationToPublish.
  ///
  /// In en, this message translates to:
  /// **'Complete shop verification to publish to customers'**
  String get dashboardScreenCompleteShopVerificationToPublish;

  /// No description provided for @dashboardScreenCount.
  ///
  /// In en, this message translates to:
  /// **'{count}'**
  String dashboardScreenCount(Object count);

  /// No description provided for @dashboardScreenFailedImportNameFailedImportRowsRowSCould.
  ///
  /// In en, this message translates to:
  /// **'{failedImportName} — {failedImportRows} row(s) could not be applied'**
  String dashboardScreenFailedImportNameFailedImportRowsRowSCould(
    Object failedImportName,
    Object failedImportRows,
  );

  /// No description provided for @dashboardScreenGreetingFirstName.
  ///
  /// In en, this message translates to:
  /// **'{_greeting}, {_firstName}'**
  String dashboardScreenGreetingFirstName(Object _greeting, Object _firstName);

  /// No description provided for @dashboardScreenLabelValue.
  ///
  /// In en, this message translates to:
  /// **'{label}: {value}'**
  String dashboardScreenLabelValue(Object label, Object value);

  /// No description provided for @dashboardScreenLowStockLowValueFlaggedLabel.
  ///
  /// In en, this message translates to:
  /// **'{lowStock} low {value}{flaggedLabel}'**
  String dashboardScreenLowStockLowValueFlaggedLabel(
    Object lowStock,
    Object value,
    Object flaggedLabel,
  );

  /// No description provided for @dashboardScreenNothingYetUpdatesWillAppear.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet — updates will appear here.'**
  String get dashboardScreenNothingYetUpdatesWillAppear;

  /// No description provided for @dashboardScreenQtyQuantity.
  ///
  /// In en, this message translates to:
  /// **'qty {quantity}'**
  String dashboardScreenQtyQuantity(Object quantity);

  /// No description provided for @dashboardScreenStaleCountProductSNotUpdated.
  ///
  /// In en, this message translates to:
  /// **'{staleCount} product(s) not updated in a while'**
  String dashboardScreenStaleCountProductSNotUpdated(Object staleCount);

  /// No description provided for @dashboardScreenUnreadNew.
  ///
  /// In en, this message translates to:
  /// **'{unread} new'**
  String dashboardScreenUnreadNew(Object unread);

  /// No description provided for @dashboardScreenUnreadNotificationsUnreadNotificationS.
  ///
  /// In en, this message translates to:
  /// **'{unreadNotifications} unread notification(s)'**
  String dashboardScreenUnreadNotificationsUnreadNotificationS(
    Object unreadNotifications,
  );

  /// No description provided for @dashboardScreenWelcomeBackToYourBusiness.
  ///
  /// In en, this message translates to:
  /// **'Welcome back to your business dashboard.'**
  String get dashboardScreenWelcomeBackToYourBusiness;

  /// No description provided for @dashboardScreenYouDoNotHaveAccess.
  ///
  /// In en, this message translates to:
  /// **'You do not have access to this shop.'**
  String get dashboardScreenYouDoNotHaveAccess;

  /// No description provided for @dashboardScreenYourAccountIsReadyAdd.
  ///
  /// In en, this message translates to:
  /// **'Your account is ready. Add your first store to start managing products, inventory and offers — or complete your profile details from the Account tab anytime.'**
  String get dashboardScreenYourAccountIsReadyAdd;

  /// No description provided for @debouncedSearchFieldRemoveTerm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{term}\"'**
  String debouncedSearchFieldRemoveTerm(Object term);

  /// No description provided for @editProfileScreenContactSupportToChangeYour.
  ///
  /// In en, this message translates to:
  /// **'Contact support to change your phone number'**
  String get editProfileScreenContactSupportToChangeYour;

  /// No description provided for @editShopScreenAOneLinePitchCustomers.
  ///
  /// In en, this message translates to:
  /// **'A one-line pitch customers see first'**
  String get editShopScreenAOneLinePitchCustomers;

  /// No description provided for @editShopScreenOnlyTheFieldsYouChanged.
  ///
  /// In en, this message translates to:
  /// **'Only the fields you changed are sent to the server.'**
  String get editShopScreenOnlyTheFieldsYouChanged;

  /// No description provided for @forgotPasswordScreenEnterYourEmailOrPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter your email or phone number and we\'ll send you a link to reset your password.'**
  String get forgotPasswordScreenEnterYourEmailOrPhone;

  /// No description provided for @forgotPasswordScreenIfAnAccountExistsWith.
  ///
  /// In en, this message translates to:
  /// **'If an account exists with this email/phone, you\'ll receive a reset link shortly.'**
  String get forgotPasswordScreenIfAnAccountExistsWith;

  /// No description provided for @holidaysSectionAddHolidayLabel.
  ///
  /// In en, this message translates to:
  /// **'Add holiday — {label}'**
  String holidaysSectionAddHolidayLabel(Object label);

  /// No description provided for @holidaysSectionDaysTheShopStaysClosed.
  ///
  /// In en, this message translates to:
  /// **'Days the shop stays closed — customers are told in advance.'**
  String get holidaysSectionDaysTheShopStaysClosed;

  /// No description provided for @holidaysSectionDiwaliStaffTraining.
  ///
  /// In en, this message translates to:
  /// **'Diwali, Staff training…'**
  String get holidaysSectionDiwaliStaffTraining;

  /// No description provided for @importCenterScreenBringProductsIntoYourShop.
  ///
  /// In en, this message translates to:
  /// **'Bring products into your shop — manually or in bulk. Choose a method below to get started.'**
  String get importCenterScreenBringProductsIntoYourShop;

  /// No description provided for @importCenterScreenBulkUploadAWorkbookTo.
  ///
  /// In en, this message translates to:
  /// **'Bulk-upload a workbook to update stock, prices or catalog. Download a sample template, fill it in, then preview before applying.'**
  String get importCenterScreenBulkUploadAWorkbookTo;

  /// No description provided for @importCenterScreenGetTheImportTemplateWorkbook.
  ///
  /// In en, this message translates to:
  /// **'Get the import template workbook'**
  String get importCenterScreenGetTheImportTemplateWorkbook;

  /// No description provided for @importCenterScreenValidRowsValidErrorRowsErrors.
  ///
  /// In en, this message translates to:
  /// **'{validRows} valid, {errorRows} errors'**
  String importCenterScreenValidRowsValidErrorRowsErrors(
    Object validRows,
    Object errorRows,
  );

  /// No description provided for @importHistoryScreenExcelFilesYouUploadWill.
  ///
  /// In en, this message translates to:
  /// **'Excel files you upload will appear here with their row-level outcomes.'**
  String get importHistoryScreenExcelFilesYouUploadWill;

  /// No description provided for @importHistoryScreenRowsTotalRowsSuccessSuccessRowsFailed.
  ///
  /// In en, this message translates to:
  /// **'Rows {totalRows} · Success {successRows} · Failed {failedRowCount}'**
  String importHistoryScreenRowsTotalRowsSuccessSuccessRowsFailed(
    Object totalRows,
    Object successRows,
    Object failedRowCount,
  );

  /// No description provided for @importPreviewScreenRowRowNumberValue.
  ///
  /// In en, this message translates to:
  /// **'Row {rowNumber}{value}'**
  String importPreviewScreenRowRowNumberValue(Object rowNumber, Object value);

  /// No description provided for @importPreviewScreenShowOnlyValidationErrors.
  ///
  /// In en, this message translates to:
  /// **'Show only validation errors'**
  String get importPreviewScreenShowOnlyValidationErrors;

  /// No description provided for @importPreviewScreenValidWillBeAppliedTo.
  ///
  /// In en, this message translates to:
  /// **'Valid — will be applied to inventory'**
  String get importPreviewScreenValidWillBeAppliedTo;

  /// No description provided for @importPreviewScreenValue.
  ///
  /// In en, this message translates to:
  /// **'{value}'**
  String importPreviewScreenValue(Object value);

  /// No description provided for @importPreviewScreenValueValue2.
  ///
  /// In en, this message translates to:
  /// **'{value} — {value2}'**
  String importPreviewScreenValueValue2(Object value, Object value2);

  /// No description provided for @importProcessingScreenApplyingRowsToYourInventory.
  ///
  /// In en, this message translates to:
  /// **'Applying rows to your inventory…'**
  String get importProcessingScreenApplyingRowsToYourInventory;

  /// No description provided for @importProcessingScreenThisUsuallyTakesAFew.
  ///
  /// In en, this message translates to:
  /// **'This usually takes a few seconds.'**
  String get importProcessingScreenThisUsuallyTakesAFew;

  /// No description provided for @importProcessingScreenViewErrorsFailed.
  ///
  /// In en, this message translates to:
  /// **'View Errors ({failed})'**
  String importProcessingScreenViewErrorsFailed(Object failed);

  /// No description provided for @importReportSheetAllRowsTotal.
  ///
  /// In en, this message translates to:
  /// **'All rows ({total})'**
  String importReportSheetAllRowsTotal(Object total);

  /// No description provided for @importReportSheetCouldNotLoadTheReport.
  ///
  /// In en, this message translates to:
  /// **'Could not load the report for this import.'**
  String get importReportSheetCouldNotLoadTheReport;

  /// No description provided for @importReportSheetFailedErrors.
  ///
  /// In en, this message translates to:
  /// **'Failed ({errors})'**
  String importReportSheetFailedErrors(Object errors);

  /// No description provided for @importReportSheetRowRowNumberValue.
  ///
  /// In en, this message translates to:
  /// **'Row {rowNumber}{value}'**
  String importReportSheetRowRowNumberValue(Object rowNumber, Object value);

  /// No description provided for @importReportSheetStatusLabelTotalRowsRowsSuccessRowsSuccess.
  ///
  /// In en, this message translates to:
  /// **'{statusLabel} · {totalRows} rows · {successRows} success, {failedRowCount} failed'**
  String importReportSheetStatusLabelTotalRowsRowsSuccessRowsSuccess(
    Object statusLabel,
    Object totalRows,
    Object successRows,
    Object failedRowCount,
  );

  /// No description provided for @importReportSheetValueValue2.
  ///
  /// In en, this message translates to:
  /// **'{value} — {value2}'**
  String importReportSheetValueValue2(Object value, Object value2);

  /// No description provided for @importResultScreenCouldNotOpenThisImport.
  ///
  /// In en, this message translates to:
  /// **'Could not open this import'**
  String get importResultScreenCouldNotOpenThisImport;

  /// No description provided for @importResultScreenErrorRowsRowSCouldNot.
  ///
  /// In en, this message translates to:
  /// **'{errorRows} row(s) could not be imported.'**
  String importResultScreenErrorRowsRowSCouldNot(Object errorRows);

  /// No description provided for @importResultScreenThisImportIsNoLonger.
  ///
  /// In en, this message translates to:
  /// **'This import is no longer available.'**
  String get importResultScreenThisImportIsNoLonger;

  /// No description provided for @importUploadScreenExcelImportNotAvailableOn.
  ///
  /// In en, this message translates to:
  /// **'Excel import not available on your plan'**
  String get importUploadScreenExcelImportNotAvailableOn;

  /// No description provided for @importUploadScreenOnlyXlsxWorkbooksAreAccepted.
  ///
  /// In en, this message translates to:
  /// **'Only .xlsx workbooks are accepted. Download the sample from the Import Center to see the exact columns.'**
  String get importUploadScreenOnlyXlsxWorkbooksAreAccepted;

  /// No description provided for @importUploadScreenUpgradeYourPlanToBulk.
  ///
  /// In en, this message translates to:
  /// **'Upgrade your plan to bulk-upload a workbook. Your current plan does not include bulk import.'**
  String get importUploadScreenUpgradeYourPlanToBulk;

  /// No description provided for @importUploadScreenUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get importUploadScreenUploading;

  /// No description provided for @importUploadScreenYourFileIsBeingChecked.
  ///
  /// In en, this message translates to:
  /// **'Your file is being checked row by row. Nothing is applied yet.'**
  String get importUploadScreenYourFileIsBeingChecked;

  /// No description provided for @insightsDrillDownScreenCouldNotLoadThisReport.
  ///
  /// In en, this message translates to:
  /// **'Could not load this report'**
  String get insightsDrillDownScreenCouldNotLoadThisReport;

  /// No description provided for @insightsDrillDownScreenDailyUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Daily {unitLabel}'**
  String insightsDrillDownScreenDailyUnitLabel(Object unitLabel);

  /// No description provided for @insightsDrillDownScreenDaysDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String insightsDrillDownScreenDaysDays(Object days);

  /// No description provided for @insightsDrillDownScreenNoCustomerActivityInThis.
  ///
  /// In en, this message translates to:
  /// **'No customer activity in this window yet.'**
  String get insightsDrillDownScreenNoCustomerActivityInThis;

  /// No description provided for @insightsDrillDownScreenPeakLabel.
  ///
  /// In en, this message translates to:
  /// **'Peak {label}'**
  String insightsDrillDownScreenPeakLabel(Object label);

  /// No description provided for @insightsDrillDownScreenRank.
  ///
  /// In en, this message translates to:
  /// **'{rank}'**
  String insightsDrillDownScreenRank(Object rank);

  /// No description provided for @insightsDrillDownScreenTopProductsUpToKInsightsMaxTopProducts.
  ///
  /// In en, this message translates to:
  /// **'Top products (up to {kInsightsMaxTopProducts})'**
  String insightsDrillDownScreenTopProductsUpToKInsightsMaxTopProducts(
    Object kInsightsMaxTopProducts,
  );

  /// No description provided for @insightsDrillDownScreenTotalInLastRangeDaysDays.
  ///
  /// In en, this message translates to:
  /// **'Total in last {rangeDays} days'**
  String insightsDrillDownScreenTotalInLastRangeDaysDays(Object rangeDays);

  /// No description provided for @insightsDrillDownScreenTotalUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'{total} {unitLabel}'**
  String insightsDrillDownScreenTotalUnitLabel(Object total, Object unitLabel);

  /// No description provided for @insightsDrillDownScreenValue.
  ///
  /// In en, this message translates to:
  /// **'{value}'**
  String insightsDrillDownScreenValue(Object value);

  /// No description provided for @insightsDrillDownScreenViews.
  ///
  /// In en, this message translates to:
  /// **'{views}'**
  String insightsDrillDownScreenViews(Object views);

  /// No description provided for @insightsDrillDownScreenViewsUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'{views} {unitLabel}'**
  String insightsDrillDownScreenViewsUnitLabel(Object views, Object unitLabel);

  /// No description provided for @insightsScreenAllMetricsAreComputedBy.
  ///
  /// In en, this message translates to:
  /// **'All metrics are computed by the backend from live customer activity.'**
  String get insightsScreenAllMetricsAreComputedBy;

  /// No description provided for @insightsScreenBusiestHourLabelViewsViews.
  ///
  /// In en, this message translates to:
  /// **'Busiest hour: {label} · {views} views'**
  String insightsScreenBusiestHourLabelViewsViews(Object label, Object views);

  /// No description provided for @insightsScreenCountShareLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} · {shareLabel}'**
  String insightsScreenCountShareLabel(Object count, Object shareLabel);

  /// No description provided for @insightsScreenCurrentInventorySnapshotFreshnessUses.
  ///
  /// In en, this message translates to:
  /// **'Current inventory snapshot; freshness uses the last 24h.'**
  String get insightsScreenCurrentInventorySnapshotFreshnessUses;

  /// No description provided for @insightsScreenDaysDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String insightsScreenDaysDays(Object days);

  /// No description provided for @insightsScreenFreshFreshStaleStale.
  ///
  /// In en, this message translates to:
  /// **'{fresh} fresh · {stale} stale'**
  String insightsScreenFreshFreshStaleStale(Object fresh, Object stale);

  /// No description provided for @insightsScreenLiveShopSnapshotInventoryListings.
  ///
  /// In en, this message translates to:
  /// **'Live shop snapshot · inventory, listings, offers and profile, computed from current data.'**
  String get insightsScreenLiveShopSnapshotInventoryListings;

  /// No description provided for @insightsScreenNothingHasBeenRecordedIn.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been recorded in the last {rangeDays} days. These reports fill in automatically once customers view your shop and products.'**
  String insightsScreenNothingHasBeenRecordedIn(Object rangeDays);

  /// No description provided for @insightsScreenQueryCount.
  ///
  /// In en, this message translates to:
  /// **'{query} · {count}'**
  String insightsScreenQueryCount(Object query, Object count);

  /// No description provided for @insightsScreenReportsNotAvailableOnYour.
  ///
  /// In en, this message translates to:
  /// **'Reports not available on your plan'**
  String get insightsScreenReportsNotAvailableOnYour;

  /// No description provided for @insightsScreenSalesTotalsAndRevenueAre.
  ///
  /// In en, this message translates to:
  /// **'Sales totals and revenue are not available. The metrics below show customer engagement, not completed sales.'**
  String get insightsScreenSalesTotalsAndRevenueAre;

  /// No description provided for @insightsScreenScoreLabelOfTotalProductsProducts.
  ///
  /// In en, this message translates to:
  /// **'{scoreLabel} of {totalProducts} products'**
  String insightsScreenScoreLabelOfTotalProductsProducts(
    Object scoreLabel,
    Object totalProducts,
  );

  /// No description provided for @insightsScreenSetUpYourShopTo.
  ///
  /// In en, this message translates to:
  /// **'Set up your shop to unlock its reports and insights.'**
  String get insightsScreenSetUpYourShopTo;

  /// No description provided for @insightsScreenToday.
  ///
  /// In en, this message translates to:
  /// **'{today}'**
  String insightsScreenToday(Object today);

  /// No description provided for @insightsScreenTrailingRangeDaysDaysComputedFrom.
  ///
  /// In en, this message translates to:
  /// **'Trailing {rangeDays} days, computed from live customer activity.'**
  String insightsScreenTrailingRangeDaysDaysComputedFrom(Object rangeDays);

  /// No description provided for @insightsScreenUpgradeYourPlanToSee.
  ///
  /// In en, this message translates to:
  /// **'Upgrade your plan to see customer activity and trends. Your current plan does not include reports.'**
  String get insightsScreenUpgradeYourPlanToSee;

  /// No description provided for @insightsScreenValue.
  ///
  /// In en, this message translates to:
  /// **'{value}'**
  String insightsScreenValue(Object value);

  /// No description provided for @insightsScreenViewsViews.
  ///
  /// In en, this message translates to:
  /// **'{views} views'**
  String insightsScreenViewsViews(Object views);

  /// No description provided for @inventoryDashboardScreenCountsComeStraightFromYour.
  ///
  /// In en, this message translates to:
  /// **'Counts come straight from your shop\'s live inventory.'**
  String get inventoryDashboardScreenCountsComeStraightFromYour;

  /// No description provided for @inventoryImportScreenAllRowsValidatedSuccessfullyReview.
  ///
  /// In en, this message translates to:
  /// **'All rows validated successfully.\nReview the summary above and confirm to apply changes.'**
  String get inventoryImportScreenAllRowsValidatedSuccessfullyReview;

  /// No description provided for @inventoryImportScreenExcelImportNotAvailableOn.
  ///
  /// In en, this message translates to:
  /// **'Excel import not available on your plan'**
  String get inventoryImportScreenExcelImportNotAvailableOn;

  /// No description provided for @inventoryImportScreenImportProductsFromExcel.
  ///
  /// In en, this message translates to:
  /// **'Import products from Excel'**
  String get inventoryImportScreenImportProductsFromExcel;

  /// No description provided for @inventoryImportScreenRowRowNumber.
  ///
  /// In en, this message translates to:
  /// **'Row {rowNumber}'**
  String inventoryImportScreenRowRowNumber(Object rowNumber);

  /// No description provided for @inventoryImportScreenUpgradeYourPlanToBulk.
  ///
  /// In en, this message translates to:
  /// **'Upgrade your plan to bulk-import a workbook. Your current plan does not include bulk import.'**
  String get inventoryImportScreenUpgradeYourPlanToBulk;

  /// No description provided for @inventoryImportScreenUploadAnXlsxWorkbookTo.
  ///
  /// In en, this message translates to:
  /// **'Upload an .xlsx workbook to bulk-add or update your shop\'s inventory. The file is validated before you commit changes.'**
  String get inventoryImportScreenUploadAnXlsxWorkbookTo;

  /// No description provided for @inventoryImportScreenValidRowsValidErrorRowsErrors.
  ///
  /// In en, this message translates to:
  /// **'{validRows} valid, {errorRows} errors'**
  String inventoryImportScreenValidRowsValidErrorRowsErrors(
    Object validRows,
    Object errorRows,
  );

  /// No description provided for @inventoryImportScreenValue.
  ///
  /// In en, this message translates to:
  /// **'{value}'**
  String inventoryImportScreenValue(Object value);

  /// No description provided for @inventoryListScreenMatchedOfTotalProducts.
  ///
  /// In en, this message translates to:
  /// **'{matched} of {total} products'**
  String inventoryListScreenMatchedOfTotalProducts(
    Object matched,
    Object total,
  );

  /// No description provided for @inventoryListScreenNoProductsMatchYourFilters.
  ///
  /// In en, this message translates to:
  /// **'No products match your filters'**
  String get inventoryListScreenNoProductsMatchYourFilters;

  /// No description provided for @inventoryListScreenNoProductsMatchYourSearch.
  ///
  /// In en, this message translates to:
  /// **'No products match your search'**
  String get inventoryListScreenNoProductsMatchYourSearch;

  /// No description provided for @inventoryListScreenQuantityUnitsValue.
  ///
  /// In en, this message translates to:
  /// **'{quantity} units · {value}'**
  String inventoryListScreenQuantityUnitsValue(Object quantity, Object value);

  /// No description provided for @inventoryListScreenSearchNameBrandOrSKU.
  ///
  /// In en, this message translates to:
  /// **'Search name, brand or SKU'**
  String get inventoryListScreenSearchNameBrandOrSKU;

  /// No description provided for @inventorySharedAddProductsOrImportThem.
  ///
  /// In en, this message translates to:
  /// **'Add products or import them from Excel first.'**
  String get inventorySharedAddProductsOrImportThem;

  /// No description provided for @inventorySharedPleaseCheckYourConnectionAnd.
  ///
  /// In en, this message translates to:
  /// **'Please check your connection and retry.'**
  String get inventorySharedPleaseCheckYourConnectionAnd;

  /// No description provided for @inventorySharedQuantityUnitsLabel.
  ///
  /// In en, this message translates to:
  /// **'{quantity} units · {label}'**
  String inventorySharedQuantityUnitsLabel(Object quantity, Object label);

  /// No description provided for @inventorySharedTotalEntrValue.
  ///
  /// In en, this message translates to:
  /// **'{total} entr{value}'**
  String inventorySharedTotalEntrValue(Object total, Object value);

  /// No description provided for @inventorySharedValue.
  ///
  /// In en, this message translates to:
  /// **'{value}'**
  String inventorySharedValue(Object value);

  /// No description provided for @inventorySharedYouDoNotHaveAccess.
  ///
  /// In en, this message translates to:
  /// **'You do not have access to this shop\'s inventory.'**
  String get inventorySharedYouDoNotHaveAccess;

  /// No description provided for @inventorySyncStatusScreenLength.
  ///
  /// In en, this message translates to:
  /// **'{length}'**
  String inventorySyncStatusScreenLength(Object length);

  /// No description provided for @inventorySyncStatusScreenSourceLabelsComeFromThe.
  ///
  /// In en, this message translates to:
  /// **'Source labels come from the server — they record how each stock figure last changed.'**
  String get inventorySyncStatusScreenSourceLabelsComeFromThe;

  /// No description provided for @locationCaptureScreenCouldNotOpenYourPhone.
  ///
  /// In en, this message translates to:
  /// **'Could not open your phone settings from here.'**
  String get locationCaptureScreenCouldNotOpenYourPhone;

  /// No description provided for @locationCaptureScreenDetectedAddressYouMayCorrect.
  ///
  /// In en, this message translates to:
  /// **'Detected address — you may correct the text'**
  String get locationCaptureScreenDetectedAddressYouMayCorrect;

  /// No description provided for @locationCaptureScreenDifferentLocationDetected.
  ///
  /// In en, this message translates to:
  /// **'Different location detected'**
  String get locationCaptureScreenDifferentLocationDetected;

  /// No description provided for @locationCaptureScreenEnterYourShopAddressIn.
  ///
  /// In en, this message translates to:
  /// **'Enter your shop address in the form.'**
  String get locationCaptureScreenEnterYourShopAddressIn;

  /// No description provided for @locationCaptureScreenForBestAccuracy.
  ///
  /// In en, this message translates to:
  /// **'For best accuracy:'**
  String get locationCaptureScreenForBestAccuracy;

  /// No description provided for @locationCaptureScreenGPSAccuracyIsAnEstimate.
  ///
  /// In en, this message translates to:
  /// **'GPS accuracy is an estimate, not a guarantee.'**
  String get locationCaptureScreenGPSAccuracyIsAnEstimate;

  /// No description provided for @locationCaptureScreenGPSCoordinatesRemainThePrimary.
  ///
  /// In en, this message translates to:
  /// **'GPS coordinates remain the primary location; the address is supporting information.'**
  String get locationCaptureScreenGPSCoordinatesRemainThePrimary;

  /// No description provided for @locationCaptureScreenTapTheMapToPlace.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to place your shop pin.'**
  String get locationCaptureScreenTapTheMapToPlace;

  /// No description provided for @locationCaptureScreenTapTheMapToPlace2.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to place the pin at your shop ENTRANCE.'**
  String get locationCaptureScreenTapTheMapToPlace2;

  /// No description provided for @locationCaptureScreenUseMyCurrentLocationInstead.
  ///
  /// In en, this message translates to:
  /// **'Use my current location instead'**
  String get locationCaptureScreenUseMyCurrentLocationInstead;

  /// No description provided for @locationCaptureScreenValueAccuracyValue2AddressSummarySave.
  ///
  /// In en, this message translates to:
  /// **'{value}Accuracy: {value2}\n\n{addressSummary}\n\nSave this as your shop entrance location?'**
  String locationCaptureScreenValueAccuracyValue2AddressSummarySave(
    Object value,
    Object value2,
    Object addressSummary,
  );

  /// No description provided for @locationCaptureScreenYourLocationIsNotAccurate.
  ///
  /// In en, this message translates to:
  /// **'Your location is not accurate enough. Move closer to your shop for better accuracy.'**
  String get locationCaptureScreenYourLocationIsNotAccurate;

  /// No description provided for @locationCaptureScreenYourSelectedShopLocationIs.
  ///
  /// In en, this message translates to:
  /// **'Your selected shop location is {value} km away from your current GPS location.\n\nAre you sure this is your shop?'**
  String locationCaptureScreenYourSelectedShopLocationIs(Object value);

  /// No description provided for @loginScreenNewHereCreateAnAccount.
  ///
  /// In en, this message translates to:
  /// **'New here? Create an account'**
  String get loginScreenNewHereCreateAnAccount;

  /// No description provided for @loginScreenSignInWithThePhone.
  ///
  /// In en, this message translates to:
  /// **'Sign in with the phone number or email you registered.'**
  String get loginScreenSignInWithThePhone;

  /// No description provided for @logoutConfirmationScreenLogOutOfPasslyBusiness.
  ///
  /// In en, this message translates to:
  /// **'Log out of Passly Business?'**
  String get logoutConfirmationScreenLogOutOfPasslyBusiness;

  /// No description provided for @logoutConfirmationScreenYouWillNeedToSign.
  ///
  /// In en, this message translates to:
  /// **'You will need to sign in with the same Google account before you can manage your shop again.'**
  String get logoutConfirmationScreenYouWillNeedToSign;

  /// No description provided for @lowStockScreenCountItemValueImmediateRestocking.
  ///
  /// In en, this message translates to:
  /// **'{count} item{value} immediate restocking'**
  String lowStockScreenCountItemValueImmediateRestocking(
    Object count,
    Object value,
  );

  /// No description provided for @lowStockScreenNoRestockNeedsMatchYour.
  ///
  /// In en, this message translates to:
  /// **'No restock needs match your search'**
  String get lowStockScreenNoRestockNeedsMatchYour;

  /// No description provided for @lowStockScreenNothingIsAtOrBelow.
  ///
  /// In en, this message translates to:
  /// **'Nothing is at or below its low-stock threshold right now.'**
  String get lowStockScreenNothingIsAtOrBelow;

  /// No description provided for @lowStockScreenQuantityUnitsLeft.
  ///
  /// In en, this message translates to:
  /// **'{quantity} units left'**
  String lowStockScreenQuantityUnitsLeft(Object quantity);

  /// No description provided for @lowStockScreenSKUSku.
  ///
  /// In en, this message translates to:
  /// **'SKU: {sku}'**
  String lowStockScreenSKUSku(Object sku);

  /// No description provided for @lowStockScreenThresholdValueUnits.
  ///
  /// In en, this message translates to:
  /// **'Threshold: {value} units'**
  String lowStockScreenThresholdValueUnits(Object value);

  /// No description provided for @myTicketsScreenCheckYourConnectionAndTry.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get myTicketsScreenCheckYourConnectionAndTry;

  /// No description provided for @myTicketsScreenReportsYouSendFromHelp.
  ///
  /// In en, this message translates to:
  /// **'Reports you send from Help & support are tracked here, with the status support has set on them.'**
  String get myTicketsScreenReportsYouSendFromHelp;

  /// No description provided for @myTicketsScreenSupportRepliedResolutionNotes.
  ///
  /// In en, this message translates to:
  /// **'Support replied: {resolutionNotes}'**
  String myTicketsScreenSupportRepliedResolutionNotes(Object resolutionNotes);

  /// No description provided for @notificationDetailScreenDeepLinkCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Deep link copied to clipboard'**
  String get notificationDetailScreenDeepLinkCopiedToClipboard;

  /// No description provided for @notificationDetailScreenOpenANotificationFromThe.
  ///
  /// In en, this message translates to:
  /// **'Open a notification from the Alerts tab to see its details.'**
  String get notificationDetailScreenOpenANotificationFromThe;

  /// No description provided for @notificationPreferencesScreenBannersAndSoundsAreControlled.
  ///
  /// In en, this message translates to:
  /// **'Banners and sounds are controlled by your phone'**
  String get notificationPreferencesScreenBannersAndSoundsAreControlled;

  /// No description provided for @notificationPreferencesScreenDeviceNotificationPermission.
  ///
  /// In en, this message translates to:
  /// **'Device notification permission'**
  String get notificationPreferencesScreenDeviceNotificationPermission;

  /// No description provided for @notificationPreferencesScreenInAppAlertsArePart.
  ///
  /// In en, this message translates to:
  /// **'In-app alerts are part of the app and are never switched off. The channels above only control how you are reached OUTSIDE the app.'**
  String get notificationPreferencesScreenInAppAlertsArePart;

  /// No description provided for @notificationPreferencesScreenSavedForYourAccountOn.
  ///
  /// In en, this message translates to:
  /// **'Saved for your account on this device'**
  String get notificationPreferencesScreenSavedForYourAccountOn;

  /// No description provided for @notificationPreferencesScreenTheAlertsTabAlwaysWorks.
  ///
  /// In en, this message translates to:
  /// **'The Alerts tab always works'**
  String get notificationPreferencesScreenTheAlertsTabAlwaysWorks;

  /// No description provided for @notificationSettingsScreenCouldNotOpenYourPhone.
  ///
  /// In en, this message translates to:
  /// **'Could not open your phone settings from here.'**
  String get notificationSettingsScreenCouldNotOpenYourPhone;

  /// No description provided for @notificationSettingsScreenIfDeviceNotificationsAreOff.
  ///
  /// In en, this message translates to:
  /// **'If device notifications are off, every alert still appears in the Alerts tab. The permission only decides whether your phone may also show banners and play sounds.'**
  String get notificationSettingsScreenIfDeviceNotificationsAreOff;

  /// No description provided for @notificationSettingsScreenInAppAlertsCannotBe.
  ///
  /// In en, this message translates to:
  /// **'In-app alerts cannot be switched off'**
  String get notificationSettingsScreenInAppAlertsCannotBe;

  /// No description provided for @notificationSettingsScreenInventoryOrdersOffersAndMore.
  ///
  /// In en, this message translates to:
  /// **'Inventory, orders, offers and more'**
  String get notificationSettingsScreenInventoryOrdersOffersAndMore;

  /// No description provided for @notificationSettingsScreenLowStockPOSSyncResults.
  ///
  /// In en, this message translates to:
  /// **'Low stock, POS sync results and account notices are part of the app so a shop is never silently out of date. The channels below decide whether you are ALSO reached outside the app.'**
  String get notificationSettingsScreenLowStockPOSSyncResults;

  /// No description provided for @notificationSettingsScreenNotificationsNeverBlockTheApp.
  ///
  /// In en, this message translates to:
  /// **'Notifications never block the app'**
  String get notificationSettingsScreenNotificationsNeverBlockTheApp;

  /// No description provided for @notificationSettingsScreenNotificationsOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Notifications on this device'**
  String get notificationSettingsScreenNotificationsOnThisDevice;

  /// No description provided for @notificationSettingsScreenWhatYouAreToldAbout.
  ///
  /// In en, this message translates to:
  /// **'What you are told about, and how'**
  String get notificationSettingsScreenWhatYouAreToldAbout;

  /// No description provided for @notificationSettingsScreenYourPhoneWillNotAsk.
  ///
  /// In en, this message translates to:
  /// **'Your phone will not ask again for this app. Turn banners on in Settings > Apps > Passly Business > Notifications.'**
  String get notificationSettingsScreenYourPhoneWillNotAsk;

  /// No description provided for @notificationsScreenCheckYourConnectionAndTry.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get notificationsScreenCheckYourConnectionAndTry;

  /// No description provided for @offerCreateSheetAppliesToLengthSelected.
  ///
  /// In en, this message translates to:
  /// **'Applies to ({length} selected)'**
  String offerCreateSheetAppliesToLengthSelected(Object length);

  /// No description provided for @offerCreateSheetDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount % *'**
  String get offerCreateSheetDiscount;

  /// No description provided for @offerCreateSheetDiscount2.
  ///
  /// In en, this message translates to:
  /// **'Discount ₹ *'**
  String get offerCreateSheetDiscount2;

  /// No description provided for @offerCreateSheetEGDiwali10Off.
  ///
  /// In en, this message translates to:
  /// **'e.g. Diwali 10% off'**
  String get offerCreateSheetEGDiwali10Off;

  /// No description provided for @offerCreateSheetEGValidOnIn.
  ///
  /// In en, this message translates to:
  /// **'e.g. Valid on in-store purchases only'**
  String get offerCreateSheetEGValidOnIn;

  /// No description provided for @offerCreateSheetEndDate.
  ///
  /// In en, this message translates to:
  /// **'End date *'**
  String get offerCreateSheetEndDate;

  /// No description provided for @offerCreateSheetFixedSalePriceCustomersPay.
  ///
  /// In en, this message translates to:
  /// **'Fixed sale price customers pay'**
  String get offerCreateSheetFixedSalePriceCustomersPay;

  /// No description provided for @offerCreateSheetKeptOffCustomerListingsUntil.
  ///
  /// In en, this message translates to:
  /// **'Kept off customer listings until you activate it'**
  String get offerCreateSheetKeptOffCustomerListingsUntil;

  /// No description provided for @offerCreateSheetNoProductsInInventoryYet.
  ///
  /// In en, this message translates to:
  /// **'No products in inventory yet — add products first.'**
  String get offerCreateSheetNoProductsInInventoryYet;

  /// No description provided for @offerCreateSheetOfferCreatedForLengthProduct.
  ///
  /// In en, this message translates to:
  /// **'Offer created for {length} product(s)'**
  String offerCreateSheetOfferCreatedForLengthProduct(Object length);

  /// No description provided for @offerCreateSheetOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Offer title *'**
  String get offerCreateSheetOfferTitle;

  /// No description provided for @offerCreateSheetOfferType.
  ///
  /// In en, this message translates to:
  /// **'Offer type *'**
  String get offerCreateSheetOfferType;

  /// No description provided for @offerCreateSheetPromotionalPrice.
  ///
  /// In en, this message translates to:
  /// **'Promotional price *'**
  String get offerCreateSheetPromotionalPrice;

  /// No description provided for @offerCreateSheetSelectAtLeastOneProduct.
  ///
  /// In en, this message translates to:
  /// **'Select at least one product for the offer'**
  String get offerCreateSheetSelectAtLeastOneProduct;

  /// No description provided for @offerCreateSheetStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start date *'**
  String get offerCreateSheetStartDate;

  /// No description provided for @offerCreateSheetTermsConditionsOptional.
  ///
  /// In en, this message translates to:
  /// **'Terms & conditions (optional)'**
  String get offerCreateSheetTermsConditionsOptional;

  /// No description provided for @offerCreateSheetValueQtyQuantity.
  ///
  /// In en, this message translates to:
  /// **'₹{value} · qty {quantity}'**
  String offerCreateSheetValueQtyQuantity(Object value, Object quantity);

  /// No description provided for @offerListScreensOfferTypeLabelDiscountLabelProductCountProductS.
  ///
  /// In en, this message translates to:
  /// **'{offerTypeLabel} · {discountLabel} · {productCount} product(s)'**
  String offerListScreensOfferTypeLabelDiscountLabelProductCountProductS(
    Object offerTypeLabel,
    Object discountLabel,
    Object productCount,
  );

  /// No description provided for @offersScreenCheckYourConnectionAndTry.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get offersScreenCheckYourConnectionAndTry;

  /// No description provided for @offersScreenChooseAShopToSee.
  ///
  /// In en, this message translates to:
  /// **'Choose a shop to see its offers.'**
  String get offersScreenChooseAShopToSee;

  /// No description provided for @operatingHoursScreenIgnoreTheWeeklyScheduleBelow.
  ///
  /// In en, this message translates to:
  /// **'Ignore the weekly schedule below entirely.'**
  String get operatingHoursScreenIgnoreTheWeeklyScheduleBelow;

  /// No description provided for @operatingHoursScreenOpen247.
  ///
  /// In en, this message translates to:
  /// **'Open 24×7'**
  String get operatingHoursScreenOpen247;

  /// No description provided for @operatingHoursScreenTheWholeWeekIsSaved.
  ///
  /// In en, this message translates to:
  /// **'The whole week is saved in one request. Holiday closures override these times.'**
  String get operatingHoursScreenTheWholeWeekIsSaved;

  /// No description provided for @operatingHoursScreenUpdateFailedPleaseRetry.
  ///
  /// In en, this message translates to:
  /// **'Update failed. Please retry.'**
  String get operatingHoursScreenUpdateFailedPleaseRetry;

  /// No description provided for @phoneOtpScreenPhoneSignInUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Phone sign-in unavailable'**
  String get phoneOtpScreenPhoneSignInUnavailable;

  /// No description provided for @phoneOtpScreenThisDeviceCannotReceiveAn.
  ///
  /// In en, this message translates to:
  /// **'This device cannot receive an SMS code. Use Google to sign in, or open the app on an Android or iOS phone.'**
  String get phoneOtpScreenThisDeviceCannotReceiveAn;

  /// No description provided for @posConnectionSetupScreenCheckTheAPIKeySecret.
  ///
  /// In en, this message translates to:
  /// **'Check the API key / secret above and try again — nothing was synced.'**
  String get posConnectionSetupScreenCheckTheAPIKeySecret;

  /// No description provided for @posConnectionSetupScreenCheckYourConnectionAndTry.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get posConnectionSetupScreenCheckYourConnectionAndTry;

  /// No description provided for @posConnectionSetupScreenLinkYourPOSToKeep.
  ///
  /// In en, this message translates to:
  /// **'Link your POS to keep products and stock in step automatically.'**
  String get posConnectionSetupScreenLinkYourPOSToKeep;

  /// No description provided for @posConnectionSetupScreenOnlyWhatYouTypeIs.
  ///
  /// In en, this message translates to:
  /// **'Only what you type is sent — a rotation never blanks an existing secret.'**
  String get posConnectionSetupScreenOnlyWhatYouTypeIs;

  /// No description provided for @posConnectionSetupScreenProviderNameIsValue.
  ///
  /// In en, this message translates to:
  /// **'{providerName} is {value}.'**
  String posConnectionSetupScreenProviderNameIsValue(
    Object providerName,
    Object value,
  );

  /// No description provided for @posConnectionSetupScreenThisConnectorSupportsFullSyncs.
  ///
  /// In en, this message translates to:
  /// **'This connector supports full syncs only.'**
  String get posConnectionSetupScreenThisConnectorSupportsFullSyncs;

  /// No description provided for @posConnectionSetupScreenThisShopAlreadyHasA.
  ///
  /// In en, this message translates to:
  /// **'This shop already has a connector ({value}). Update its credentials and reconnect — no duplicate is created.'**
  String posConnectionSetupScreenThisShopAlreadyHasA(Object value);

  /// No description provided for @posConnectionSetupScreenVendorCredentialsOptional.
  ///
  /// In en, this message translates to:
  /// **'Vendor credentials (optional)'**
  String get posConnectionSetupScreenVendorCredentialsOptional;

  /// No description provided for @posErrorScreenCheckTheConnectionAgain.
  ///
  /// In en, this message translates to:
  /// **'Check the connection again'**
  String get posErrorScreenCheckTheConnectionAgain;

  /// No description provided for @posErrorScreenLeaveThisScreenAndReturn.
  ///
  /// In en, this message translates to:
  /// **'Leave this screen and return to the POS hub.'**
  String get posErrorScreenLeaveThisScreenAndReturn;

  /// No description provided for @posErrorScreenReReadTheConnectorAnd.
  ///
  /// In en, this message translates to:
  /// **'Re-read the connector and its sync jobs from the server.'**
  String get posErrorScreenReReadTheConnectorAnd;

  /// No description provided for @posErrorScreenSeeWhetherAnEarlierJob.
  ///
  /// In en, this message translates to:
  /// **'See whether an earlier job succeeded and what failed.'**
  String get posErrorScreenSeeWhetherAnEarlierJob;

  /// No description provided for @posHubSheetsEveryTillScannerOrTablet.
  ///
  /// In en, this message translates to:
  /// **'Every till, scanner or tablet mapped to this connector.'**
  String get posHubSheetsEveryTillScannerOrTablet;

  /// No description provided for @posHubSheetsNoTerminalsMappedYetAdd.
  ///
  /// In en, this message translates to:
  /// **'No terminals mapped yet. Add the first one below.'**
  String get posHubSheetsNoTerminalsMappedYetAdd;

  /// No description provided for @posHubSheetsRecordsPerBatchOptional.
  ///
  /// In en, this message translates to:
  /// **'Records per batch (optional)'**
  String get posHubSheetsRecordsPerBatchOptional;

  /// No description provided for @posHubSheetsTerminalIdFromYourPOS.
  ///
  /// In en, this message translates to:
  /// **'Terminal id (from your POS vendor)'**
  String get posHubSheetsTerminalIdFromYourPOS;

  /// No description provided for @posHubSheetsTheTillIsUsuallyThe.
  ///
  /// In en, this message translates to:
  /// **'The till is usually the truth for stock levels; the platform keeps pricing, offers and MRP.'**
  String get posHubSheetsTheTillIsUsuallyThe;

  /// No description provided for @posHubSheetsWhenTheSameProductDisagrees.
  ///
  /// In en, this message translates to:
  /// **'When the same product disagrees'**
  String get posHubSheetsWhenTheSameProductDisagrees;

  /// No description provided for @posScreenCheckYourConnectionAndTry.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get posScreenCheckYourConnectionAndTry;

  /// No description provided for @posScreenChooseAShopToManage.
  ///
  /// In en, this message translates to:
  /// **'Choose a shop to manage its POS integration.'**
  String get posScreenChooseAShopToManage;

  /// No description provided for @posScreenConnectYourBillingCounter.
  ///
  /// In en, this message translates to:
  /// **'Connect your billing counter'**
  String get posScreenConnectYourBillingCounter;

  /// No description provided for @posScreenLinkYourPOSToKeep.
  ///
  /// In en, this message translates to:
  /// **'Link your POS to keep products and stock in step automatically.'**
  String get posScreenLinkYourPOSToKeep;

  /// No description provided for @posScreenNoSyncsYetTapSync.
  ///
  /// In en, this message translates to:
  /// **'No syncs yet.\nTap \"Sync now\" to pull your POS data.'**
  String get posScreenNoSyncsYetTapSync;

  /// No description provided for @posScreenPOSIntegrationIsNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'POS integration is not configured for your account.'**
  String get posScreenPOSIntegrationIsNotConfigured;

  /// No description provided for @posScreenPOSNotAvailableOnYour.
  ///
  /// In en, this message translates to:
  /// **'POS not available on your plan'**
  String get posScreenPOSNotAvailableOnYour;

  /// No description provided for @posScreenScheduledSyncsWillStopYou.
  ///
  /// In en, this message translates to:
  /// **'Scheduled syncs will stop. You can reconnect at any time.'**
  String get posScreenScheduledSyncsWillStopYou;

  /// No description provided for @posScreenUpgradeYourPlanToConnect.
  ///
  /// In en, this message translates to:
  /// **'Upgrade your plan to connect a point of sale. Your current plan does not include POS integrations.'**
  String get posScreenUpgradeYourPlanToConnect;

  /// No description provided for @posSharedCheckYourConnectionAndTry.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get posSharedCheckYourConnectionAndTry;

  /// No description provided for @posSyncHistoryScreenConnectAPOSAndRun.
  ///
  /// In en, this message translates to:
  /// **'Connect a POS and run a sync to build a history.'**
  String get posSyncHistoryScreenConnectAPOSAndRun;

  /// No description provided for @posSyncHistoryScreenNothingMatchesThisFilter.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches this filter'**
  String get posSyncHistoryScreenNothingMatchesThisFilter;

  /// No description provided for @posSyncHistoryScreenRunASyncAndEvery.
  ///
  /// In en, this message translates to:
  /// **'Run a sync and every job — queued, done or failed — shows up here.'**
  String get posSyncHistoryScreenRunASyncAndEvery;

  /// No description provided for @posSyncHistoryScreenSyncJobId.
  ///
  /// In en, this message translates to:
  /// **'Sync job #{id}'**
  String posSyncHistoryScreenSyncJobId(Object id);

  /// No description provided for @posSyncHistoryScreenTryAnotherStatusOrClear.
  ///
  /// In en, this message translates to:
  /// **'Try another status, or clear the filter.'**
  String get posSyncHistoryScreenTryAnotherStatusOrClear;

  /// No description provided for @posSyncHistoryScreenValueValue2Value3.
  ///
  /// In en, this message translates to:
  /// **'{value} · {value2}{value3}'**
  String posSyncHistoryScreenValueValue2Value3(
    Object value,
    Object value2,
    Object value3,
  );

  /// No description provided for @posSyncProgressScreenNothingIsCountedHereThe.
  ///
  /// In en, this message translates to:
  /// **'Nothing is counted here — the numbers below come from the POS connector.'**
  String get posSyncProgressScreenNothingIsCountedHereThe;

  /// No description provided for @posSyncProgressScreenStartingSync.
  ///
  /// In en, this message translates to:
  /// **'Starting sync…'**
  String get posSyncProgressScreenStartingSync;

  /// No description provided for @posSyncProgressScreenSyncingYourProducts.
  ///
  /// In en, this message translates to:
  /// **'Syncing your products…'**
  String get posSyncProgressScreenSyncingYourProducts;

  /// No description provided for @posSyncProgressScreenTheJobIsStillOn.
  ///
  /// In en, this message translates to:
  /// **'The job is still on the server — check the sync history before starting another one.'**
  String get posSyncProgressScreenTheJobIsStillOn;

  /// No description provided for @posSyncProgressScreenValue.
  ///
  /// In en, this message translates to:
  /// **'{value}'**
  String posSyncProgressScreenValue(Object value);

  /// No description provided for @posSyncResultScreenValue.
  ///
  /// In en, this message translates to:
  /// **'{value}'**
  String posSyncResultScreenValue(Object value);

  /// No description provided for @posSyncScreenConnectAPOSFirstThere.
  ///
  /// In en, this message translates to:
  /// **'Connect a POS first — there is nothing to sync from.'**
  String get posSyncScreenConnectAPOSFirstThere;

  /// No description provided for @posSyncScreenOnlyWhatChangedSinceThe.
  ///
  /// In en, this message translates to:
  /// **'Only what changed since the last sync — faster, but it can miss manual edits.'**
  String get posSyncScreenOnlyWhatChangedSinceThe;

  /// No description provided for @posSyncScreenReReadTheWholePOS.
  ///
  /// In en, this message translates to:
  /// **'Re-read the whole POS catalog and reconcile every product.'**
  String get posSyncScreenReReadTheWholePOS;

  /// No description provided for @priceHistoryScreenEveryPriceUpdateForThis.
  ///
  /// In en, this message translates to:
  /// **'Every price update for this product will be recorded here.'**
  String get priceHistoryScreenEveryPriceUpdateForThis;

  /// No description provided for @priceListScreenSearchNameBrandOrSKU.
  ///
  /// In en, this message translates to:
  /// **'Search name, brand or SKU'**
  String get priceListScreenSearchNameBrandOrSKU;

  /// No description provided for @pricingSharedAddProductsOrImportThem.
  ///
  /// In en, this message translates to:
  /// **'Add products or import them from Excel first.'**
  String get pricingSharedAddProductsOrImportThem;

  /// No description provided for @pricingSharedCurrentPriceValueValue2.
  ///
  /// In en, this message translates to:
  /// **'Current price ₹{value}{value2}'**
  String pricingSharedCurrentPriceValueValue2(Object value, Object value2);

  /// No description provided for @privacyScreenBusinessDataIsKeptWhile.
  ///
  /// In en, this message translates to:
  /// **'Business data is kept while your shop is active. When an account is closed, operational data is removed or anonymised except where a record must be kept for accounting or legal reasons.'**
  String get privacyScreenBusinessDataIsKeptWhile;

  /// No description provided for @privacyScreenDecideWhichAlertsYouReceive.
  ///
  /// In en, this message translates to:
  /// **'Decide which alerts you receive in Notification preferences, keep your catalogue accurate from the Products and Inventory screens, and contact support to correct your account details or ask for your data to be deleted.'**
  String get privacyScreenDecideWhichAlertsYouReceive;

  /// No description provided for @privacyScreenOnlyYourPublicBusinessInformation.
  ///
  /// In en, this message translates to:
  /// **'Only your public business information: shop name, category, address, hours, contact details and the products you publish. Stock quantities, costs, documents and your personal contact details stay private.'**
  String get privacyScreenOnlyYourPublicBusinessInformation;

  /// No description provided for @privacyScreenPaymentAndBillingProvidersWhen.
  ///
  /// In en, this message translates to:
  /// **'Payment and billing providers when you subscribe to a paid plan, providers you connect yourself (for example your POS vendor), and authorities when legally required. Nothing else is shared.'**
  String get privacyScreenPaymentAndBillingProvidersWhen;

  /// No description provided for @privacyScreenQuestionsAboutYourData.
  ///
  /// In en, this message translates to:
  /// **'Questions about your data?'**
  String get privacyScreenQuestionsAboutYourData;

  /// No description provided for @privacyScreenSessionsUseShortLivedAccess.
  ///
  /// In en, this message translates to:
  /// **'Sessions use short-lived access tokens that are revocable from the server, and tokens are stored in the device keychain or keystore. Logging out revokes the session and erases the stored tokens from this device.'**
  String get privacyScreenSessionsUseShortLivedAccess;

  /// No description provided for @privacyScreenToShowYourShopProducts.
  ///
  /// In en, this message translates to:
  /// **'To show your shop, products and prices to nearby customers, to sync your stock and prices, to send you operational alerts (low stock, POS sync results, verification), and to keep your account secure. Analytics are aggregated — we never sell your data.'**
  String get privacyScreenToShowYourShopProducts;

  /// No description provided for @privacyScreenWriteToEmailAndThe.
  ///
  /// In en, this message translates to:
  /// **'Write to {email} and the team will respond during {hours}.'**
  String privacyScreenWriteToEmailAndThe(Object email, Object hours);

  /// No description provided for @privacyScreenYourAccountIdentityNamePhone.
  ///
  /// In en, this message translates to:
  /// **'Your account identity (name, phone number and e-mail from your Google sign-in), your business details (shop name, category, address, operating hours and licence documents), your catalogue (products, stock levels and prices) and the notifications you receive. Shop location is captured only when you place or update your shop on the map.'**
  String get privacyScreenYourAccountIdentityNamePhone;

  /// No description provided for @privacyScreenYourDataInPasslyBusiness.
  ///
  /// In en, this message translates to:
  /// **'Your data in Passly Business'**
  String get privacyScreenYourDataInPasslyBusiness;

  /// No description provided for @productSheetsChooseHowYouWantTo.
  ///
  /// In en, this message translates to:
  /// **'Choose how you want to add products:'**
  String get productSheetsChooseHowYouWantTo;

  /// No description provided for @productSheetsEditName.
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String productSheetsEditName(Object name);

  /// No description provided for @productSheetsFullDetailsPriceStockBrand.
  ///
  /// In en, this message translates to:
  /// **'Full details: price, stock, brand, photo…'**
  String get productSheetsFullDetailsPriceStockBrand;

  /// No description provided for @productSheetsJPGPNGWebPUpTo.
  ///
  /// In en, this message translates to:
  /// **'JPG / PNG / WebP up to 5 MB, stored securely — the shop listing shows a link to it.'**
  String get productSheetsJPGPNGWebPUpTo;

  /// No description provided for @productSheetsMatchAgainstTheSharedCatalog.
  ///
  /// In en, this message translates to:
  /// **'Match against the shared catalog'**
  String get productSheetsMatchAgainstTheSharedCatalog;

  /// No description provided for @productSheetsProductName.
  ///
  /// In en, this message translates to:
  /// **'Product name *'**
  String get productSheetsProductName;

  /// No description provided for @productSheetsSellingPrice.
  ///
  /// In en, this message translates to:
  /// **'Selling price *'**
  String get productSheetsSellingPrice;

  /// No description provided for @productSheetsTypeOrPasteTheCode.
  ///
  /// In en, this message translates to:
  /// **'Type or paste the code on the pack'**
  String get productSheetsTypeOrPasteTheCode;

  /// No description provided for @productSheetsUnavailableProductsAreHiddenFrom.
  ///
  /// In en, this message translates to:
  /// **'Unavailable products are hidden from customers'**
  String get productSheetsUnavailableProductsAreHiddenFrom;

  /// No description provided for @productSheetsUnpublishedProductsStayAsDrafts.
  ///
  /// In en, this message translates to:
  /// **'Unpublished products stay as drafts'**
  String get productSheetsUnpublishedProductsStayAsDrafts;

  /// No description provided for @productSheetsUploadASpreadsheetOfProducts.
  ///
  /// In en, this message translates to:
  /// **'Upload a spreadsheet of products'**
  String get productSheetsUploadASpreadsheetOfProducts;

  /// No description provided for @productsScreenByUpdatedBy.
  ///
  /// In en, this message translates to:
  /// **'by {updatedBy}'**
  String productsScreenByUpdatedBy(Object updatedBy);

  /// No description provided for @productsScreenMatchedOfTotalProducts.
  ///
  /// In en, this message translates to:
  /// **'{matched} of {total} products'**
  String productsScreenMatchedOfTotalProducts(Object matched, Object total);

  /// No description provided for @productsScreenPleaseCheckYourConnectionAnd.
  ///
  /// In en, this message translates to:
  /// **'Please check your connection and retry.'**
  String get productsScreenPleaseCheckYourConnectionAnd;

  /// No description provided for @productsScreenRsValue.
  ///
  /// In en, this message translates to:
  /// **'Rs {value}'**
  String productsScreenRsValue(Object value);

  /// No description provided for @productsScreenSearchNameBrandOrSKU.
  ///
  /// In en, this message translates to:
  /// **'Search name, brand or SKU…'**
  String get productsScreenSearchNameBrandOrSKU;

  /// No description provided for @productsScreenUpdatedValue.
  ///
  /// In en, this message translates to:
  /// **'Updated {value}'**
  String productsScreenUpdatedValue(Object value);

  /// No description provided for @productsScreenYouDoNotHaveAccess.
  ///
  /// In en, this message translates to:
  /// **'You do not have access to this shop.'**
  String get productsScreenYouDoNotHaveAccess;

  /// No description provided for @registerScreenAlreadyHaveAnAccountSign.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get registerScreenAlreadyHaveAnAccountSign;

  /// No description provided for @registerScreenCompleteSignInInThe.
  ///
  /// In en, this message translates to:
  /// **'Complete sign-in in the opened Google window…'**
  String get registerScreenCompleteSignInInThe;

  /// No description provided for @registerScreenCreateYourAccountWithYour.
  ///
  /// In en, this message translates to:
  /// **'Create your account with your phone number and a password.'**
  String get registerScreenCreateYourAccountWithYour;

  /// No description provided for @registerScreenPhoneNumberAlreadyRegisteredPlease.
  ///
  /// In en, this message translates to:
  /// **'Phone number already registered. Please login instead.'**
  String get registerScreenPhoneNumberAlreadyRegisteredPlease;

  /// No description provided for @registerScreenTellUsAboutYourBusiness.
  ///
  /// In en, this message translates to:
  /// **'Tell us about your business'**
  String get registerScreenTellUsAboutYourBusiness;

  /// No description provided for @registrationWidgetsTakeAPhotoWithYour.
  ///
  /// In en, this message translates to:
  /// **'Take a photo with your camera'**
  String get registrationWidgetsTakeAPhotoWithYour;

  /// No description provided for @registrationWidgetsText.
  ///
  /// In en, this message translates to:
  /// **'*'**
  String get registrationWidgetsText;

  /// No description provided for @registrationWidgetsUploadingValue.
  ///
  /// In en, this message translates to:
  /// **'Uploading {value}…'**
  String registrationWidgetsUploadingValue(Object value);

  /// No description provided for @registrationWidgetsValue.
  ///
  /// In en, this message translates to:
  /// **'{value}'**
  String registrationWidgetsValue(Object value);

  /// No description provided for @registrationWidgetsValueReadyToUpload.
  ///
  /// In en, this message translates to:
  /// **'{value} · ready to upload'**
  String registrationWidgetsValueReadyToUpload(Object value);

  /// No description provided for @registrationWidgetsValueValue2.
  ///
  /// In en, this message translates to:
  /// **'{value} · {value2}'**
  String registrationWidgetsValueValue2(Object value, Object value2);

  /// No description provided for @reportIssueScreen1OpenProducts2Tap.
  ///
  /// In en, this message translates to:
  /// **'1. Open Products\n2. Tap a product'**
  String get reportIssueScreen1OpenProducts2Tap;

  /// No description provided for @reportIssueScreenAPictureOfTheScreen.
  ///
  /// In en, this message translates to:
  /// **'A picture of the screen helps support reproduce the problem. One image, compressed to WebP under 2 MB before it is sent.'**
  String get reportIssueScreenAPictureOfTheScreen;

  /// No description provided for @reportIssueScreenAPreciseReportIsUsually.
  ///
  /// In en, this message translates to:
  /// **'A precise report is usually fixed in one release'**
  String get reportIssueScreenAPreciseReportIsUsually;

  /// No description provided for @reportIssueScreenAPriceSavedAsThe.
  ///
  /// In en, this message translates to:
  /// **'A price saved as the old value after I tapped Save'**
  String get reportIssueScreenAPriceSavedAsThe;

  /// No description provided for @reportIssueScreenEveryReportBecomesATracked.
  ///
  /// In en, this message translates to:
  /// **'Every report becomes a tracked ticket'**
  String get reportIssueScreenEveryReportBecomesATracked;

  /// No description provided for @reportIssueScreenFilenameValue.
  ///
  /// In en, this message translates to:
  /// **'{filename} - {value}'**
  String reportIssueScreenFilenameValue(Object filename, Object value);

  /// No description provided for @reportIssueScreenHowMuchDoesItBlock.
  ///
  /// In en, this message translates to:
  /// **'How much does it block you?'**
  String get reportIssueScreenHowMuchDoesItBlock;

  /// No description provided for @reportIssueScreenReportCopiedPasteItInto.
  ///
  /// In en, this message translates to:
  /// **'Report copied - paste it into an e-mail to {email}'**
  String reportIssueScreenReportCopiedPasteItInto(Object email);

  /// No description provided for @reportIssueScreenSendingFilesASupportTicket.
  ///
  /// In en, this message translates to:
  /// **'Sending files a support ticket with the category, severity, your shop and the app version attached. Support works through the same queue, and the status stays visible under My support tickets.'**
  String get reportIssueScreenSendingFilesASupportTicket;

  /// No description provided for @reportIssueScreenStepsToReproduceOptional.
  ///
  /// In en, this message translates to:
  /// **'Steps to reproduce (optional)'**
  String get reportIssueScreenStepsToReproduceOptional;

  /// No description provided for @reportIssueScreenSupportHasItInThe.
  ///
  /// In en, this message translates to:
  /// **'Support has it in the queue. Quote the ticket number below if you contact us about it.'**
  String get reportIssueScreenSupportHasItInThe;

  /// No description provided for @resetPasswordScreenPasswordResetSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Password reset successfully!'**
  String get resetPasswordScreenPasswordResetSuccessfully;

  /// No description provided for @resetPasswordScreenYourNewPasswordMustBe.
  ///
  /// In en, this message translates to:
  /// **'Your new password must be at least 8 characters and include letters and numbers.'**
  String get resetPasswordScreenYourNewPasswordMustBe;

  /// No description provided for @securityScreenEndsTheSessionAndErases.
  ///
  /// In en, this message translates to:
  /// **'Ends the session and erases the saved tokens'**
  String get securityScreenEndsTheSessionAndErases;

  /// No description provided for @securityScreenGoogleAccountVerifiedByFirebase.
  ///
  /// In en, this message translates to:
  /// **'Google account, verified by Firebase'**
  String get securityScreenGoogleAccountVerifiedByFirebase;

  /// No description provided for @securityScreenHowYouSignInAnd.
  ///
  /// In en, this message translates to:
  /// **'How you sign in and where you are signed in'**
  String get securityScreenHowYouSignInAnd;

  /// No description provided for @securityScreenPasswordSignInIsNot.
  ///
  /// In en, this message translates to:
  /// **'Password sign-in is not enabled'**
  String get securityScreenPasswordSignInIsNot;

  /// No description provided for @securityScreenReportSuspiciousActivity.
  ///
  /// In en, this message translates to:
  /// **'Report suspicious activity'**
  String get securityScreenReportSuspiciousActivity;

  /// No description provided for @securityScreenSignInAndAccountNotices.
  ///
  /// In en, this message translates to:
  /// **'Sign-in and account notices'**
  String get securityScreenSignInAndAccountNotices;

  /// No description provided for @securityScreenYourIdentityIsVerifiedBy.
  ///
  /// In en, this message translates to:
  /// **'Your identity is verified by Google every time you sign in, so there is no Passly password to change or reset. To move your account to a different Google address, contact support.'**
  String get securityScreenYourIdentityIsVerifiedBy;

  /// No description provided for @sessionsScreenCheckYourConnectionAndTry.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get sessionsScreenCheckYourConnectionAndTry;

  /// No description provided for @sessionsScreenDevicesWithAnActivePassly.
  ///
  /// In en, this message translates to:
  /// **'Devices with an active Passly Business session'**
  String get sessionsScreenDevicesWithAnActivePassly;

  /// No description provided for @sessionsScreenIPIp.
  ///
  /// In en, this message translates to:
  /// **'IP {ip}'**
  String sessionsScreenIPIp(Object ip);

  /// No description provided for @sessionsScreenLabelWillNeedToSign.
  ///
  /// In en, this message translates to:
  /// **'{label} will need to sign in again. This device stays signed in.'**
  String sessionsScreenLabelWillNeedToSign(Object label);

  /// No description provided for @sessionsScreenNoDeviceSessionsRecorded.
  ///
  /// In en, this message translates to:
  /// **'No device sessions recorded'**
  String get sessionsScreenNoDeviceSessionsRecorded;

  /// No description provided for @sessionsScreenOnlyThisDeviceIsSigned.
  ///
  /// In en, this message translates to:
  /// **'Only this device is signed in right now.'**
  String get sessionsScreenOnlyThisDeviceIsSigned;

  /// No description provided for @sessionsScreenSigningADeviceOutTakes.
  ///
  /// In en, this message translates to:
  /// **'Signing a device out takes effect immediately'**
  String get sessionsScreenSigningADeviceOutTakes;

  /// No description provided for @sessionsScreenTheDeviceIsReturnedTo.
  ///
  /// In en, this message translates to:
  /// **'The device is returned to the sign-in screen the next time it reaches Passly. To end THIS session, use Log out in Settings — that also erases the saved tokens on this phone.'**
  String get sessionsScreenTheDeviceIsReturnedTo;

  /// No description provided for @sessionsScreenThisAccountSignsInWith.
  ///
  /// In en, this message translates to:
  /// **'This account signs in with Google, so the session is managed by Google rather than stored as a Passly device session. Logging out from Settings still ends it on this device.'**
  String get sessionsScreenThisAccountSignsInWith;

  /// No description provided for @shopLocationDetailsGPSAccuracyIsAnEstimate.
  ///
  /// In en, this message translates to:
  /// **'GPS accuracy is an estimate, not a guarantee. Tap the map, drag the pin, or correct coordinates below. Check your shop entrance and address before confirming.'**
  String get shopLocationDetailsGPSAccuracyIsAnEstimate;

  /// No description provided for @shopLocationDetailsOriginalGPSEstimateValue.
  ///
  /// In en, this message translates to:
  /// **'Original GPS estimate — {value}'**
  String shopLocationDetailsOriginalGPSEstimateValue(Object value);

  /// No description provided for @shopLocationDetailsThisPinIsAboutValue.
  ///
  /// In en, this message translates to:
  /// **'This pin is about {value} m away from your GPS location. Are you sure this is your shop entrance?'**
  String shopLocationDetailsThisPinIsAboutValue(Object value);

  /// No description provided for @shopLocationDetailsYesThisIsMyShop.
  ///
  /// In en, this message translates to:
  /// **'Yes, this is my shop entrance'**
  String get shopLocationDetailsYesThisIsMyShop;

  /// No description provided for @shopLocationScreenCouldNotOpenYourPhone.
  ///
  /// In en, this message translates to:
  /// **'Could not open your phone settings from here.'**
  String get shopLocationScreenCouldNotOpenYourPhone;

  /// No description provided for @shopLocationScreenCustomersSeeYourShopOn.
  ///
  /// In en, this message translates to:
  /// **'Customers see your shop on the map at this pin. Keep it on your shop entrance, not the street corner.'**
  String get shopLocationScreenCustomersSeeYourShopOn;

  /// No description provided for @shopLocationScreenTheAppReadsYourDevice.
  ///
  /// In en, this message translates to:
  /// **'The app reads your device GPS a few times, keeps the most accurate fix and asks the server to replace the stored pin. Every change is audited.'**
  String get shopLocationScreenTheAppReadsYourDevice;

  /// No description provided for @shopLocationScreenWithoutAPinCustomersCannot.
  ///
  /// In en, this message translates to:
  /// **'Without a pin customers cannot find your shop on the map. Stand at or near the shop and save your current location.'**
  String get shopLocationScreenWithoutAPinCustomersCannot;

  /// No description provided for @shopProfileScreenValueValue2CategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'{value} · {value2} · {categoryLabel}'**
  String shopProfileScreenValueValue2CategoryLabel(
    Object value,
    Object value2,
    Object categoryLabel,
  );

  /// No description provided for @shopProfileSharedManagersHaveReadOnlyAccess.
  ///
  /// In en, this message translates to:
  /// **'Managers have read-only access here. Ask the shop owner for changes.'**
  String get shopProfileSharedManagersHaveReadOnlyAccess;

  /// No description provided for @shopRegistrationWizardAddYourShopLocationFor.
  ///
  /// In en, this message translates to:
  /// **'Add your shop location for better visibility and verification.'**
  String get shopRegistrationWizardAddYourShopLocationFor;

  /// No description provided for @shopRegistrationWizardAlreadyHaveAnAccountLogin.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Login'**
  String get shopRegistrationWizardAlreadyHaveAnAccountLogin;

  /// No description provided for @shopRegistrationWizardDiscoverabilityByNearbyCustomers.
  ///
  /// In en, this message translates to:
  /// **'Discoverability by nearby customers'**
  String get shopRegistrationWizardDiscoverabilityByNearbyCustomers;

  /// No description provided for @shopRegistrationWizardDocumentsAndAdditionalInfo.
  ///
  /// In en, this message translates to:
  /// **'Documents and Additional Info'**
  String get shopRegistrationWizardDocumentsAndAdditionalInfo;

  /// No description provided for @shopRegistrationWizardEGSharmaMedicalStore.
  ///
  /// In en, this message translates to:
  /// **'e.g. Sharma Medical Store'**
  String get shopRegistrationWizardEGSharmaMedicalStore;

  /// No description provided for @shopRegistrationWizardGettingLocation.
  ///
  /// In en, this message translates to:
  /// **'Getting location…'**
  String get shopRegistrationWizardGettingLocation;

  /// No description provided for @shopRegistrationWizardHandleProductsOrdersInventoryAnd.
  ///
  /// In en, this message translates to:
  /// **'Handle products, orders/inventory and business information'**
  String get shopRegistrationWizardHandleProductsOrdersInventoryAnd;

  /// No description provided for @shopRegistrationWizardHttps.
  ///
  /// In en, this message translates to:
  /// **'https://'**
  String get shopRegistrationWizardHttps;

  /// No description provided for @shopRegistrationWizardInstagramFacebookLink.
  ///
  /// In en, this message translates to:
  /// **'Instagram / Facebook link'**
  String get shopRegistrationWizardInstagramFacebookLink;

  /// No description provided for @shopRegistrationWizardJoinOurPlatformAndBring.
  ///
  /// In en, this message translates to:
  /// **'Join our platform and bring your business closer to local customers.'**
  String get shopRegistrationWizardJoinOurPlatformAndBring;

  /// No description provided for @shopRegistrationWizardNear.
  ///
  /// In en, this message translates to:
  /// **'Near…'**
  String get shopRegistrationWizardNear;

  /// No description provided for @shopRegistrationWizardNoGPSFixTapThe.
  ///
  /// In en, this message translates to:
  /// **'No GPS fix — tap the map above to place your shop entrance pin, or type the coordinates below.'**
  String get shopRegistrationWizardNoGPSFixTapThe;

  /// No description provided for @shopRegistrationWizardTapTheMapToPlace.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to place your shop pin.'**
  String get shopRegistrationWizardTapTheMapToPlace;

  /// No description provided for @shopRegistrationWizardTellCustomersAboutYourShop.
  ///
  /// In en, this message translates to:
  /// **'Tell customers about your shop …'**
  String get shopRegistrationWizardTellCustomersAboutYourShop;

  /// No description provided for @shopRegistrationWizardTellUsAboutYourShop.
  ///
  /// In en, this message translates to:
  /// **'Tell us about your shop or business.'**
  String get shopRegistrationWizardTellUsAboutYourShop;

  /// No description provided for @shopRegistrationWizardTypeYourAddressBelowThen.
  ///
  /// In en, this message translates to:
  /// **'Type your address below, then tap the map to place your shop pin.'**
  String get shopRegistrationWizardTypeYourAddressBelowThen;

  /// No description provided for @shopRegistrationWizardUdyamMSMENumberOptional.
  ///
  /// In en, this message translates to:
  /// **'Udyam / MSME Number (optional)'**
  String get shopRegistrationWizardUdyamMSMENumberOptional;

  /// No description provided for @shopRegistrationWizardUploadRequiredDocumentsForVerification.
  ///
  /// In en, this message translates to:
  /// **'Upload required documents for verification.'**
  String get shopRegistrationWizardUploadRequiredDocumentsForVerification;

  /// No description provided for @shopRegistrationWizardVerifiedBusinessesCreateASafer.
  ///
  /// In en, this message translates to:
  /// **'Verified businesses create a safer marketplace'**
  String get shopRegistrationWizardVerifiedBusinessesCreateASafer;

  /// No description provided for @shopRegistrationWizardYouWillGetANotification.
  ///
  /// In en, this message translates to:
  /// **'You will get a notification once your shop is verified.'**
  String get shopRegistrationWizardYouWillGetANotification;

  /// No description provided for @shopRegistrationWizardYourShopRegistrationHasBeen.
  ///
  /// In en, this message translates to:
  /// **'Your shop registration has been successfully submitted. Our team will review the details and verify your documents.'**
  String get shopRegistrationWizardYourShopRegistrationHasBeen;

  /// No description provided for @shopSettingsScreenCouldNotSavePleaseRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not save. Please retry.'**
  String get shopSettingsScreenCouldNotSavePleaseRetry;

  /// No description provided for @shopSettingsScreenCustomersCanPlaceNewOrders.
  ///
  /// In en, this message translates to:
  /// **'Customers can place new orders while on'**
  String get shopSettingsScreenCustomersCanPlaceNewOrders;

  /// No description provided for @shopSettingsScreenManagersCannotChangeShopSettings.
  ///
  /// In en, this message translates to:
  /// **'Managers cannot change shop settings.'**
  String get shopSettingsScreenManagersCannotChangeShopSettings;

  /// No description provided for @shopSettingsScreenOpen247.
  ///
  /// In en, this message translates to:
  /// **'Open 24×7'**
  String get shopSettingsScreenOpen247;

  /// No description provided for @shopsScreenNoShopsYetRegisterYour.
  ///
  /// In en, this message translates to:
  /// **'No shops yet.\nRegister your first business to get started.'**
  String get shopsScreenNoShopsYetRegisterYour;

  /// No description provided for @splashScreenCouldNotCompleteStartup.
  ///
  /// In en, this message translates to:
  /// **'Could not complete startup'**
  String get splashScreenCouldNotCompleteStartup;

  /// No description provided for @splashScreenCouldNotCompleteStartupCheck.
  ///
  /// In en, this message translates to:
  /// **'Could not complete startup. Check your connection and retry.'**
  String get splashScreenCouldNotCompleteStartupCheck;

  /// No description provided for @stockHistoryScreenStockMovementsAdjustmentsAndPrice.
  ///
  /// In en, this message translates to:
  /// **'Stock movements, adjustments and price changes will appear here.'**
  String get stockHistoryScreenStockMovementsAdjustmentsAndPrice;

  /// No description provided for @stockSheetsCurrentStockCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current stock: {_current}'**
  String stockSheetsCurrentStockCurrent(Object _current);

  /// No description provided for @stockSheetsHistoryName.
  ///
  /// In en, this message translates to:
  /// **'History — {name}'**
  String stockSheetsHistoryName(Object name);

  /// No description provided for @stockSheetsLastUpdatedValueValue2Value3.
  ///
  /// In en, this message translates to:
  /// **'Last updated {value}{value2} · {value3}'**
  String stockSheetsLastUpdatedValueValue2Value3(
    Object value,
    Object value2,
    Object value3,
  );

  /// No description provided for @stockSheetsStockMovementsAdjustmentsAndPrice.
  ///
  /// In en, this message translates to:
  /// **'Stock movements, adjustments and price changes (newest first)'**
  String get stockSheetsStockMovementsAdjustmentsAndPrice;

  /// No description provided for @stockSheetsValueStockDelta.
  ///
  /// In en, this message translates to:
  /// **'{value}{stockDelta}'**
  String stockSheetsValueStockDelta(Object value, Object stockDelta);

  /// No description provided for @stockSheetsValueValue2ActorLabel.
  ///
  /// In en, this message translates to:
  /// **'{value}{value2} · {actorLabel}'**
  String stockSheetsValueValue2ActorLabel(
    Object value,
    Object value2,
    Object actorLabel,
  );

  /// No description provided for @supportFaqScreenLengthOfLength2Articles.
  ///
  /// In en, this message translates to:
  /// **'{length} of {length2} articles'**
  String supportFaqScreenLengthOfLength2Articles(Object length, Object length2);

  /// No description provided for @supportFaqScreenStillNeedHelpContactSupport.
  ///
  /// In en, this message translates to:
  /// **'Still need help? Contact support'**
  String get supportFaqScreenStillNeedHelpContactSupport;

  /// No description provided for @supportFaqScreenTryAnotherWordOrSend.
  ///
  /// In en, this message translates to:
  /// **'Try another word, or send your question to support.'**
  String get supportFaqScreenTryAnotherWordOrSend;

  /// No description provided for @supportScreenFrequentlyAskedQuestions.
  ///
  /// In en, this message translates to:
  /// **'Frequently asked questions'**
  String get supportScreenFrequentlyAskedQuestions;

  /// No description provided for @supportScreenWriteToEmailOrCall.
  ///
  /// In en, this message translates to:
  /// **'Write to {email} or call {phone}. Support hours: {hours}.'**
  String supportScreenWriteToEmailOrCall(
    Object email,
    Object phone,
    Object hours,
  );

  /// No description provided for @termsScreenAnAccountThatBreaksThese.
  ///
  /// In en, this message translates to:
  /// **'An account that breaks these terms, or that is involved in fraud, can be suspended or closed. If that happens you will see the reason the next time you open the app.'**
  String get termsScreenAnAccountThatBreaksThese;

  /// No description provided for @termsScreenContactEmailForAnyQuestion.
  ///
  /// In en, this message translates to:
  /// **'Contact {email} for any question about these terms.'**
  String termsScreenContactEmailForAnyQuestion(Object email);

  /// No description provided for @termsScreenDoNotUploadUnlawfulProducts.
  ///
  /// In en, this message translates to:
  /// **'Do not upload unlawful products, attempt to access another shop\'s data, scrape the platform, or use the app to send spam. Barcode, import and POS tools are provided so you can manage your own catalogue.'**
  String get termsScreenDoNotUploadUnlawfulProducts;

  /// No description provided for @termsScreenPaidPlansAreBilledThrough.
  ///
  /// In en, this message translates to:
  /// **'Paid plans are billed through the provider shown at checkout, renew until cancelled, and are refundable only where the law or the plan terms allow. Cancelling stops future renewals.'**
  String get termsScreenPaidPlansAreBilledThrough;

  /// No description provided for @termsScreenShopNameAddressCategoryHours.
  ///
  /// In en, this message translates to:
  /// **'Shop name, address, category, hours and verification documents must be truthful. Shops with misleading details, or documents that do not belong to the business, can be suspended.'**
  String get termsScreenShopNameAddressCategoryHours;

  /// No description provided for @termsScreenTheAppIsForOwners.
  ///
  /// In en, this message translates to:
  /// **'The app is for owners and managers of registered shops. You may use it only for the shop you are authorised to manage, and you are responsible for keeping your sign-in device secure.'**
  String get termsScreenTheAppIsForOwners;

  /// No description provided for @termsScreenTheseTermsMayBeUpdated.
  ///
  /// In en, this message translates to:
  /// **'These terms may be updated as the app gains features. Continuing to use the app after an update means you accept the current version.'**
  String get termsScreenTheseTermsMayBeUpdated;

  /// No description provided for @termsScreenWeWorkToKeepThe.
  ///
  /// In en, this message translates to:
  /// **'We work to keep the app and the sync services available, but there will be maintenance windows and outages. Offline work is not lost — changes are sent when the connection returns.'**
  String get termsScreenWeWorkToKeepThe;

  /// No description provided for @termsScreenYouOwnTheProductsPrices.
  ///
  /// In en, this message translates to:
  /// **'You own the products, prices, stock figures and images you publish. Customers rely on them, so keep them accurate and up to date, and make sure you have the right to sell the products you list.'**
  String get termsScreenYouOwnTheProductsPrices;

  /// No description provided for @ticketDetailScreenReferenceCopied.
  ///
  /// In en, this message translates to:
  /// **'{reference} copied'**
  String ticketDetailScreenReferenceCopied(Object reference);

  /// No description provided for @ticketDetailScreenShopShopName.
  ///
  /// In en, this message translates to:
  /// **'Shop: {shopName}'**
  String ticketDetailScreenShopShopName(Object shopName);

  /// No description provided for @ticketDetailScreenSomethingElseContactSupport.
  ///
  /// In en, this message translates to:
  /// **'Something else? Contact support'**
  String get ticketDetailScreenSomethingElseContactSupport;

  /// No description provided for @ticketDetailScreenTicketsArePrivateToThe.
  ///
  /// In en, this message translates to:
  /// **'Tickets are private to the account that filed them.'**
  String get ticketDetailScreenTicketsArePrivateToThe;

  /// No description provided for @updatePriceScreenCurrentValueValue2.
  ///
  /// In en, this message translates to:
  /// **'Current: {value}{value2}'**
  String updatePriceScreenCurrentValueValue2(Object value, Object value2);

  /// No description provided for @updatePriceScreenMRPOptional.
  ///
  /// In en, this message translates to:
  /// **'MRP (₹, optional)'**
  String get updatePriceScreenMRPOptional;

  /// No description provided for @updatePriceScreenPriceUpdatedNowValueValue2.
  ///
  /// In en, this message translates to:
  /// **'Price updated — now ₹{value}{value2}'**
  String updatePriceScreenPriceUpdatedNowValueValue2(
    Object value,
    Object value2,
  );

  /// No description provided for @updatePriceScreenSellingPrice.
  ///
  /// In en, this message translates to:
  /// **'Selling price (₹)'**
  String get updatePriceScreenSellingPrice;

  /// No description provided for @updateStockScreenCurrentQuantityUnits.
  ///
  /// In en, this message translates to:
  /// **'Current: {quantity} units'**
  String updateStockScreenCurrentQuantityUnits(Object quantity);

  /// No description provided for @updateStockScreenEG24ToAdd.
  ///
  /// In en, this message translates to:
  /// **'e.g. 24 to add stock, -3 to remove'**
  String get updateStockScreenEG24ToAdd;

  /// No description provided for @updateStockScreenEGSupplierDelivery123.
  ///
  /// In en, this message translates to:
  /// **'e.g. supplier delivery #123'**
  String get updateStockScreenEGSupplierDelivery123;

  /// No description provided for @updateStockScreenStockUpdatedPreviousQuantityNewQuantityUnits.
  ///
  /// In en, this message translates to:
  /// **'Stock updated: {previousQuantity} → {newQuantity} units ({label})'**
  String updateStockScreenStockUpdatedPreviousQuantityNewQuantityUnits(
    Object previousQuantity,
    Object newQuantity,
    Object label,
  );

  /// No description provided for @welcomeScreenByContinuingYouAgreeTo.
  ///
  /// In en, this message translates to:
  /// **'By continuing, you agree to our Terms & Privacy Policy.'**
  String get welcomeScreenByContinuingYouAgreeTo;

  /// No description provided for @welcomeScreenLoginFailedPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Login failed. Please try again.'**
  String get welcomeScreenLoginFailedPleaseTryAgain;

  /// No description provided for @welcomeScreenManageYourShopProductsAnd.
  ///
  /// In en, this message translates to:
  /// **'Manage your shop, products and inventory.'**
  String get welcomeScreenManageYourShopProductsAnd;

  /// No description provided for @commonCheckTheDetails.
  ///
  /// In en, this message translates to:
  /// **'Check the details'**
  String get commonCheckTheDetails;

  /// No description provided for @commonNetworkProblem.
  ///
  /// In en, this message translates to:
  /// **'Network problem'**
  String get commonNetworkProblem;

  /// No description provided for @commonNoInternetConnection.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get commonNoInternetConnection;

  /// No description provided for @commonNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get commonNotFound;

  /// No description provided for @commonNothingHereYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get commonNothingHereYet;

  /// No description provided for @commonServerError.
  ///
  /// In en, this message translates to:
  /// **'Server error'**
  String get commonServerError;

  /// No description provided for @commonSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired'**
  String get commonSessionExpired;

  /// No description provided for @commonSignInRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign-in required'**
  String get commonSignInRequired;

  /// No description provided for @commonSomethingWentWrong3.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonSomethingWentWrong3;

  /// No description provided for @commonThatChangeConflicts.
  ///
  /// In en, this message translates to:
  /// **'That change conflicts'**
  String get commonThatChangeConflicts;

  /// No description provided for @commonTheServerTookTooLong.
  ///
  /// In en, this message translates to:
  /// **'The server took too long'**
  String get commonTheServerTookTooLong;

  /// No description provided for @commonUnderMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Under maintenance'**
  String get commonUnderMaintenance;

  /// No description provided for @systemStateCheckYourMobileDataOr.
  ///
  /// In en, this message translates to:
  /// **'Check your mobile data or Wi-Fi, then try again. Nothing you did was lost.'**
  String get systemStateCheckYourMobileDataOr;

  /// No description provided for @systemStateForYourSecurityYouWere.
  ///
  /// In en, this message translates to:
  /// **'For your security you were signed out. Please sign in again to continue where you left off.'**
  String get systemStateForYourSecurityYouWere;

  /// No description provided for @systemStateSomeOfTheInformationIs.
  ///
  /// In en, this message translates to:
  /// **'Some of the information is not valid. Please review it and try again.'**
  String get systemStateSomeOfTheInformationIs;

  /// No description provided for @systemStateSomethingWasAlreadyUpdatedRefresh.
  ///
  /// In en, this message translates to:
  /// **'Something was already updated. Refresh the list and try again.'**
  String get systemStateSomethingWasAlreadyUpdatedRefresh;

  /// No description provided for @systemStateSomethingWentWrongOnOur.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong on our side. Please try again shortly.'**
  String get systemStateSomethingWentWrongOnOur;

  /// No description provided for @systemStateTheActionCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The action could not be completed. Please try again.'**
  String get systemStateTheActionCouldNotBe;

  /// No description provided for @systemStateTheRequestTimedOutBefore.
  ///
  /// In en, this message translates to:
  /// **'The request timed out before the server answered. Please try again.'**
  String get systemStateTheRequestTimedOutBefore;

  /// No description provided for @systemStateThereIsNothingToShow.
  ///
  /// In en, this message translates to:
  /// **'There is nothing to show right now.'**
  String get systemStateThereIsNothingToShow;

  /// No description provided for @systemStateWeAreDoingAShort.
  ///
  /// In en, this message translates to:
  /// **'We are doing a short maintenance. Your data is safe — please try again in a few minutes.'**
  String get systemStateWeAreDoingAShort;

  /// No description provided for @systemStateWeCouldNotFindThat.
  ///
  /// In en, this message translates to:
  /// **'We could not find that. It may have been removed.'**
  String get systemStateWeCouldNotFindThat;

  /// No description provided for @systemStateWeCouldNotReachThe.
  ///
  /// In en, this message translates to:
  /// **'We could not reach the server. Check your connection and try again.'**
  String get systemStateWeCouldNotReachThe;

  /// No description provided for @systemStateYouAreNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'You are not signed in for this action. Please sign in again.'**
  String get systemStateYouAreNotSignedIn;

  /// No description provided for @systemStateYourAccountIsNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Your account is not allowed to do this here. Ask the shop owner, or switch to a shop you manage.'**
  String get systemStateYourAccountIsNotAllowed;
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
