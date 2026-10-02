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

  @override
  String get msgNotSignedIn => 'Not signed in';

  @override
  String get msgNoShopSelected => 'No shop selected';

  @override
  String get msgSessionExpired =>
      'Your session has expired. Please sign in again.';

  @override
  String get msgNoInternet =>
      'No internet connection. Check your network and retry.';

  @override
  String get formProductNameRequired => 'Product name is required';

  @override
  String get formSellingPriceRequired => 'Selling price is required';

  @override
  String get formEnterValidAmount => 'Enter a valid amount';

  @override
  String get formPriceCannotBeNegative => 'Price cannot be negative';

  @override
  String get formMrpCannotBeNegative => 'MRP cannot be negative';

  @override
  String get formMrpBelowPrice => 'MRP cannot be lower than the selling price';

  @override
  String get formWholeNumberRequired => 'Enter a whole number';

  @override
  String get formQuantityCannotBeNegative => 'Quantity cannot be negative';

  @override
  String formBarcodeTooShort(int count) {
    return 'Barcode must be at least $count characters';
  }

  @override
  String formTooManyCharacters(int count) {
    return 'Use at most $count characters';
  }

  @override
  String get dashLabel => '—';

  @override
  String get notUpdatedYet => 'Not updated yet';

  @override
  String get timeJustNow => 'just now';

  @override
  String timeMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String timeHoursAgo(int count) {
    return '$count h ago';
  }

  @override
  String timeYesterdayAt(String time) {
    return 'Yesterday $time';
  }

  @override
  String get patternTime => 'HH:mm';

  @override
  String get patternDateShort => 'd MMM yyyy';

  @override
  String get patternDateTimeThisYear => 'd MMM, HH:mm';

  @override
  String get patternDateTimeFull => 'd MMM yyyy, HH:mm';

  @override
  String get freshnessPrefixInventory => 'Inventory updated';

  @override
  String get freshnessPrefixPrice => 'Price updated';

  @override
  String get freshnessPrefixPosSync => 'Last POS sync';

  @override
  String freshnessJustNow(String prefix) {
    return '$prefix just now';
  }

  @override
  String freshnessMinutesAgo(String prefix, int count) {
    return '$prefix $count min ago';
  }

  @override
  String freshnessToday(String prefix) {
    return '$prefix today';
  }

  @override
  String freshnessYesterday(String prefix) {
    return '$prefix yesterday';
  }

  @override
  String freshnessOnDate(String prefix, String date) {
    return '$prefix $date';
  }

  @override
  String get inventoryNotUpdatedYet => 'Inventory not updated yet';

  @override
  String get priceNotUpdatedYet => 'Price not updated yet';

  @override
  String get noPosSyncYet => 'No POS sync yet';

  @override
  String get connectivityBannerReconnecting => 'Reconnecting…';

  @override
  String get connectivityBannerRetry => 'Retry';

  @override
  String get aboutScreenConnectYourBillingSoftwareAnd =>
      'Connect your billing software and pull bill items';

  @override
  String get aboutScreenImportAWholeCatalogueWith =>
      'Import a whole catalogue with a preview first';

  @override
  String get aboutScreenPasslyBusinessForShopkeepers =>
      'Passly Business, for shopkeepers';

  @override
  String get aboutScreenPriceListsDiscountsAndPrice =>
      'Price lists, discounts and price history';

  @override
  String get aboutScreenProductsBarcodeScanningStockAnd =>
      'Products, barcode scanning, stock and freshness';

  @override
  String aboutScreenVersionLabelPassly(Object versionLabel) {
    return '$versionLabel - Passly';
  }

  @override
  String get aboutScreenViewsClicksAndWhatCustomers =>
      'Views, clicks and what customers searched for';

  @override
  String get accountScreenAccountSecurityAppLegalAnd =>
      'Account, security, app, legal and support';

  @override
  String get accountScreenHyperlocalShopkeeperV100 =>
      'Hyperlocal Shopkeeper v1.0.0';

  @override
  String accountScreenValueStatusValue2(
    Object value,
    Object status,
    Object value2,
  ) {
    return '$value · $status$value2';
  }

  @override
  String get accountSettingsScreenAnswersToTheMostCommon =>
      'Answers to the most common questions';

  @override
  String get accountSettingsScreenAppLanguageForThisDevice =>
      'App language for this device';

  @override
  String get accountSettingsScreenDeliveryCategoriesAndPermissions =>
      'Delivery, categories and permissions';

  @override
  String get accountSettingsScreenEveryDeviceSignedInTo =>
      'Every device signed in to this account';

  @override
  String get accountSettingsScreenGuidesAndWaysToReach =>
      'Guides and ways to reach the team';

  @override
  String get accountSettingsScreenLightDarkOrFollowThis =>
      'Light, dark or follow this device';

  @override
  String get accountSettingsScreenLookingForYourBusinesses =>
      'Looking for your businesses?';

  @override
  String get accountSettingsScreenShopSettingsHolidaysAndSwitching =>
      'Shop settings, holidays and switching between shops belong to the Account tab — they change shop data, not your account or this app.';

  @override
  String get accountSettingsScreenSignInMethodAccountStatus =>
      'Sign-in method, account status and safety';

  @override
  String get accountSettingsScreenStatusOfTheReportsYou =>
      'Status of the reports you sent';

  @override
  String get accountSettingsScreenTheAgreementForUsingPassly =>
      'The agreement for using Passly Business';

  @override
  String get accountSettingsScreenVersionLicencesAndCredits =>
      'Version, licences and credits';

  @override
  String get accountSettingsScreenWhatIsKeptOnThis =>
      'What is kept on this device';

  @override
  String get accountStatusScreenIfYouBelieveThisIs =>
      'If you believe this is a mistake, reach out to the Hyperlocal support team to reactivate your account.';

  @override
  String get allFeaturesScreenBusinessScreensOpenOnceYour =>
      'Business screens open once your shop is set up.';

  @override
  String get allFeaturesScreenEachScreenShowsLiveData =>
      'Each screen shows live data for your selected shop.';

  @override
  String get allFeaturesScreenEverythingYouManageInOne =>
      'Everything you manage, in one place';

  @override
  String get barcodeScannerScreenMultipleProductsShareThisBarcode =>
      'Multiple products share this barcode';

  @override
  String get barcodeScannerScreenPleaseSelectTheProductYou =>
      'Please select the product you scanned:';

  @override
  String get barcodeScannerScreenPositionAProductBarcodeInside =>
      'Position a product barcode inside the frame — it is detected automatically.';

  @override
  String get barcodeScannerScreenProductAddedToInventory =>
      'Product added to inventory';

  @override
  String barcodeSheetsBarcodeBarcodeValue(Object barcode, Object value) {
    return 'Barcode $barcode$value';
  }

  @override
  String get barcodeSheetsCheckTheBarcodeDigitsOr =>
      'Check the barcode digits, or add the item manually — it will be created under your shop.';

  @override
  String get barcodeSheetsCouldNotSaveTheProduct =>
      'Could not save the product';

  @override
  String get barcodeSheetsEAN8UPCAEAN =>
      'EAN-8, UPC-A, EAN-13 or GTIN-14 — digits only.';

  @override
  String get barcodeSheetsMRPCannotBeLowerThan =>
      'MRP cannot be lower than the selling price';

  @override
  String barcodeSheetsNoCatalogProductMatchesBarcode(Object barcode) {
    return 'No catalog product matches barcode $barcode.';
  }

  @override
  String get barcodeSheetsSellingPrice => 'Selling price *';

  @override
  String get barcodeSheetsThisProductIsAlreadyIn =>
      'This product is already in your inventory';

  @override
  String get barcodeSheetsThisProductIsNotCurrently =>
      'This product is not currently published in the shared catalog. You cannot list it right now.';

  @override
  String get barcodeSheetsUnpublishedProductsStayAsDrafts =>
      'Unpublished products stay as drafts';

  @override
  String get businessCategoryScreenApprovedBusinessCategories =>
      'Approved business categories';

  @override
  String get businessCategoryScreenCouldNotLoadTheRequirements =>
      'Could not load the requirements for this category.';

  @override
  String get businessCategoryScreenNoCategorySpecificDocumentsAre =>
      'No category-specific documents are required.';

  @override
  String get businessCategoryScreenTheCategoryIsSetAt =>
      'The category is set at registration and verified by the platform — changing it starts a new verification, so contact support.';

  @override
  String get businessInfoScreenTheseDetailsComeFromYour =>
      'These details come from your shop record. Use Edit shop to change the contact fields.';

  @override
  String get common123456 => '123456';

  @override
  String get common500 => '500';

  @override
  String get common6DigitCode => '6-digit code';

  @override
  String get common6DigitPincode => '6-digit pincode';

  @override
  String get common9999999999 => '99999 99999';

  @override
  String get common99999999992 => '9999999999';

  @override
  String get common99999999993 => '9999999999';

  @override
  String get commonAPIBaseURL => 'API base URL';

  @override
  String get commonAPIKey => 'API key';

  @override
  String get commonAPISecret => 'API secret';

  @override
  String get commonAbout => 'About';

  @override
  String get commonAbout2 => 'About';

  @override
  String get commonAcceptingOrders => 'Accepting orders';

  @override
  String get commonAccessDenied => 'Access denied';

  @override
  String get commonAccessOnThisAccount => 'Access on this account';

  @override
  String get commonAccount => 'Account';

  @override
  String get commonAccount2 => 'Account';

  @override
  String get commonAccountProtection => 'Account protection';

  @override
  String get commonAccountSafety => 'Account safety';

  @override
  String get commonAccountStatus => 'Account status';

  @override
  String get commonActivateOffer => 'Activate offer';

  @override
  String get commonActivateOffer2 => 'Activate offer';

  @override
  String get commonActive => 'Active';

  @override
  String get commonActive2 => 'Active';

  @override
  String get commonActiveProducts => 'Active products';

  @override
  String get commonActiveSession => 'Active session';

  @override
  String get commonActivity => 'Activity';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonAddAHoliday => 'Add a holiday';

  @override
  String get commonAddATerminal => 'Add a terminal';

  @override
  String get commonAddHoliday => 'Add holiday';

  @override
  String get commonAddProduct => 'Add Product';

  @override
  String get commonAddProduct2 => 'Add product';

  @override
  String get commonAddTerminal => 'Add terminal';

  @override
  String get commonAddToInventory => 'Add to inventory';

  @override
  String get commonAddYourShop => 'Add Your Shop';

  @override
  String get commonAdditionalInformation => 'Additional information';

  @override
  String get commonAddress => 'Address';

  @override
  String get commonAdjustPin => 'Adjust Pin';

  @override
  String get commonAlertsAndPermissions => 'Alerts and permissions';

  @override
  String get commonAlertsTab => 'Alerts tab';

  @override
  String get commonAll => 'All';

  @override
  String get commonAll2 => 'All';

  @override
  String get commonAll3 => 'All';

  @override
  String get commonAllClear => 'All clear';

  @override
  String get commonAllFeatures => 'All features';

  @override
  String get commonAllFeatures2 => 'All Features';

  @override
  String get commonAllFeatures3 => 'All features';

  @override
  String get commonAllItemsWellStocked => 'All items well stocked';

  @override
  String get commonAlternatePhone => 'Alternate phone';

  @override
  String get commonApp => 'App';

  @override
  String get commonAppVersion => 'App version';

  @override
  String get commonApply => 'Apply';

  @override
  String get commonApplyManualCorrection => 'Apply manual correction';

  @override
  String get commonApplyToProducts => 'Apply to products';

  @override
  String get commonApplyingImport => 'Applying import';

  @override
  String get commonApproval => 'Approval';

  @override
  String get commonAuthentication => 'Authentication';

  @override
  String get commonAvailability => 'Availability';

  @override
  String get commonAvailable => 'Available';

  @override
  String get commonAvailableForSale => 'Available for sale';

  @override
  String get commonAvailableToCustomers => 'Available to customers';

  @override
  String get commonBack => 'Back';

  @override
  String get commonBack2 => 'Back';

  @override
  String get commonBack3 => 'Back';

  @override
  String get commonBack4 => 'Back';

  @override
  String get commonBack5 => 'Back';

  @override
  String get commonBack6 => 'Back';

  @override
  String get commonBackToHome => 'Back to Home';

  @override
  String get commonBackToImportCenter => 'Back to Import Center';

  @override
  String get commonBackToImportCenter2 => 'Back to Import Center';

  @override
  String get commonBackToIntegration => 'Back to integration';

  @override
  String get commonBackToSignIn => 'Back to sign in';

  @override
  String get commonBackToSignIn2 => 'Back to sign in';

  @override
  String get commonBackToTheIntegration => 'Back to the integration';

  @override
  String get commonBackgroundSync => 'Background sync';

  @override
  String get commonBankVerification => 'Bank Verification';

  @override
  String get commonBarcode => 'Barcode';

  @override
  String get commonBarcodeOptional => 'Barcode (optional)';

  @override
  String get commonBrand => 'Brand';

  @override
  String get commonBrandOptional => 'Brand (optional)';

  @override
  String get commonBulkExcelImport => 'Bulk Excel import';

  @override
  String get commonBusinessCategory => 'Business Category';

  @override
  String get commonBusinessCategory2 => 'Business category';

  @override
  String get commonBusinessDashboard => 'Business dashboard';

  @override
  String get commonBusinessDescription => 'Business Description';

  @override
  String get commonBusinessInformation => 'Business information';

  @override
  String get commonBusinessInformation2 => 'Business information';

  @override
  String get commonBusinessInsights => 'Business insights';

  @override
  String get commonBusinessPhoneNumber => 'Business phone number';

  @override
  String get commonBusinessType => 'Business Type';

  @override
  String get commonBusinessType2 => 'Business Type';

  @override
  String get commonBySource => 'By source';

  @override
  String get commonCallViews => 'Call views';

  @override
  String get commonCamera => 'Camera';

  @override
  String get commonCatalogReference => 'Catalog reference';

  @override
  String get commonCatalogueAndInventory => 'Catalogue and inventory';

  @override
  String get commonCategory => 'Category';

  @override
  String get commonCategory2 => 'Category';

  @override
  String get commonCategory3 => 'Category';

  @override
  String get commonCategoryOptional => 'Category (optional)';

  @override
  String get commonChangeNumber => 'Change number';

  @override
  String get commonChannels => 'Channels';

  @override
  String get commonChannels2 => 'Channels';

  @override
  String get commonCheckTheSyncHistory => 'Check the sync history';

  @override
  String get commonChooseAnExistingPhoto => 'Choose an existing photo';

  @override
  String get commonChooseAnotherFile => 'Choose another file';

  @override
  String get commonChooseAnotherProduct => 'Choose another product';

  @override
  String get commonChooseAnotherProduct2 => 'Choose another product';

  @override
  String get commonChooseAnotherProduct3 => 'Choose another product';

  @override
  String get commonChooseAnotherProduct4 => 'Choose another product';

  @override
  String get commonChooseExcelFile => 'Choose Excel file';

  @override
  String get commonChooseExcelFile2 => 'Choose Excel file';

  @override
  String get commonChooseLocationOnMap => 'Choose Location on Map';

  @override
  String get commonChooseScreenshot => 'Choose screenshot';

  @override
  String get commonChooseWhatYouReceive => 'Choose what you receive';

  @override
  String get commonCity => 'City';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonClear2 => 'Clear';

  @override
  String get commonClearFilters => 'Clear filters';

  @override
  String get commonClearSearch => 'Clear search';

  @override
  String get commonClearSearch2 => 'Clear search';

  @override
  String get commonClearSearch3 => 'Clear search';

  @override
  String get commonClicksToday => 'Clicks today';

  @override
  String get commonClose => 'Close';

  @override
  String get commonClose2 => 'Close';

  @override
  String get commonClose3 => 'Close';

  @override
  String get commonClose4 => 'Close';

  @override
  String get commonClosed => 'Closed';

  @override
  String get commonCloses => 'Closes';

  @override
  String get commonClosingTime => 'Closing Time';

  @override
  String get commonCompleteYourProfile => 'Complete your profile';

  @override
  String get commonCompliance => 'Compliance';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonConfirmPassword => 'Confirm password';

  @override
  String get commonConfirmPassword2 => 'Confirm password';

  @override
  String get commonConfirmShopLocation => 'Confirm shop location';

  @override
  String get commonConfirmShopLocation2 => 'Confirm Shop Location';

  @override
  String get commonConflicts => 'Conflicts';

  @override
  String get commonConnectPOS => 'Connect POS';

  @override
  String get commonConnectionType => 'Connection type';

  @override
  String get commonConnector => 'Connector';

  @override
  String get commonContact => 'Contact';

  @override
  String get commonContactSupport => 'Contact support';

  @override
  String get commonContactSupport2 => 'Contact Support';

  @override
  String get commonContactSupport3 => 'Contact support';

  @override
  String get commonContactSupport4 => 'Contact support';

  @override
  String get commonContactUs => 'Contact us';

  @override
  String get commonContinueWithGoogle => 'Continue with Google';

  @override
  String get commonCoordinates => 'Coordinates';

  @override
  String get commonCopyEMailAddress => 'Copy e-mail address';

  @override
  String get commonCopyLink => 'Copy link';

  @override
  String get commonCopyPhoneNumber => 'Copy phone number';

  @override
  String get commonCopyReportInstead => 'Copy report instead';

  @override
  String get commonCopyRequest => 'Copy request';

  @override
  String get commonCopyTicketNumber => 'Copy ticket number';

  @override
  String get commonCouldNotLoadInventory => 'Could not load inventory';

  @override
  String get commonCouldNotLoadInventory2 => 'Could not load inventory';

  @override
  String get commonCouldNotLoadReports => 'Could not load reports';

  @override
  String get commonCouldNotLoadThisShop => 'Could not load this shop';

  @override
  String get commonCounter1 => 'Counter 1';

  @override
  String get commonCreateANewAccount => 'Create a new account';

  @override
  String get commonCreateAccount => 'Create account';

  @override
  String get commonCreateBusinessAccount => 'Create business account';

  @override
  String get commonCreateNewPassword => 'Create new password';

  @override
  String get commonCreateOffer => 'Create offer';

  @override
  String get commonCreateOffer2 => 'Create offer';

  @override
  String get commonCreateOffer3 => 'Create offer';

  @override
  String get commonCreateOffer4 => 'Create offer';

  @override
  String get commonCreateOffer5 => 'Create offer';

  @override
  String get commonCreateOffer6 => 'Create offer';

  @override
  String get commonCreateProduct => 'Create product';

  @override
  String get commonCreateProfile => 'Create Profile';

  @override
  String get commonCreatingProfile => 'Creating Profile...';

  @override
  String get commonCurrentBusiness => 'Current business';

  @override
  String get commonCustomerInteractions => 'Customer interactions';

  @override
  String get commonCustomerRating => 'Customer rating';

  @override
  String get commonCustomerSearches => 'Customer searches';

  @override
  String get commonDataStorage => 'Data & storage';

  @override
  String get commonDecrease => 'Decrease';

  @override
  String get commonDeepLink => 'Deep link';

  @override
  String get commonDelivery => 'Delivery';

  @override
  String get commonDeliveryAvailable => 'Delivery available';

  @override
  String get commonDeliveryFee => 'Delivery fee';

  @override
  String get commonDeliveryRadiusKm => 'Delivery radius (km)';

  @override
  String get commonDescription => 'Description';

  @override
  String get commonDescription2 => 'Description';

  @override
  String get commonDescriptionOptional => 'Description (optional)';

  @override
  String get commonDetectedAddress => 'Detected Address';

  @override
  String get commonDevices => 'Devices';

  @override
  String get commonDisableOffer => 'Disable offer';

  @override
  String get commonDisableOffer2 => 'Disable offer';

  @override
  String get commonDisabled => 'Disabled';

  @override
  String get commonDiscard => 'Discard';

  @override
  String get commonDiscard2 => 'Discard';

  @override
  String get commonDisconnect => 'Disconnect';

  @override
  String get commonDisconnectPOS => 'Disconnect POS?';

  @override
  String get commonDismiss => 'Dismiss';

  @override
  String get commonDocumentVerification => 'Document Verification';

  @override
  String get commonDocuments => 'Documents';

  @override
  String get commonDone => 'Done';

  @override
  String get commonDone2 => 'Done';

  @override
  String get commonDownloadSample => 'Download sample';

  @override
  String get commonEG8901234567890 => 'e.g. 8901234567890';

  @override
  String get commonEGKiranaCorner => 'e.g. Kirana Corner';

  @override
  String get commonEGMonsoonSale => 'e.g. Monsoon Sale';

  @override
  String get commonEMail => 'E-mail';

  @override
  String get commonEMail2 => 'E-mail';

  @override
  String get commonEasyManagement => 'Easy Management';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonEditProduct => 'Edit product';

  @override
  String get commonEditProfile => 'Edit profile';

  @override
  String get commonEditShop => 'Edit shop';

  @override
  String get commonEmail => 'Email';

  @override
  String get commonEmail2 => 'Email';

  @override
  String get commonEmailOptional => 'Email (optional)';

  @override
  String get commonEmailOrPhoneNumber => 'Email or phone number';

  @override
  String get commonEndDate => 'End date';

  @override
  String get commonEnterBarcode => 'Enter barcode';

  @override
  String get commonEnterBarcodeManually => 'Enter barcode manually';

  @override
  String get commonEnterGSTIN => 'Enter GSTIN';

  @override
  String get commonEnterLocationManually => 'Enter Location Manually';

  @override
  String get commonEnterManually => 'Enter Manually';

  @override
  String get commonEnterManually2 => 'Enter manually';

  @override
  String get commonEnterUdyamNumber => 'Enter Udyam Number';

  @override
  String get commonErrors => 'errors';

  @override
  String get commonErrors2 => 'Errors';

  @override
  String get commonEveryYear => 'Every year';

  @override
  String get commonExcelCSV => 'Excel / CSV';

  @override
  String get commonExcelImports => 'Excel imports';

  @override
  String get commonExcelImports2 => 'Excel imports';

  @override
  String get commonExpired => 'Expired';

  @override
  String get commonExpires => 'Expires';

  @override
  String get commonFAQs => 'FAQs';

  @override
  String get commonFailed => 'Failed';

  @override
  String get commonFailed2 => 'Failed';

  @override
  String get commonFailed3 => 'Failed';

  @override
  String get commonFailedImport => 'Failed import';

  @override
  String get commonFailedToLoad => 'Failed to load';

  @override
  String get commonFilters => 'Filters';

  @override
  String get commonFilters2 => 'Filters';

  @override
  String get commonForgotPassword => 'Forgot password';

  @override
  String get commonForgotPassword2 => 'Forgot password?';

  @override
  String get commonFreeDeliveryAbove => 'Free delivery above';

  @override
  String get commonFresh => 'Fresh';

  @override
  String get commonFresh2 => 'fresh';

  @override
  String get commonFreshness => 'Freshness';

  @override
  String get commonFulfilment => 'Fulfilment';

  @override
  String get commonFullName => 'Full Name';

  @override
  String get commonFullName2 => 'Full name';

  @override
  String get commonFullSync => 'Full sync';

  @override
  String get commonGSTINOptional => 'GSTIN (optional)';

  @override
  String get commonGallery => 'Gallery';

  @override
  String get commonGetStarted => 'Get Started';

  @override
  String get commonGoToConnectionSetup => 'Go to connection setup';

  @override
  String get commonGoToConnectionSetup2 => 'Go to connection setup';

  @override
  String get commonGoToDashboard => 'Go to Dashboard';

  @override
  String get commonHelpCenter => 'Help Center';

  @override
  String get commonHelpCentre => 'Help centre';

  @override
  String get commonHelpCentre2 => 'Help centre';

  @override
  String get commonHelpCentre3 => 'Help centre';

  @override
  String get commonHelpSupport => 'Help & support';

  @override
  String get commonHelpSupport2 => 'Help & support';

  @override
  String get commonHistory => 'History';

  @override
  String get commonHolidays => 'Holidays';

  @override
  String get commonHowCanWeHelp => 'How can we help?';

  @override
  String get commonHyperLocal => 'HyperLocal';

  @override
  String get commonHyperlocalShopkeeper => 'Hyperlocal Shopkeeper';

  @override
  String get commonIdentity => 'Identity';

  @override
  String get commonImage => 'Image';

  @override
  String get commonImportAnotherFile => 'Import another file';

  @override
  String get commonImportCenter => 'Import Center';

  @override
  String get commonImportFailed => 'Import failed';

  @override
  String get commonImportFailed2 => 'Import failed';

  @override
  String get commonImportFromExcel => 'Import from Excel';

  @override
  String get commonImportFromExcel2 => 'Import from Excel';

  @override
  String get commonImportHistory => 'Import history';

  @override
  String get commonImportResult => 'Import result';

  @override
  String get commonImportantNotification => 'Important notification';

  @override
  String get commonInAppAlerts => 'In-app alerts';

  @override
  String get commonInStock => 'In Stock';

  @override
  String get commonInStock2 => 'In Stock';

  @override
  String get commonInStock3 => 'In stock';

  @override
  String get commonInactive => 'Inactive';

  @override
  String get commonIncrease => 'Increase';

  @override
  String get commonIncremental => 'Incremental';

  @override
  String get commonInsightsUnavailable => 'Insights unavailable';

  @override
  String get commonInteractions => 'Interactions';

  @override
  String get commonInteractionsToday => 'Interactions today';

  @override
  String get commonInventory => 'Inventory';

  @override
  String get commonInventory2 => 'Inventory';

  @override
  String get commonInventory3 => 'Inventory';

  @override
  String get commonInventoryFreshness => 'Inventory freshness';

  @override
  String get commonInventoryStale => 'Inventory stale';

  @override
  String get commonInventoryStatus => 'Inventory status';

  @override
  String get commonInventorySyncStatus => 'Inventory sync status';

  @override
  String get commonItems => 'Items';

  @override
  String get commonLandmarkOptional => 'Landmark (optional)';

  @override
  String get commonLanguage => 'Language';

  @override
  String get commonLastImport => 'Last import';

  @override
  String get commonLastInventoryUpdate => 'Last inventory update';

  @override
  String get commonLastPOSSync => 'Last POS sync';

  @override
  String get commonLatitude => 'Latitude';

  @override
  String get commonLatitude2 => 'Latitude';

  @override
  String get commonLegal => 'Legal';

  @override
  String get commonLinkedProducts => 'Linked products';

  @override
  String get commonLocation => 'Location';

  @override
  String get commonLog => 'Log';

  @override
  String get commonLogOut => 'Log out';

  @override
  String get commonLogOut2 => 'Log out';

  @override
  String get commonLogout => 'Logout';

  @override
  String get commonLongitude => 'Longitude';

  @override
  String get commonLongitude2 => 'Longitude';

  @override
  String get commonLookUp => 'Look up';

  @override
  String get commonLow => 'Low';

  @override
  String get commonLowStock => 'Low stock';

  @override
  String get commonLowStock2 => 'Low Stock';

  @override
  String get commonLowStock3 => 'Low stock';

  @override
  String get commonLowStock4 => 'Low Stock';

  @override
  String get commonLowStock5 => 'Low stock';

  @override
  String get commonMRP => 'MRP';

  @override
  String get commonMRPOptional => 'MRP (optional)';

  @override
  String get commonMRPOptional2 => 'MRP (optional)';

  @override
  String get commonMarkAllRead => 'Mark all read';

  @override
  String get commonMarkRead => 'Mark read';

  @override
  String get commonMax => 'Max';

  @override
  String get commonMessageSent => 'Message sent';

  @override
  String get commonMessageTheSupportTeam => 'Message the support team';

  @override
  String get commonMessages => 'Messages';

  @override
  String get commonMin => 'Min';

  @override
  String get commonMinOrderAmount => 'Min order amount';

  @override
  String get commonMobileNumber => 'Mobile number';

  @override
  String get commonMore => 'More';

  @override
  String get commonMoreDetailsOptional => 'More details (optional)';

  @override
  String get commonMoreVisibility => 'More Visibility';

  @override
  String get commonMyBusiness => 'My business';

  @override
  String get commonMyBusiness2 => 'My business';

  @override
  String get commonMyProfile => 'My profile';

  @override
  String get commonMySupportTickets => 'My support tickets';

  @override
  String get commonMySupportTickets2 => 'My support tickets';

  @override
  String get commonMyTickets => 'My Tickets';

  @override
  String get commonMyTickets2 => 'My tickets';

  @override
  String get commonName => 'Name';

  @override
  String get commonNameOptional => 'Name (optional)';

  @override
  String get commonNeedClarification => 'Need clarification?';

  @override
  String get commonNeedsAttention => 'Needs attention';

  @override
  String get commonNeedsUpdate => 'Needs update';

  @override
  String get commonNewPassword => 'New password';

  @override
  String get commonNewProduct => 'New product';

  @override
  String get commonNewQuantity => 'New quantity';

  @override
  String get commonNext => 'Next';

  @override
  String get commonNoAccessToThisShop => 'No access to this shop';

  @override
  String get commonNoAccessToThisShop2 => 'No access to this shop';

  @override
  String get commonNoConnectorYet => 'No connector yet.';

  @override
  String get commonNoConnectorYet2 => 'No connector yet';

  @override
  String get commonNoConnectorYet3 => 'No connector yet';

  @override
  String get commonNoCustomerActivityYet => 'No customer activity yet';

  @override
  String get commonNoHistoryRecordedYet => 'No history recorded yet.';

  @override
  String get commonNoHistoryYet => 'No history yet';

  @override
  String get commonNoHolidaysScheduled => 'No holidays scheduled.';

  @override
  String get commonNoImage => 'No image';

  @override
  String get commonNoImage2 => 'No image';

  @override
  String get commonNoImportsYet => 'No imports yet';

  @override
  String get commonNoOtherDevices => 'No other devices';

  @override
  String get commonNoPinStoredYet => 'No pin stored yet';

  @override
  String get commonNoPriceChangesYet => 'No price changes yet';

  @override
  String get commonNoProductsYet => 'No products yet';

  @override
  String get commonNoProductsYet2 => 'No products yet';

  @override
  String get commonNoShopSelected => 'No shop selected';

  @override
  String get commonNoShopSelected2 => 'No shop selected';

  @override
  String get commonNoShopSelected3 => 'No shop selected';

  @override
  String get commonNoShopSelected4 => 'No shop selected';

  @override
  String get commonNoShopSelected5 => 'No shop selected';

  @override
  String get commonNoSyncsYet => 'No syncs yet';

  @override
  String get commonNoTicketsYet => 'No tickets yet';

  @override
  String get commonNotEstablishedYet => 'Not established yet';

  @override
  String get commonNoteOptional => 'Note (optional)';

  @override
  String get commonNothingChangedYet => 'Nothing changed yet.';

  @override
  String get commonNothingToApply => 'Nothing to apply';

  @override
  String get commonNothingToPreview => 'Nothing to preview';

  @override
  String get commonNotification => 'Notification';

  @override
  String get commonNotificationPreferences => 'Notification preferences';

  @override
  String get commonNotificationSettings => 'Notification settings';

  @override
  String get commonNotificationSettings2 => 'Notification settings';

  @override
  String get commonNotifications => 'Notifications';

  @override
  String get commonNotifications2 => 'Notifications';

  @override
  String get commonOTPVerification => 'OTP Verification';

  @override
  String get commonOfferDetails => 'Offer details';

  @override
  String get commonOfferTitle => 'Offer title';

  @override
  String get commonOfferType => 'Offer type';

  @override
  String get commonOffers => 'Offers';

  @override
  String get commonOffersAndPricing => 'Offers and pricing';

  @override
  String get commonOffersPricing => 'Offers & pricing';

  @override
  String get commonOnlyRecentlyUpdated => 'Only recently updated';

  @override
  String get commonOpenImportHistory => 'Open import history';

  @override
  String get commonOpenProduct => 'Open Product';

  @override
  String get commonOpenSystemSettings => 'Open System Settings';

  @override
  String get commonOpenSystemSettings2 => 'Open System Settings';

  @override
  String get commonOpeningTime => 'Opening Time';

  @override
  String get commonOpens => 'Opens';

  @override
  String get commonOperatingHours => 'Operating hours';

  @override
  String get commonOptional => 'Optional';

  @override
  String get commonOr => 'or';

  @override
  String get commonOr2 => 'or';

  @override
  String get commonOrders => 'Orders';

  @override
  String get commonOther => 'Other';

  @override
  String get commonOtherDevices => 'Other devices';

  @override
  String get commonOut => 'Out';

  @override
  String get commonOutOfStock => 'Out of Stock';

  @override
  String get commonOutOfStock2 => 'Out of Stock';

  @override
  String get commonOutOfStock3 => 'Out of stock';

  @override
  String get commonOverview => 'Overview';

  @override
  String get commonPOSConnected => 'POS connected';

  @override
  String get commonPOSConnectionSetup => 'POS connection setup';

  @override
  String get commonPOSIntegration => 'POS integration';

  @override
  String get commonPOSProblem => 'POS problem';

  @override
  String get commonPOSProvider => 'POS provider';

  @override
  String get commonPOSProvider2 => 'POS provider';

  @override
  String get commonPOSSync => 'POS sync';

  @override
  String get commonPOSSync2 => 'POS sync';

  @override
  String get commonPOSSync3 => 'POS Sync';

  @override
  String get commonPOSSync4 => 'POS sync';

  @override
  String get commonPOSSync5 => 'POS sync';

  @override
  String get commonPassword => 'Password';

  @override
  String get commonPassword2 => 'Password';

  @override
  String get commonPast => 'Past';

  @override
  String get commonPeakHours => 'Peak hours';

  @override
  String get commonPeakHours2 => 'Peak hours';

  @override
  String get commonPhone => 'Phone';

  @override
  String get commonPhone2 => 'Phone';

  @override
  String get commonPhoneNumber => 'Phone number';

  @override
  String get commonPhoneNumberOrEmail => 'Phone number or email';

  @override
  String get commonPickup => 'Pickup';

  @override
  String get commonPickupAvailable => 'Pickup available';

  @override
  String get commonPincode => 'Pincode';

  @override
  String get commonPlatform => 'Platform';

  @override
  String get commonPreparingScreenshot => 'Preparing screenshot...';

  @override
  String get commonPrice => 'Price';

  @override
  String get commonPriceAndMRP => 'Price and MRP';

  @override
  String get commonPriceHistory => 'Price history';

  @override
  String get commonPriceHistory2 => 'Price history';

  @override
  String get commonPriceList => 'Price list';

  @override
  String get commonPriceRange => 'Price range';

  @override
  String get commonPriceUpdated => 'Price updated';

  @override
  String get commonPricing => 'Pricing';

  @override
  String get commonPricingOffers => 'Pricing & Offers';

  @override
  String get commonPriority => 'Priority';

  @override
  String get commonPrivacyPolicy => 'Privacy policy';

  @override
  String get commonPrivacyPolicy2 => 'Privacy Policy';

  @override
  String get commonPrivacyPolicy3 => 'Privacy policy';

  @override
  String get commonProcessed => 'Processed';

  @override
  String get commonProduct => 'Product';

  @override
  String get commonProductClicks => 'Product clicks';

  @override
  String get commonProductCreated => 'Product created';

  @override
  String get commonProductNotFound => 'Product not found';

  @override
  String get commonProductUpdated => 'Product updated';

  @override
  String get commonProducts => 'Products';

  @override
  String get commonProducts2 => 'Products';

  @override
  String get commonProductsInventory => 'Products & inventory';

  @override
  String get commonProfileSetupIssue => 'Profile setup issue';

  @override
  String get commonPublishImmediately => 'Publish immediately';

  @override
  String get commonPublishImmediately2 => 'Publish immediately';

  @override
  String get commonPushNotifications => 'Push notifications';

  @override
  String get commonQuantity => 'Quantity';

  @override
  String get commonQuantityChange => 'Quantity change';

  @override
  String get commonQuantityInitialStock => 'Quantity (initial stock)';

  @override
  String get commonQuickActions => 'Quick Actions';

  @override
  String get commonRatings => 'Ratings';

  @override
  String get commonReachUs => 'Reach us';

  @override
  String get commonReason => 'Reason';

  @override
  String get commonReasonOptional => 'Reason (optional)';

  @override
  String get commonRecentImports => 'Recent imports';

  @override
  String get commonRecentImports2 => 'Recent imports';

  @override
  String get commonRecentSearches => 'Recent searches';

  @override
  String get commonRecentUpdates => 'Recent updates';

  @override
  String get commonRecentUpdates2 => 'Recent Updates';

  @override
  String get commonRecentlyUpdated => 'Recently updated';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonRefresh2 => 'Refresh';

  @override
  String get commonRefresh3 => 'Refresh';

  @override
  String get commonRefresh4 => 'Refresh';

  @override
  String get commonRefresh5 => 'Refresh';

  @override
  String get commonRefresh6 => 'Refresh';

  @override
  String get commonRefresh7 => 'Refresh';

  @override
  String get commonRefresh8 => 'Refresh';

  @override
  String get commonRefresh9 => 'Refresh';

  @override
  String get commonRefreshNow => 'Refresh now';

  @override
  String get commonRefreshRecentImports => 'Refresh recent imports';

  @override
  String get commonRefreshStatus => 'Refresh status';

  @override
  String get commonRegisterYourShop => 'Register Your Shop';

  @override
  String get commonRegisteredAddress => 'Registered address';

  @override
  String get commonRegisteredAs => 'Registered as';

  @override
  String get commonRegistrationSubmitted => 'Registration Submitted!';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonRemoveHoliday => 'Remove holiday';

  @override
  String get commonRemovePhoto => 'Remove photo';

  @override
  String get commonRemoveScreenshot => 'Remove screenshot';

  @override
  String get commonRepeatsEveryYear => 'Repeats every year';

  @override
  String get commonReplace => 'Replace';

  @override
  String get commonReportAnIssue => 'Report an issue';

  @override
  String get commonReportAnIssue2 => 'Report an issue';

  @override
  String get commonReportIssue => 'Report Issue';

  @override
  String get commonReportIssue2 => 'Report issue';

  @override
  String get commonReportSent => 'Report sent';

  @override
  String get commonReportSomethingElse => 'Report something else';

  @override
  String get commonReportsAndInsights => 'Reports and insights';

  @override
  String get commonReportsInsights => 'Reports & insights';

  @override
  String get commonReportsInsights2 => 'Reports & Insights';

  @override
  String get commonReportsUnavailable => 'Reports unavailable';

  @override
  String get commonResendCode => 'Resend code';

  @override
  String get commonReset => 'Reset';

  @override
  String get commonResetPassword => 'Reset password';

  @override
  String get commonResetYourPassword => 'Reset your password';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonRetry10 => 'Retry';

  @override
  String get commonRetry11 => 'Retry';

  @override
  String get commonRetry12 => 'Retry';

  @override
  String get commonRetry2 => 'Retry';

  @override
  String get commonRetry3 => 'Retry';

  @override
  String get commonRetry4 => 'Retry';

  @override
  String get commonRetry5 => 'Retry';

  @override
  String get commonRetry6 => 'Retry';

  @override
  String get commonRetry7 => 'Retry';

  @override
  String get commonRetry8 => 'Retry';

  @override
  String get commonRetry9 => 'Retry';

  @override
  String get commonRetryCamera => 'Retry camera';

  @override
  String get commonRetryThisSync => 'Retry this sync';

  @override
  String get commonReviewDetails => 'Review details';

  @override
  String get commonReviewImport => 'Review import';

  @override
  String get commonReviewYourDetails => 'Review your details';

  @override
  String get commonReviewed => 'Reviewed';

  @override
  String get commonRows => 'rows';

  @override
  String get commonSKUOptional => 'SKU (optional)';

  @override
  String get commonSMS => 'SMS';

  @override
  String get commonSave => 'Save';

  @override
  String get commonSaveAsDraft => 'Save as draft';

  @override
  String get commonSaveChanges => 'Save changes';

  @override
  String get commonSaveChanges2 => 'Save changes';

  @override
  String get commonSaveOperatingHours => 'Save operating hours';

  @override
  String get commonSavePrice => 'Save price';

  @override
  String get commonSaveSettings => 'Save settings';

  @override
  String get commonSaveSettings2 => 'Save settings';

  @override
  String get commonSaveStockUpdate => 'Save stock update';

  @override
  String get commonScanBarcode => 'Scan barcode';

  @override
  String get commonScanBarcode2 => 'Scan barcode';

  @override
  String get commonScanBarcode3 => 'Scan barcode';

  @override
  String get commonScheduled => 'Scheduled';

  @override
  String get commonScreenshotOptional => 'Screenshot (optional)';

  @override
  String get commonSearchHelp => 'Search help';

  @override
  String get commonSearchNameOrSKU => 'Search name or SKU';

  @override
  String get commonSecureTrusted => 'Secure & Trusted';

  @override
  String get commonSecurity => 'Security';

  @override
  String get commonSecurity2 => 'Security';

  @override
  String get commonSecurityAlerts => 'Security alerts';

  @override
  String get commonSelectACategory => 'Select a category';

  @override
  String get commonSelectAType => 'Select a type';

  @override
  String get commonSelectBusinessCategory => 'Select Business Category';

  @override
  String get commonSelectXlsxFile => 'Select .xlsx file';

  @override
  String get commonSellingPrice => 'Selling price';

  @override
  String get commonSendCode => 'Send code';

  @override
  String get commonSendResetLink => 'Send reset link';

  @override
  String get commonSession => 'Session';

  @override
  String get commonSessionsDevices => 'Sessions & devices';

  @override
  String get commonSessionsDevices2 => 'Sessions & devices';

  @override
  String get commonSetUpYourFirstShop => 'Set up your first shop';

  @override
  String get commonSettings => 'Settings';

  @override
  String get commonSettings2 => 'Settings';

  @override
  String get commonSettingsSaved => 'Settings saved';

  @override
  String get commonShopAlerts => 'Shop alerts';

  @override
  String get commonShopBusinessName => 'Shop / Business Name';

  @override
  String get commonShopBusinessName2 => 'Shop / Business Name';

  @override
  String get commonShopLocation => 'Shop Location';

  @override
  String get commonShopLocation2 => 'Shop location';

  @override
  String get commonShopName => 'Shop name';

  @override
  String get commonShopNoStreetArea => 'Shop no., street, area';

  @override
  String get commonShopProfile => 'Shop profile';

  @override
  String get commonShopProfile2 => 'Shop profile';

  @override
  String get commonShopProfile3 => 'Shop Profile';

  @override
  String get commonShopProfile4 => 'Shop profile';

  @override
  String get commonShopSettings => 'Shop settings';

  @override
  String get commonShopSettings2 => 'Shop settings';

  @override
  String get commonShopSettings3 => 'Shop settings';

  @override
  String get commonShopStatus => 'Shop status';

  @override
  String get commonShopVerification => 'Shop verification';

  @override
  String get commonShopViews => 'Shop views';

  @override
  String get commonShopkeeperApp => 'Shopkeeper App';

  @override
  String get commonShowAllJobs => 'Show all jobs';

  @override
  String get commonSignIn => 'Sign in';

  @override
  String get commonSignIn2 => 'Sign-in';

  @override
  String get commonSignIn3 => 'Sign in';

  @override
  String get commonSignInInstead => 'Sign in instead';

  @override
  String get commonSignInMethod => 'Sign-in method';

  @override
  String get commonSignInWithPhone => 'Sign in with phone';

  @override
  String get commonSignOut => 'Sign out';

  @override
  String get commonSignOut2 => 'Sign out';

  @override
  String get commonSignOut3 => 'Sign out';

  @override
  String get commonSignOutOfThisDevice => 'Sign out of this device';

  @override
  String get commonSignOutOfThisDevice2 => 'Sign out of this device';

  @override
  String get commonSignOutThisDevice => 'Sign out this device?';

  @override
  String get commonSignedInAs => 'Signed in as';

  @override
  String get commonSignedInOnThisDevice => 'Signed in on this device';

  @override
  String get commonSigningOut => 'Signing out...';

  @override
  String get commonSocialMediaOptional => 'Social Media (optional)';

  @override
  String get commonSomethingWentWrong => 'Something went wrong.';

  @override
  String get commonSomethingWentWrong2 => 'Something went wrong.';

  @override
  String get commonSort => 'Sort';

  @override
  String get commonStale => 'stale';

  @override
  String get commonStartASync => 'Start a sync';

  @override
  String get commonStartDate => 'Start date';

  @override
  String get commonStartSync => 'Start sync';

  @override
  String get commonState => 'State';

  @override
  String get commonStatus => 'Status';

  @override
  String get commonStaySignedIn => 'Stay signed in';

  @override
  String get commonStillStuck => 'Still stuck?';

  @override
  String get commonStock => 'Stock';

  @override
  String get commonStockHealth => 'Stock health';

  @override
  String get commonStockHistory => 'Stock history';

  @override
  String get commonStockLevels => 'Stock levels';

  @override
  String get commonStockQuantity => 'Stock quantity';

  @override
  String get commonStoredShopPin => 'Stored shop pin';

  @override
  String get commonSubcategoryOptional => 'Subcategory (optional)';

  @override
  String get commonSubmitRegistration => 'Submit Registration';

  @override
  String get commonSubmitted => 'Submitted';

  @override
  String get commonSubscription => 'Subscription';

  @override
  String get commonSubscription2 => 'Subscription';

  @override
  String get commonSupport => 'Support';

  @override
  String get commonSupportHours => 'Support hours';

  @override
  String get commonSupportReplied => 'Support replied';

  @override
  String get commonSwitchShop => 'Switch shop';

  @override
  String get commonSyncAgain => 'Sync again';

  @override
  String get commonSyncEvery => 'Sync every';

  @override
  String get commonSyncHistory => 'Sync history';

  @override
  String get commonSyncHistory2 => 'Sync history';

  @override
  String get commonSyncNow => 'Sync now';

  @override
  String get commonSyncNow2 => 'Sync now';

  @override
  String get commonSyncProgress => 'Sync progress';

  @override
  String get commonSyncResult => 'Sync result';

  @override
  String get commonSyncSettings => 'Sync settings';

  @override
  String get commonSynced => 'Synced';

  @override
  String get commonSynced2 => 'Synced';

  @override
  String get commonTILL01 => 'TILL-01';

  @override
  String get commonTagline => 'Tagline';

  @override
  String get commonTaglineOptional => 'Tagline (optional)';

  @override
  String get commonTakePhoto => 'Take photo';

  @override
  String get commonTellUsWhatBroke => 'Tell us what broke';

  @override
  String get commonTellUsWhatWentWrong => 'Tell us what went wrong';

  @override
  String get commonTerminals => 'Terminals';

  @override
  String get commonTermsConditions => 'Terms & Conditions';

  @override
  String get commonTermsConditions2 => 'Terms & conditions';

  @override
  String get commonTermsOfService => 'Terms of service';

  @override
  String get commonTermsOfService2 => 'Terms of service';

  @override
  String get commonTermsOfUse => 'Terms of use';

  @override
  String get commonText => '-';

  @override
  String get commonTheme => 'Theme';

  @override
  String get commonThisDevice => 'This device';

  @override
  String get commonThisTill => 'This till';

  @override
  String get commonThisWeek => 'This week';

  @override
  String get commonTicketDetails => 'Ticket details';

  @override
  String get commonTopProducts => 'Top products';

  @override
  String get commonTotal => 'Total';

  @override
  String get commonTryAgain => 'Try Again';

  @override
  String get commonTryAgain2 => 'Try Again';

  @override
  String get commonType => 'Type';

  @override
  String get commonType2 => 'Type';

  @override
  String get commonUnavailable => 'Unavailable';

  @override
  String get commonUnitSizeEG1 => 'Unit / size (e.g. 1 kg)';

  @override
  String get commonUpdatePrice => 'Update price';

  @override
  String get commonUpdateStock => 'Update Stock';

  @override
  String get commonUpdateStock2 => 'Update stock';

  @override
  String get commonUpdateStock3 => 'Update stock';

  @override
  String get commonUpdateStock4 => 'Update stock';

  @override
  String get commonUpdateThePin => 'Update the pin';

  @override
  String get commonUpdatedInTheLast24h => 'updated in the last 24h';

  @override
  String get commonUploadInventoryFile => 'Upload inventory file';

  @override
  String get commonValid => 'valid';

  @override
  String get commonValid2 => 'Valid';

  @override
  String get commonValid3 => 'Valid';

  @override
  String get commonValidatingYourFile => 'Validating your file...';

  @override
  String get commonValidity => 'Validity';

  @override
  String get commonVariantOptional => 'Variant (optional)';

  @override
  String get commonVerification => 'Verification';

  @override
  String get commonVerified => 'Verified';

  @override
  String get commonVerifyContinue => 'Verify & continue';

  @override
  String get commonVersion => 'Version';

  @override
  String get commonViewAll => 'View all';

  @override
  String get commonViewAllQuestions => 'View all questions';

  @override
  String get commonViewHistory => 'View history';

  @override
  String get commonViewHistory2 => 'View history';

  @override
  String get commonViewHistory3 => 'View history';

  @override
  String get commonViewImportHistory => 'View import history';

  @override
  String get commonViewImportHistory2 => 'View import history';

  @override
  String get commonViewMySupportTickets => 'View my support tickets';

  @override
  String get commonViewMySupportTickets2 => 'View my support tickets';

  @override
  String get commonViewResults => 'View Results';

  @override
  String get commonViewRowReport => 'View row report';

  @override
  String get commonViewSyncHistory => 'View sync history';

  @override
  String get commonViewsToday => 'Views today';

  @override
  String get commonVisibility => 'Visibility';

  @override
  String get commonVsYesterday => 'vs yesterday';

  @override
  String get commonWebsiteOptional => 'Website (optional)';

  @override
  String get commonWeeklySchedule => 'Weekly schedule';

  @override
  String get commonWelcomeBack => 'Welcome back';

  @override
  String get commonWelcomeBack2 => 'Welcome Back';

  @override
  String get commonWelcomeToHyperLocal => 'Welcome to HyperLocal!';

  @override
  String get commonWelcomeToPasslyBiz => 'Welcome to Passly Biz!';

  @override
  String get commonWhatHappened => 'What happened?';

  @override
  String get commonWhatHappensNext => 'What happens next';

  @override
  String get commonWhatIsAffected => 'What is affected?';

  @override
  String get commonWhatIsThisAbout => 'What is this about?';

  @override
  String get commonWhatShouldBePulled => 'What should be pulled?';

  @override
  String get commonWhatWeCollectAndWhy => 'What we collect and why';

  @override
  String get commonWhatYouCanDo => 'What you can do';

  @override
  String get commonWhatYouCanDoHere => 'What you can do here';

  @override
  String get commonWhatsAppNumber => 'WhatsApp number';

  @override
  String get commonWhereYouAreSignedIn => 'Where you are signed in';

  @override
  String get commonWriteAnotherMessage => 'Write another message';

  @override
  String get commonWriteToUs => 'Write to us';

  @override
  String get commonYouHaveUnsavedChanges => 'You have unsaved changes';

  @override
  String get commonYourName => 'Your name';

  @override
  String get commonYourReport => 'Your report';

  @override
  String get connectivityBannerYouReOfflineChangesCan =>
      'You\'re offline — changes can\'t be saved until you\'re back online.';

  @override
  String get contactSupportScreenDescribeTheProblemInYour =>
      'Describe the problem in your own words';

  @override
  String get contactSupportScreenIncludeMyAccountAndShop =>
      'Include my account and shop';

  @override
  String contactSupportScreenPasteTheCopiedTextInto(Object email) {
    return 'Paste the copied text into an e-mail to $email.';
  }

  @override
  String get contactSupportScreenSavesARoundTripSupport =>
      'Saves a round-trip - support can look up the right shop';

  @override
  String get contactSupportScreenSendingFilesASupportTicket =>
      'Sending files a support ticket with your topic, account and shop attached - the same details support needs to answer quickly. Its status stays visible under My support tickets, and the text can still be copied to send it by e-mail.';

  @override
  String contactSupportScreenStatusStatusLabel(Object statusLabel) {
    return 'Status: $statusLabel';
  }

  @override
  String get contactSupportScreenYourMessageBecomesATracked =>
      'Your message becomes a tracked ticket';

  @override
  String get contactSupportScreenYourMessageIsInThe =>
      'Your message is in the support queue.';

  @override
  String get createOfferScreenOfferCreatedAndLinkedTo =>
      'Offer created and linked to your products';

  @override
  String get createOfferScreenOffersNotAvailableOnYour =>
      'Offers not available on your plan';

  @override
  String createOfferScreenPrice(Object price) {
    return '₹$price';
  }

  @override
  String get createOfferScreenTermsConditionsOptional =>
      'Terms & conditions (optional)';

  @override
  String get createOfferScreenUpgradeYourPlanToCreate =>
      'Upgrade your plan to create discount offers. Your current plan does not include offers.';

  @override
  String get createProfileScreenAShortDescriptionOfYour =>
      'A short description of your shop';

  @override
  String get createProfileScreenContactNumberOptional =>
      'Contact Number (optional)';

  @override
  String get createProfileScreenCreateYourShopkeeperProfile =>
      'Create Your Shopkeeper Profile';

  @override
  String get createProfileScreenSetUpYourShopTo =>
      'Set up your shop to start managing products and inventory.';

  @override
  String get createProfileScreenYouExampleCom => 'you@example.com';

  @override
  String get dashboardScreenCompleteShopVerificationToPublish =>
      'Complete shop verification to publish to customers';

  @override
  String dashboardScreenCount(Object count) {
    return '$count';
  }

  @override
  String dashboardScreenFailedImportNameFailedImportRowsRowSCould(
    Object failedImportName,
    Object failedImportRows,
  ) {
    return '$failedImportName — $failedImportRows row(s) could not be applied';
  }

  @override
  String dashboardScreenGreetingFirstName(Object _greeting, Object _firstName) {
    return '$_greeting, $_firstName';
  }

  @override
  String dashboardScreenLabelValue(Object label, Object value) {
    return '$label: $value';
  }

  @override
  String dashboardScreenLowStockLowValueFlaggedLabel(
    Object lowStock,
    Object value,
    Object flaggedLabel,
  ) {
    return '$lowStock low $value$flaggedLabel';
  }

  @override
  String get dashboardScreenNothingYetUpdatesWillAppear =>
      'Nothing yet — updates will appear here.';

  @override
  String dashboardScreenQtyQuantity(Object quantity) {
    return 'qty $quantity';
  }

  @override
  String dashboardScreenStaleCountProductSNotUpdated(Object staleCount) {
    return '$staleCount product(s) not updated in a while';
  }

  @override
  String dashboardScreenUnreadNew(Object unread) {
    return '$unread new';
  }

  @override
  String dashboardScreenUnreadNotificationsUnreadNotificationS(
    Object unreadNotifications,
  ) {
    return '$unreadNotifications unread notification(s)';
  }

  @override
  String get dashboardScreenWelcomeBackToYourBusiness =>
      'Welcome back to your business dashboard.';

  @override
  String get dashboardScreenYouDoNotHaveAccess =>
      'You do not have access to this shop.';

  @override
  String get dashboardScreenYourAccountIsReadyAdd =>
      'Your account is ready. Add your first store to start managing products, inventory and offers — or complete your profile details from the Account tab anytime.';

  @override
  String debouncedSearchFieldRemoveTerm(Object term) {
    return 'Remove \"$term\"';
  }

  @override
  String get editProfileScreenContactSupportToChangeYour =>
      'Contact support to change your phone number';

  @override
  String get editShopScreenAOneLinePitchCustomers =>
      'A one-line pitch customers see first';

  @override
  String get editShopScreenOnlyTheFieldsYouChanged =>
      'Only the fields you changed are sent to the server.';

  @override
  String get forgotPasswordScreenEnterYourEmailOrPhone =>
      'Enter your email or phone number and we\'ll send you a link to reset your password.';

  @override
  String get forgotPasswordScreenIfAnAccountExistsWith =>
      'If an account exists with this email/phone, you\'ll receive a reset link shortly.';

  @override
  String holidaysSectionAddHolidayLabel(Object label) {
    return 'Add holiday — $label';
  }

  @override
  String get holidaysSectionDaysTheShopStaysClosed =>
      'Days the shop stays closed — customers are told in advance.';

  @override
  String get holidaysSectionDiwaliStaffTraining => 'Diwali, Staff training…';

  @override
  String get importCenterScreenBringProductsIntoYourShop =>
      'Bring products into your shop — manually or in bulk. Choose a method below to get started.';

  @override
  String get importCenterScreenBulkUploadAWorkbookTo =>
      'Bulk-upload a workbook to update stock, prices or catalog. Download a sample template, fill it in, then preview before applying.';

  @override
  String get importCenterScreenGetTheImportTemplateWorkbook =>
      'Get the import template workbook';

  @override
  String importCenterScreenValidRowsValidErrorRowsErrors(
    Object validRows,
    Object errorRows,
  ) {
    return '$validRows valid, $errorRows errors';
  }

  @override
  String get importHistoryScreenExcelFilesYouUploadWill =>
      'Excel files you upload will appear here with their row-level outcomes.';

  @override
  String importHistoryScreenRowsTotalRowsSuccessSuccessRowsFailed(
    Object totalRows,
    Object successRows,
    Object failedRowCount,
  ) {
    return 'Rows $totalRows · Success $successRows · Failed $failedRowCount';
  }

  @override
  String importPreviewScreenRowRowNumberValue(Object rowNumber, Object value) {
    return 'Row $rowNumber$value';
  }

  @override
  String get importPreviewScreenShowOnlyValidationErrors =>
      'Show only validation errors';

  @override
  String get importPreviewScreenValidWillBeAppliedTo =>
      'Valid — will be applied to inventory';

  @override
  String importPreviewScreenValue(Object value) {
    return '$value';
  }

  @override
  String importPreviewScreenValueValue2(Object value, Object value2) {
    return '$value — $value2';
  }

  @override
  String get importProcessingScreenApplyingRowsToYourInventory =>
      'Applying rows to your inventory…';

  @override
  String get importProcessingScreenThisUsuallyTakesAFew =>
      'This usually takes a few seconds.';

  @override
  String importProcessingScreenViewErrorsFailed(Object failed) {
    return 'View Errors ($failed)';
  }

  @override
  String importReportSheetAllRowsTotal(Object total) {
    return 'All rows ($total)';
  }

  @override
  String get importReportSheetCouldNotLoadTheReport =>
      'Could not load the report for this import.';

  @override
  String importReportSheetFailedErrors(Object errors) {
    return 'Failed ($errors)';
  }

  @override
  String importReportSheetRowRowNumberValue(Object rowNumber, Object value) {
    return 'Row $rowNumber$value';
  }

  @override
  String importReportSheetStatusLabelTotalRowsRowsSuccessRowsSuccess(
    Object statusLabel,
    Object totalRows,
    Object successRows,
    Object failedRowCount,
  ) {
    return '$statusLabel · $totalRows rows · $successRows success, $failedRowCount failed';
  }

  @override
  String importReportSheetValueValue2(Object value, Object value2) {
    return '$value — $value2';
  }

  @override
  String get importResultScreenCouldNotOpenThisImport =>
      'Could not open this import';

  @override
  String importResultScreenErrorRowsRowSCouldNot(Object errorRows) {
    return '$errorRows row(s) could not be imported.';
  }

  @override
  String get importResultScreenThisImportIsNoLonger =>
      'This import is no longer available.';

  @override
  String get importUploadScreenExcelImportNotAvailableOn =>
      'Excel import not available on your plan';

  @override
  String get importUploadScreenOnlyXlsxWorkbooksAreAccepted =>
      'Only .xlsx workbooks are accepted. Download the sample from the Import Center to see the exact columns.';

  @override
  String get importUploadScreenUpgradeYourPlanToBulk =>
      'Upgrade your plan to bulk-upload a workbook. Your current plan does not include bulk import.';

  @override
  String get importUploadScreenUploading => 'Uploading…';

  @override
  String get importUploadScreenYourFileIsBeingChecked =>
      'Your file is being checked row by row. Nothing is applied yet.';

  @override
  String get insightsDrillDownScreenCouldNotLoadThisReport =>
      'Could not load this report';

  @override
  String insightsDrillDownScreenDailyUnitLabel(Object unitLabel) {
    return 'Daily $unitLabel';
  }

  @override
  String insightsDrillDownScreenDaysDays(Object days) {
    return '$days days';
  }

  @override
  String get insightsDrillDownScreenNoCustomerActivityInThis =>
      'No customer activity in this window yet.';

  @override
  String insightsDrillDownScreenPeakLabel(Object label) {
    return 'Peak $label';
  }

  @override
  String insightsDrillDownScreenRank(Object rank) {
    return '$rank';
  }

  @override
  String insightsDrillDownScreenTopProductsUpToKInsightsMaxTopProducts(
    Object kInsightsMaxTopProducts,
  ) {
    return 'Top products (up to $kInsightsMaxTopProducts)';
  }

  @override
  String insightsDrillDownScreenTotalInLastRangeDaysDays(Object rangeDays) {
    return 'Total in last $rangeDays days';
  }

  @override
  String insightsDrillDownScreenTotalUnitLabel(Object total, Object unitLabel) {
    return '$total $unitLabel';
  }

  @override
  String insightsDrillDownScreenValue(Object value) {
    return '$value';
  }

  @override
  String insightsDrillDownScreenViews(Object views) {
    return '$views';
  }

  @override
  String insightsDrillDownScreenViewsUnitLabel(Object views, Object unitLabel) {
    return '$views $unitLabel';
  }

  @override
  String get insightsScreenAllMetricsAreComputedBy =>
      'All metrics are computed by the backend from live customer activity.';

  @override
  String insightsScreenBusiestHourLabelViewsViews(Object label, Object views) {
    return 'Busiest hour: $label · $views views';
  }

  @override
  String insightsScreenCountShareLabel(Object count, Object shareLabel) {
    return '$count · $shareLabel';
  }

  @override
  String get insightsScreenCurrentInventorySnapshotFreshnessUses =>
      'Current inventory snapshot; freshness uses the last 24h.';

  @override
  String insightsScreenDaysDays(Object days) {
    return '$days days';
  }

  @override
  String insightsScreenFreshFreshStaleStale(Object fresh, Object stale) {
    return '$fresh fresh · $stale stale';
  }

  @override
  String get insightsScreenLiveShopSnapshotInventoryListings =>
      'Live shop snapshot · inventory, listings, offers and profile, computed from current data.';

  @override
  String insightsScreenNothingHasBeenRecordedIn(Object rangeDays) {
    return 'Nothing has been recorded in the last $rangeDays days. These reports fill in automatically once customers view your shop and products.';
  }

  @override
  String insightsScreenQueryCount(Object query, Object count) {
    return '$query · $count';
  }

  @override
  String get insightsScreenReportsNotAvailableOnYour =>
      'Reports not available on your plan';

  @override
  String get insightsScreenSalesTotalsAndRevenueAre =>
      'Sales totals and revenue are not available. The metrics below show customer engagement, not completed sales.';

  @override
  String insightsScreenScoreLabelOfTotalProductsProducts(
    Object scoreLabel,
    Object totalProducts,
  ) {
    return '$scoreLabel of $totalProducts products';
  }

  @override
  String get insightsScreenSetUpYourShopTo =>
      'Set up your shop to unlock its reports and insights.';

  @override
  String insightsScreenToday(Object today) {
    return '$today';
  }

  @override
  String insightsScreenTrailingRangeDaysDaysComputedFrom(Object rangeDays) {
    return 'Trailing $rangeDays days, computed from live customer activity.';
  }

  @override
  String get insightsScreenUpgradeYourPlanToSee =>
      'Upgrade your plan to see customer activity and trends. Your current plan does not include reports.';

  @override
  String insightsScreenValue(Object value) {
    return '$value';
  }

  @override
  String insightsScreenViewsViews(Object views) {
    return '$views views';
  }

  @override
  String get inventoryDashboardScreenCountsComeStraightFromYour =>
      'Counts come straight from your shop\'s live inventory.';

  @override
  String get inventoryImportScreenAllRowsValidatedSuccessfullyReview =>
      'All rows validated successfully.\nReview the summary above and confirm to apply changes.';

  @override
  String get inventoryImportScreenExcelImportNotAvailableOn =>
      'Excel import not available on your plan';

  @override
  String get inventoryImportScreenImportProductsFromExcel =>
      'Import products from Excel';

  @override
  String inventoryImportScreenRowRowNumber(Object rowNumber) {
    return 'Row $rowNumber';
  }

  @override
  String get inventoryImportScreenUpgradeYourPlanToBulk =>
      'Upgrade your plan to bulk-import a workbook. Your current plan does not include bulk import.';

  @override
  String get inventoryImportScreenUploadAnXlsxWorkbookTo =>
      'Upload an .xlsx workbook to bulk-add or update your shop\'s inventory. The file is validated before you commit changes.';

  @override
  String inventoryImportScreenValidRowsValidErrorRowsErrors(
    Object validRows,
    Object errorRows,
  ) {
    return '$validRows valid, $errorRows errors';
  }

  @override
  String inventoryImportScreenValue(Object value) {
    return '$value';
  }

  @override
  String inventoryListScreenMatchedOfTotalProducts(
    Object matched,
    Object total,
  ) {
    return '$matched of $total products';
  }

  @override
  String get inventoryListScreenNoProductsMatchYourFilters =>
      'No products match your filters';

  @override
  String get inventoryListScreenNoProductsMatchYourSearch =>
      'No products match your search';

  @override
  String inventoryListScreenQuantityUnitsValue(Object quantity, Object value) {
    return '$quantity units · $value';
  }

  @override
  String get inventoryListScreenSearchNameBrandOrSKU =>
      'Search name, brand or SKU';

  @override
  String get inventorySharedAddProductsOrImportThem =>
      'Add products or import them from Excel first.';

  @override
  String get inventorySharedPleaseCheckYourConnectionAnd =>
      'Please check your connection and retry.';

  @override
  String inventorySharedQuantityUnitsLabel(Object quantity, Object label) {
    return '$quantity units · $label';
  }

  @override
  String inventorySharedTotalEntrValue(Object total, Object value) {
    return '$total entr$value';
  }

  @override
  String inventorySharedValue(Object value) {
    return '$value';
  }

  @override
  String get inventorySharedYouDoNotHaveAccess =>
      'You do not have access to this shop\'s inventory.';

  @override
  String inventorySyncStatusScreenLength(Object length) {
    return '$length';
  }

  @override
  String get inventorySyncStatusScreenSourceLabelsComeFromThe =>
      'Source labels come from the server — they record how each stock figure last changed.';

  @override
  String get locationCaptureScreenCouldNotOpenYourPhone =>
      'Could not open your phone settings from here.';

  @override
  String get locationCaptureScreenDetectedAddressYouMayCorrect =>
      'Detected address — you may correct the text';

  @override
  String get locationCaptureScreenDifferentLocationDetected =>
      'Different location detected';

  @override
  String get locationCaptureScreenEnterYourShopAddressIn =>
      'Enter your shop address in the form.';

  @override
  String get locationCaptureScreenForBestAccuracy => 'For best accuracy:';

  @override
  String get locationCaptureScreenGPSAccuracyIsAnEstimate =>
      'GPS accuracy is an estimate, not a guarantee.';

  @override
  String get locationCaptureScreenGPSCoordinatesRemainThePrimary =>
      'GPS coordinates remain the primary location; the address is supporting information.';

  @override
  String get locationCaptureScreenTapTheMapToPlace =>
      'Tap the map to place your shop pin.';

  @override
  String get locationCaptureScreenTapTheMapToPlace2 =>
      'Tap the map to place the pin at your shop ENTRANCE.';

  @override
  String get locationCaptureScreenUseMyCurrentLocationInstead =>
      'Use my current location instead';

  @override
  String locationCaptureScreenValueAccuracyValue2AddressSummarySave(
    Object value,
    Object value2,
    Object addressSummary,
  ) {
    return '${value}Accuracy: $value2\n\n$addressSummary\n\nSave this as your shop entrance location?';
  }

  @override
  String get locationCaptureScreenYourLocationIsNotAccurate =>
      'Your location is not accurate enough. Move closer to your shop for better accuracy.';

  @override
  String locationCaptureScreenYourSelectedShopLocationIs(Object value) {
    return 'Your selected shop location is $value km away from your current GPS location.\n\nAre you sure this is your shop?';
  }

  @override
  String get loginScreenNewHereCreateAnAccount => 'New here? Create an account';

  @override
  String get loginScreenSignInWithThePhone =>
      'Sign in with the phone number or email you registered.';

  @override
  String get logoutConfirmationScreenLogOutOfPasslyBusiness =>
      'Log out of Passly Business?';

  @override
  String get logoutConfirmationScreenYouWillNeedToSign =>
      'You will need to sign in with the same Google account before you can manage your shop again.';

  @override
  String lowStockScreenCountItemValueImmediateRestocking(
    Object count,
    Object value,
  ) {
    return '$count item$value immediate restocking';
  }

  @override
  String get lowStockScreenNoRestockNeedsMatchYour =>
      'No restock needs match your search';

  @override
  String get lowStockScreenNothingIsAtOrBelow =>
      'Nothing is at or below its low-stock threshold right now.';

  @override
  String lowStockScreenQuantityUnitsLeft(Object quantity) {
    return '$quantity units left';
  }

  @override
  String lowStockScreenSKUSku(Object sku) {
    return 'SKU: $sku';
  }

  @override
  String lowStockScreenThresholdValueUnits(Object value) {
    return 'Threshold: $value units';
  }

  @override
  String get myTicketsScreenCheckYourConnectionAndTry =>
      'Check your connection and try again.';

  @override
  String get myTicketsScreenReportsYouSendFromHelp =>
      'Reports you send from Help & support are tracked here, with the status support has set on them.';

  @override
  String myTicketsScreenSupportRepliedResolutionNotes(Object resolutionNotes) {
    return 'Support replied: $resolutionNotes';
  }

  @override
  String get notificationDetailScreenDeepLinkCopiedToClipboard =>
      'Deep link copied to clipboard';

  @override
  String get notificationDetailScreenOpenANotificationFromThe =>
      'Open a notification from the Alerts tab to see its details.';

  @override
  String get notificationPreferencesScreenBannersAndSoundsAreControlled =>
      'Banners and sounds are controlled by your phone';

  @override
  String get notificationPreferencesScreenDeviceNotificationPermission =>
      'Device notification permission';

  @override
  String get notificationPreferencesScreenInAppAlertsArePart =>
      'In-app alerts are part of the app and are never switched off. The channels above only control how you are reached OUTSIDE the app.';

  @override
  String get notificationPreferencesScreenSavedForYourAccountOn =>
      'Saved for your account on this device';

  @override
  String get notificationPreferencesScreenTheAlertsTabAlwaysWorks =>
      'The Alerts tab always works';

  @override
  String get notificationSettingsScreenCouldNotOpenYourPhone =>
      'Could not open your phone settings from here.';

  @override
  String get notificationSettingsScreenIfDeviceNotificationsAreOff =>
      'If device notifications are off, every alert still appears in the Alerts tab. The permission only decides whether your phone may also show banners and play sounds.';

  @override
  String get notificationSettingsScreenInAppAlertsCannotBe =>
      'In-app alerts cannot be switched off';

  @override
  String get notificationSettingsScreenInventoryOrdersOffersAndMore =>
      'Inventory, orders, offers and more';

  @override
  String get notificationSettingsScreenLowStockPOSSyncResults =>
      'Low stock, POS sync results and account notices are part of the app so a shop is never silently out of date. The channels below decide whether you are ALSO reached outside the app.';

  @override
  String get notificationSettingsScreenNotificationsNeverBlockTheApp =>
      'Notifications never block the app';

  @override
  String get notificationSettingsScreenNotificationsOnThisDevice =>
      'Notifications on this device';

  @override
  String get notificationSettingsScreenWhatYouAreToldAbout =>
      'What you are told about, and how';

  @override
  String get notificationSettingsScreenYourPhoneWillNotAsk =>
      'Your phone will not ask again for this app. Turn banners on in Settings > Apps > Passly Business > Notifications.';

  @override
  String get notificationsScreenCheckYourConnectionAndTry =>
      'Check your connection and try again.';

  @override
  String offerCreateSheetAppliesToLengthSelected(Object length) {
    return 'Applies to ($length selected)';
  }

  @override
  String get offerCreateSheetDiscount => 'Discount % *';

  @override
  String get offerCreateSheetDiscount2 => 'Discount ₹ *';

  @override
  String get offerCreateSheetEGDiwali10Off => 'e.g. Diwali 10% off';

  @override
  String get offerCreateSheetEGValidOnIn =>
      'e.g. Valid on in-store purchases only';

  @override
  String get offerCreateSheetEndDate => 'End date *';

  @override
  String get offerCreateSheetFixedSalePriceCustomersPay =>
      'Fixed sale price customers pay';

  @override
  String get offerCreateSheetKeptOffCustomerListingsUntil =>
      'Kept off customer listings until you activate it';

  @override
  String get offerCreateSheetNoProductsInInventoryYet =>
      'No products in inventory yet — add products first.';

  @override
  String offerCreateSheetOfferCreatedForLengthProduct(Object length) {
    return 'Offer created for $length product(s)';
  }

  @override
  String get offerCreateSheetOfferTitle => 'Offer title *';

  @override
  String get offerCreateSheetOfferType => 'Offer type *';

  @override
  String get offerCreateSheetPromotionalPrice => 'Promotional price *';

  @override
  String get offerCreateSheetSelectAtLeastOneProduct =>
      'Select at least one product for the offer';

  @override
  String get offerCreateSheetStartDate => 'Start date *';

  @override
  String get offerCreateSheetTermsConditionsOptional =>
      'Terms & conditions (optional)';

  @override
  String offerCreateSheetValueQtyQuantity(Object value, Object quantity) {
    return '₹$value · qty $quantity';
  }

  @override
  String offerListScreensOfferTypeLabelDiscountLabelProductCountProductS(
    Object offerTypeLabel,
    Object discountLabel,
    Object productCount,
  ) {
    return '$offerTypeLabel · $discountLabel · $productCount product(s)';
  }

  @override
  String get offersScreenCheckYourConnectionAndTry =>
      'Check your connection and try again.';

  @override
  String get offersScreenChooseAShopToSee => 'Choose a shop to see its offers.';

  @override
  String get operatingHoursScreenIgnoreTheWeeklyScheduleBelow =>
      'Ignore the weekly schedule below entirely.';

  @override
  String get operatingHoursScreenOpen247 => 'Open 24×7';

  @override
  String get operatingHoursScreenTheWholeWeekIsSaved =>
      'The whole week is saved in one request. Holiday closures override these times.';

  @override
  String get operatingHoursScreenUpdateFailedPleaseRetry =>
      'Update failed. Please retry.';

  @override
  String get phoneOtpScreenPhoneSignInUnavailable =>
      'Phone sign-in unavailable';

  @override
  String get phoneOtpScreenThisDeviceCannotReceiveAn =>
      'This device cannot receive an SMS code. Use Google to sign in, or open the app on an Android or iOS phone.';

  @override
  String get posConnectionSetupScreenCheckTheAPIKeySecret =>
      'Check the API key / secret above and try again — nothing was synced.';

  @override
  String get posConnectionSetupScreenCheckYourConnectionAndTry =>
      'Check your connection and try again.';

  @override
  String get posConnectionSetupScreenLinkYourPOSToKeep =>
      'Link your POS to keep products and stock in step automatically.';

  @override
  String get posConnectionSetupScreenOnlyWhatYouTypeIs =>
      'Only what you type is sent — a rotation never blanks an existing secret.';

  @override
  String posConnectionSetupScreenProviderNameIsValue(
    Object providerName,
    Object value,
  ) {
    return '$providerName is $value.';
  }

  @override
  String get posConnectionSetupScreenThisConnectorSupportsFullSyncs =>
      'This connector supports full syncs only.';

  @override
  String posConnectionSetupScreenThisShopAlreadyHasA(Object value) {
    return 'This shop already has a connector ($value). Update its credentials and reconnect — no duplicate is created.';
  }

  @override
  String get posConnectionSetupScreenVendorCredentialsOptional =>
      'Vendor credentials (optional)';

  @override
  String get posErrorScreenCheckTheConnectionAgain =>
      'Check the connection again';

  @override
  String get posErrorScreenLeaveThisScreenAndReturn =>
      'Leave this screen and return to the POS hub.';

  @override
  String get posErrorScreenReReadTheConnectorAnd =>
      'Re-read the connector and its sync jobs from the server.';

  @override
  String get posErrorScreenSeeWhetherAnEarlierJob =>
      'See whether an earlier job succeeded and what failed.';

  @override
  String get posHubSheetsEveryTillScannerOrTablet =>
      'Every till, scanner or tablet mapped to this connector.';

  @override
  String get posHubSheetsNoTerminalsMappedYetAdd =>
      'No terminals mapped yet. Add the first one below.';

  @override
  String get posHubSheetsRecordsPerBatchOptional =>
      'Records per batch (optional)';

  @override
  String get posHubSheetsTerminalIdFromYourPOS =>
      'Terminal id (from your POS vendor)';

  @override
  String get posHubSheetsTheTillIsUsuallyThe =>
      'The till is usually the truth for stock levels; the platform keeps pricing, offers and MRP.';

  @override
  String get posHubSheetsWhenTheSameProductDisagrees =>
      'When the same product disagrees';

  @override
  String get posScreenCheckYourConnectionAndTry =>
      'Check your connection and try again.';

  @override
  String get posScreenChooseAShopToManage =>
      'Choose a shop to manage its POS integration.';

  @override
  String get posScreenConnectYourBillingCounter =>
      'Connect your billing counter';

  @override
  String get posScreenLinkYourPOSToKeep =>
      'Link your POS to keep products and stock in step automatically.';

  @override
  String get posScreenNoSyncsYetTapSync =>
      'No syncs yet.\nTap \"Sync now\" to pull your POS data.';

  @override
  String get posScreenPOSIntegrationIsNotConfigured =>
      'POS integration is not configured for your account.';

  @override
  String get posScreenPOSNotAvailableOnYour => 'POS not available on your plan';

  @override
  String get posScreenScheduledSyncsWillStopYou =>
      'Scheduled syncs will stop. You can reconnect at any time.';

  @override
  String get posScreenUpgradeYourPlanToConnect =>
      'Upgrade your plan to connect a point of sale. Your current plan does not include POS integrations.';

  @override
  String get posSharedCheckYourConnectionAndTry =>
      'Check your connection and try again.';

  @override
  String get posSyncHistoryScreenConnectAPOSAndRun =>
      'Connect a POS and run a sync to build a history.';

  @override
  String get posSyncHistoryScreenNothingMatchesThisFilter =>
      'Nothing matches this filter';

  @override
  String get posSyncHistoryScreenRunASyncAndEvery =>
      'Run a sync and every job — queued, done or failed — shows up here.';

  @override
  String posSyncHistoryScreenSyncJobId(Object id) {
    return 'Sync job #$id';
  }

  @override
  String get posSyncHistoryScreenTryAnotherStatusOrClear =>
      'Try another status, or clear the filter.';

  @override
  String posSyncHistoryScreenValueValue2Value3(
    Object value,
    Object value2,
    Object value3,
  ) {
    return '$value · $value2$value3';
  }

  @override
  String get posSyncProgressScreenNothingIsCountedHereThe =>
      'Nothing is counted here — the numbers below come from the POS connector.';

  @override
  String get posSyncProgressScreenStartingSync => 'Starting sync…';

  @override
  String get posSyncProgressScreenSyncingYourProducts =>
      'Syncing your products…';

  @override
  String get posSyncProgressScreenTheJobIsStillOn =>
      'The job is still on the server — check the sync history before starting another one.';

  @override
  String posSyncProgressScreenValue(Object value) {
    return '$value';
  }

  @override
  String posSyncResultScreenValue(Object value) {
    return '$value';
  }

  @override
  String get posSyncScreenConnectAPOSFirstThere =>
      'Connect a POS first — there is nothing to sync from.';

  @override
  String get posSyncScreenOnlyWhatChangedSinceThe =>
      'Only what changed since the last sync — faster, but it can miss manual edits.';

  @override
  String get posSyncScreenReReadTheWholePOS =>
      'Re-read the whole POS catalog and reconcile every product.';

  @override
  String get priceHistoryScreenEveryPriceUpdateForThis =>
      'Every price update for this product will be recorded here.';

  @override
  String get priceListScreenSearchNameBrandOrSKU => 'Search name, brand or SKU';

  @override
  String get pricingSharedAddProductsOrImportThem =>
      'Add products or import them from Excel first.';

  @override
  String pricingSharedCurrentPriceValueValue2(Object value, Object value2) {
    return 'Current price ₹$value$value2';
  }

  @override
  String get privacyScreenBusinessDataIsKeptWhile =>
      'Business data is kept while your shop is active. When an account is closed, operational data is removed or anonymised except where a record must be kept for accounting or legal reasons.';

  @override
  String get privacyScreenDecideWhichAlertsYouReceive =>
      'Decide which alerts you receive in Notification preferences, keep your catalogue accurate from the Products and Inventory screens, and contact support to correct your account details or ask for your data to be deleted.';

  @override
  String get privacyScreenOnlyYourPublicBusinessInformation =>
      'Only your public business information: shop name, category, address, hours, contact details and the products you publish. Stock quantities, costs, documents and your personal contact details stay private.';

  @override
  String get privacyScreenPaymentAndBillingProvidersWhen =>
      'Payment and billing providers when you subscribe to a paid plan, providers you connect yourself (for example your POS vendor), and authorities when legally required. Nothing else is shared.';

  @override
  String get privacyScreenQuestionsAboutYourData =>
      'Questions about your data?';

  @override
  String get privacyScreenSessionsUseShortLivedAccess =>
      'Sessions use short-lived access tokens that are revocable from the server, and tokens are stored in the device keychain or keystore. Logging out revokes the session and erases the stored tokens from this device.';

  @override
  String get privacyScreenToShowYourShopProducts =>
      'To show your shop, products and prices to nearby customers, to sync your stock and prices, to send you operational alerts (low stock, POS sync results, verification), and to keep your account secure. Analytics are aggregated — we never sell your data.';

  @override
  String privacyScreenWriteToEmailAndThe(Object email, Object hours) {
    return 'Write to $email and the team will respond during $hours.';
  }

  @override
  String get privacyScreenYourAccountIdentityNamePhone =>
      'Your account identity (name, phone number and e-mail from your Google sign-in), your business details (shop name, category, address, operating hours and licence documents), your catalogue (products, stock levels and prices) and the notifications you receive. Shop location is captured only when you place or update your shop on the map.';

  @override
  String get privacyScreenYourDataInPasslyBusiness =>
      'Your data in Passly Business';

  @override
  String get productSheetsChooseHowYouWantTo =>
      'Choose how you want to add products:';

  @override
  String productSheetsEditName(Object name) {
    return 'Edit $name';
  }

  @override
  String get productSheetsFullDetailsPriceStockBrand =>
      'Full details: price, stock, brand, photo…';

  @override
  String get productSheetsJPGPNGWebPUpTo =>
      'JPG / PNG / WebP up to 5 MB, stored securely — the shop listing shows a link to it.';

  @override
  String get productSheetsMatchAgainstTheSharedCatalog =>
      'Match against the shared catalog';

  @override
  String get productSheetsProductName => 'Product name *';

  @override
  String get productSheetsSellingPrice => 'Selling price *';

  @override
  String get productSheetsTypeOrPasteTheCode =>
      'Type or paste the code on the pack';

  @override
  String get productSheetsUnavailableProductsAreHiddenFrom =>
      'Unavailable products are hidden from customers';

  @override
  String get productSheetsUnpublishedProductsStayAsDrafts =>
      'Unpublished products stay as drafts';

  @override
  String get productSheetsUploadASpreadsheetOfProducts =>
      'Upload a spreadsheet of products';

  @override
  String productsScreenByUpdatedBy(Object updatedBy) {
    return 'by $updatedBy';
  }

  @override
  String productsScreenMatchedOfTotalProducts(Object matched, Object total) {
    return '$matched of $total products';
  }

  @override
  String get productsScreenPleaseCheckYourConnectionAnd =>
      'Please check your connection and retry.';

  @override
  String productsScreenRsValue(Object value) {
    return 'Rs $value';
  }

  @override
  String get productsScreenSearchNameBrandOrSKU => 'Search name, brand or SKU…';

  @override
  String productsScreenUpdatedValue(Object value) {
    return 'Updated $value';
  }

  @override
  String get productsScreenYouDoNotHaveAccess =>
      'You do not have access to this shop.';

  @override
  String get registerScreenAlreadyHaveAnAccountSign =>
      'Already have an account? Sign in';

  @override
  String get registerScreenCompleteSignInInThe =>
      'Complete sign-in in the opened Google window…';

  @override
  String get registerScreenCreateYourAccountWithYour =>
      'Create your account with your phone number and a password.';

  @override
  String get registerScreenPhoneNumberAlreadyRegisteredPlease =>
      'Phone number already registered. Please login instead.';

  @override
  String get registerScreenTellUsAboutYourBusiness =>
      'Tell us about your business';

  @override
  String get registrationWidgetsTakeAPhotoWithYour =>
      'Take a photo with your camera';

  @override
  String get registrationWidgetsText => '*';

  @override
  String registrationWidgetsUploadingValue(Object value) {
    return 'Uploading $value…';
  }

  @override
  String registrationWidgetsValue(Object value) {
    return '$value';
  }

  @override
  String registrationWidgetsValueReadyToUpload(Object value) {
    return '$value · ready to upload';
  }

  @override
  String registrationWidgetsValueValue2(Object value, Object value2) {
    return '$value · $value2';
  }

  @override
  String get reportIssueScreen1OpenProducts2Tap =>
      '1. Open Products\n2. Tap a product';

  @override
  String get reportIssueScreenAPictureOfTheScreen =>
      'A picture of the screen helps support reproduce the problem. One image, compressed to WebP under 2 MB before it is sent.';

  @override
  String get reportIssueScreenAPreciseReportIsUsually =>
      'A precise report is usually fixed in one release';

  @override
  String get reportIssueScreenAPriceSavedAsThe =>
      'A price saved as the old value after I tapped Save';

  @override
  String get reportIssueScreenEveryReportBecomesATracked =>
      'Every report becomes a tracked ticket';

  @override
  String reportIssueScreenFilenameValue(Object filename, Object value) {
    return '$filename - $value';
  }

  @override
  String get reportIssueScreenHowMuchDoesItBlock =>
      'How much does it block you?';

  @override
  String reportIssueScreenReportCopiedPasteItInto(Object email) {
    return 'Report copied - paste it into an e-mail to $email';
  }

  @override
  String get reportIssueScreenSendingFilesASupportTicket =>
      'Sending files a support ticket with the category, severity, your shop and the app version attached. Support works through the same queue, and the status stays visible under My support tickets.';

  @override
  String get reportIssueScreenStepsToReproduceOptional =>
      'Steps to reproduce (optional)';

  @override
  String get reportIssueScreenSupportHasItInThe =>
      'Support has it in the queue. Quote the ticket number below if you contact us about it.';

  @override
  String get resetPasswordScreenPasswordResetSuccessfully =>
      'Password reset successfully!';

  @override
  String get resetPasswordScreenYourNewPasswordMustBe =>
      'Your new password must be at least 8 characters and include letters and numbers.';

  @override
  String get securityScreenEndsTheSessionAndErases =>
      'Ends the session and erases the saved tokens';

  @override
  String get securityScreenGoogleAccountVerifiedByFirebase =>
      'Google account, verified by Firebase';

  @override
  String get securityScreenHowYouSignInAnd =>
      'How you sign in and where you are signed in';

  @override
  String get securityScreenPasswordSignInIsNot =>
      'Password sign-in is not enabled';

  @override
  String get securityScreenReportSuspiciousActivity =>
      'Report suspicious activity';

  @override
  String get securityScreenSignInAndAccountNotices =>
      'Sign-in and account notices';

  @override
  String get securityScreenYourIdentityIsVerifiedBy =>
      'Your identity is verified by Google every time you sign in, so there is no Passly password to change or reset. To move your account to a different Google address, contact support.';

  @override
  String get sessionsScreenCheckYourConnectionAndTry =>
      'Check your connection and try again.';

  @override
  String get sessionsScreenDevicesWithAnActivePassly =>
      'Devices with an active Passly Business session';

  @override
  String sessionsScreenIPIp(Object ip) {
    return 'IP $ip';
  }

  @override
  String sessionsScreenLabelWillNeedToSign(Object label) {
    return '$label will need to sign in again. This device stays signed in.';
  }

  @override
  String get sessionsScreenNoDeviceSessionsRecorded =>
      'No device sessions recorded';

  @override
  String get sessionsScreenOnlyThisDeviceIsSigned =>
      'Only this device is signed in right now.';

  @override
  String get sessionsScreenSigningADeviceOutTakes =>
      'Signing a device out takes effect immediately';

  @override
  String get sessionsScreenTheDeviceIsReturnedTo =>
      'The device is returned to the sign-in screen the next time it reaches Passly. To end THIS session, use Log out in Settings — that also erases the saved tokens on this phone.';

  @override
  String get sessionsScreenThisAccountSignsInWith =>
      'This account signs in with Google, so the session is managed by Google rather than stored as a Passly device session. Logging out from Settings still ends it on this device.';

  @override
  String get shopLocationDetailsGPSAccuracyIsAnEstimate =>
      'GPS accuracy is an estimate, not a guarantee. Tap the map, drag the pin, or correct coordinates below. Check your shop entrance and address before confirming.';

  @override
  String shopLocationDetailsOriginalGPSEstimateValue(Object value) {
    return 'Original GPS estimate — $value';
  }

  @override
  String shopLocationDetailsThisPinIsAboutValue(Object value) {
    return 'This pin is about $value m away from your GPS location. Are you sure this is your shop entrance?';
  }

  @override
  String get shopLocationDetailsYesThisIsMyShop =>
      'Yes, this is my shop entrance';

  @override
  String get shopLocationScreenCouldNotOpenYourPhone =>
      'Could not open your phone settings from here.';

  @override
  String get shopLocationScreenCustomersSeeYourShopOn =>
      'Customers see your shop on the map at this pin. Keep it on your shop entrance, not the street corner.';

  @override
  String get shopLocationScreenTheAppReadsYourDevice =>
      'The app reads your device GPS a few times, keeps the most accurate fix and asks the server to replace the stored pin. Every change is audited.';

  @override
  String get shopLocationScreenWithoutAPinCustomersCannot =>
      'Without a pin customers cannot find your shop on the map. Stand at or near the shop and save your current location.';

  @override
  String shopProfileScreenValueValue2CategoryLabel(
    Object value,
    Object value2,
    Object categoryLabel,
  ) {
    return '$value · $value2 · $categoryLabel';
  }

  @override
  String get shopProfileSharedManagersHaveReadOnlyAccess =>
      'Managers have read-only access here. Ask the shop owner for changes.';

  @override
  String get shopRegistrationWizardAddYourShopLocationFor =>
      'Add your shop location for better visibility and verification.';

  @override
  String get shopRegistrationWizardAlreadyHaveAnAccountLogin =>
      'Already have an account? Login';

  @override
  String get shopRegistrationWizardDiscoverabilityByNearbyCustomers =>
      'Discoverability by nearby customers';

  @override
  String get shopRegistrationWizardDocumentsAndAdditionalInfo =>
      'Documents and Additional Info';

  @override
  String get shopRegistrationWizardEGSharmaMedicalStore =>
      'e.g. Sharma Medical Store';

  @override
  String get shopRegistrationWizardGettingLocation => 'Getting location…';

  @override
  String get shopRegistrationWizardHandleProductsOrdersInventoryAnd =>
      'Handle products, orders/inventory and business information';

  @override
  String get shopRegistrationWizardHttps => 'https://';

  @override
  String get shopRegistrationWizardInstagramFacebookLink =>
      'Instagram / Facebook link';

  @override
  String get shopRegistrationWizardJoinOurPlatformAndBring =>
      'Join our platform and bring your business closer to local customers.';

  @override
  String get shopRegistrationWizardNear => 'Near…';

  @override
  String get shopRegistrationWizardNoGPSFixTapThe =>
      'No GPS fix — tap the map above to place your shop entrance pin, or type the coordinates below.';

  @override
  String get shopRegistrationWizardTapTheMapToPlace =>
      'Tap the map to place your shop pin.';

  @override
  String get shopRegistrationWizardTellCustomersAboutYourShop =>
      'Tell customers about your shop …';

  @override
  String get shopRegistrationWizardTellUsAboutYourShop =>
      'Tell us about your shop or business.';

  @override
  String get shopRegistrationWizardTypeYourAddressBelowThen =>
      'Type your address below, then tap the map to place your shop pin.';

  @override
  String get shopRegistrationWizardUdyamMSMENumberOptional =>
      'Udyam / MSME Number (optional)';

  @override
  String get shopRegistrationWizardUploadRequiredDocumentsForVerification =>
      'Upload required documents for verification.';

  @override
  String get shopRegistrationWizardVerifiedBusinessesCreateASafer =>
      'Verified businesses create a safer marketplace';

  @override
  String get shopRegistrationWizardYouWillGetANotification =>
      'You will get a notification once your shop is verified.';

  @override
  String get shopRegistrationWizardYourShopRegistrationHasBeen =>
      'Your shop registration has been successfully submitted. Our team will review the details and verify your documents.';

  @override
  String get shopSettingsScreenCouldNotSavePleaseRetry =>
      'Could not save. Please retry.';

  @override
  String get shopSettingsScreenCustomersCanPlaceNewOrders =>
      'Customers can place new orders while on';

  @override
  String get shopSettingsScreenManagersCannotChangeShopSettings =>
      'Managers cannot change shop settings.';

  @override
  String get shopSettingsScreenOpen247 => 'Open 24×7';

  @override
  String get shopsScreenNoShopsYetRegisterYour =>
      'No shops yet.\nRegister your first business to get started.';

  @override
  String get splashScreenCouldNotCompleteStartup =>
      'Could not complete startup';

  @override
  String get splashScreenCouldNotCompleteStartupCheck =>
      'Could not complete startup. Check your connection and retry.';

  @override
  String get stockHistoryScreenStockMovementsAdjustmentsAndPrice =>
      'Stock movements, adjustments and price changes will appear here.';

  @override
  String stockSheetsCurrentStockCurrent(Object _current) {
    return 'Current stock: $_current';
  }

  @override
  String stockSheetsHistoryName(Object name) {
    return 'History — $name';
  }

  @override
  String stockSheetsLastUpdatedValueValue2Value3(
    Object value,
    Object value2,
    Object value3,
  ) {
    return 'Last updated $value$value2 · $value3';
  }

  @override
  String get stockSheetsStockMovementsAdjustmentsAndPrice =>
      'Stock movements, adjustments and price changes (newest first)';

  @override
  String stockSheetsValueStockDelta(Object value, Object stockDelta) {
    return '$value$stockDelta';
  }

  @override
  String stockSheetsValueValue2ActorLabel(
    Object value,
    Object value2,
    Object actorLabel,
  ) {
    return '$value$value2 · $actorLabel';
  }

  @override
  String supportFaqScreenLengthOfLength2Articles(
    Object length,
    Object length2,
  ) {
    return '$length of $length2 articles';
  }

  @override
  String get supportFaqScreenStillNeedHelpContactSupport =>
      'Still need help? Contact support';

  @override
  String get supportFaqScreenTryAnotherWordOrSend =>
      'Try another word, or send your question to support.';

  @override
  String get supportScreenFrequentlyAskedQuestions =>
      'Frequently asked questions';

  @override
  String supportScreenWriteToEmailOrCall(
    Object email,
    Object phone,
    Object hours,
  ) {
    return 'Write to $email or call $phone. Support hours: $hours.';
  }

  @override
  String get termsScreenAnAccountThatBreaksThese =>
      'An account that breaks these terms, or that is involved in fraud, can be suspended or closed. If that happens you will see the reason the next time you open the app.';

  @override
  String termsScreenContactEmailForAnyQuestion(Object email) {
    return 'Contact $email for any question about these terms.';
  }

  @override
  String get termsScreenDoNotUploadUnlawfulProducts =>
      'Do not upload unlawful products, attempt to access another shop\'s data, scrape the platform, or use the app to send spam. Barcode, import and POS tools are provided so you can manage your own catalogue.';

  @override
  String get termsScreenPaidPlansAreBilledThrough =>
      'Paid plans are billed through the provider shown at checkout, renew until cancelled, and are refundable only where the law or the plan terms allow. Cancelling stops future renewals.';

  @override
  String get termsScreenShopNameAddressCategoryHours =>
      'Shop name, address, category, hours and verification documents must be truthful. Shops with misleading details, or documents that do not belong to the business, can be suspended.';

  @override
  String get termsScreenTheAppIsForOwners =>
      'The app is for owners and managers of registered shops. You may use it only for the shop you are authorised to manage, and you are responsible for keeping your sign-in device secure.';

  @override
  String get termsScreenTheseTermsMayBeUpdated =>
      'These terms may be updated as the app gains features. Continuing to use the app after an update means you accept the current version.';

  @override
  String get termsScreenWeWorkToKeepThe =>
      'We work to keep the app and the sync services available, but there will be maintenance windows and outages. Offline work is not lost — changes are sent when the connection returns.';

  @override
  String get termsScreenYouOwnTheProductsPrices =>
      'You own the products, prices, stock figures and images you publish. Customers rely on them, so keep them accurate and up to date, and make sure you have the right to sell the products you list.';

  @override
  String ticketDetailScreenReferenceCopied(Object reference) {
    return '$reference copied';
  }

  @override
  String ticketDetailScreenShopShopName(Object shopName) {
    return 'Shop: $shopName';
  }

  @override
  String get ticketDetailScreenSomethingElseContactSupport =>
      'Something else? Contact support';

  @override
  String get ticketDetailScreenTicketsArePrivateToThe =>
      'Tickets are private to the account that filed them.';

  @override
  String updatePriceScreenCurrentValueValue2(Object value, Object value2) {
    return 'Current: $value$value2';
  }

  @override
  String get updatePriceScreenMRPOptional => 'MRP (₹, optional)';

  @override
  String updatePriceScreenPriceUpdatedNowValueValue2(
    Object value,
    Object value2,
  ) {
    return 'Price updated — now ₹$value$value2';
  }

  @override
  String get updatePriceScreenSellingPrice => 'Selling price (₹)';

  @override
  String updateStockScreenCurrentQuantityUnits(Object quantity) {
    return 'Current: $quantity units';
  }

  @override
  String get updateStockScreenEG24ToAdd => 'e.g. 24 to add stock, -3 to remove';

  @override
  String get updateStockScreenEGSupplierDelivery123 =>
      'e.g. supplier delivery #123';

  @override
  String updateStockScreenStockUpdatedPreviousQuantityNewQuantityUnits(
    Object previousQuantity,
    Object newQuantity,
    Object label,
  ) {
    return 'Stock updated: $previousQuantity → $newQuantity units ($label)';
  }

  @override
  String get welcomeScreenByContinuingYouAgreeTo =>
      'By continuing, you agree to our Terms & Privacy Policy.';

  @override
  String get welcomeScreenLoginFailedPleaseTryAgain =>
      'Login failed. Please try again.';

  @override
  String get welcomeScreenManageYourShopProductsAnd =>
      'Manage your shop, products and inventory.';

  @override
  String get commonCheckTheDetails => 'Check the details';

  @override
  String get commonNetworkProblem => 'Network problem';

  @override
  String get commonNoInternetConnection => 'No internet connection';

  @override
  String get commonNotFound => 'Not found';

  @override
  String get commonNothingHereYet => 'Nothing here yet';

  @override
  String get commonServerError => 'Server error';

  @override
  String get commonSessionExpired => 'Session expired';

  @override
  String get commonSignInRequired => 'Sign-in required';

  @override
  String get commonSomethingWentWrong3 => 'Something went wrong';

  @override
  String get commonThatChangeConflicts => 'That change conflicts';

  @override
  String get commonTheServerTookTooLong => 'The server took too long';

  @override
  String get commonUnderMaintenance => 'Under maintenance';

  @override
  String get systemStateCheckYourMobileDataOr =>
      'Check your mobile data or Wi-Fi, then try again. Nothing you did was lost.';

  @override
  String get systemStateForYourSecurityYouWere =>
      'For your security you were signed out. Please sign in again to continue where you left off.';

  @override
  String get systemStateSomeOfTheInformationIs =>
      'Some of the information is not valid. Please review it and try again.';

  @override
  String get systemStateSomethingWasAlreadyUpdatedRefresh =>
      'Something was already updated. Refresh the list and try again.';

  @override
  String get systemStateSomethingWentWrongOnOur =>
      'Something went wrong on our side. Please try again shortly.';

  @override
  String get systemStateTheActionCouldNotBe =>
      'The action could not be completed. Please try again.';

  @override
  String get systemStateTheRequestTimedOutBefore =>
      'The request timed out before the server answered. Please try again.';

  @override
  String get systemStateThereIsNothingToShow =>
      'There is nothing to show right now.';

  @override
  String get systemStateWeAreDoingAShort =>
      'We are doing a short maintenance. Your data is safe — please try again in a few minutes.';

  @override
  String get systemStateWeCouldNotFindThat =>
      'We could not find that. It may have been removed.';

  @override
  String get systemStateWeCouldNotReachThe =>
      'We could not reach the server. Check your connection and try again.';

  @override
  String get systemStateYouAreNotSignedIn =>
      'You are not signed in for this action. Please sign in again.';

  @override
  String get systemStateYourAccountIsNotAllowed =>
      'Your account is not allowed to do this here. Ask the shop owner, or switch to a shop you manage.';
}
