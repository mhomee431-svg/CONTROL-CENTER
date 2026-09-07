/// Localized Strings Abstraction (Supports English, Architecture ready for Hindi 'hi')
class AppStrings {
  final String languageCode;

  const AppStrings(this.languageCode);

  static const _en = {
    'settingsTitle': 'Settings',
    'language': 'Language',
    'theme': 'Theme',
    'pushNotifications': 'Push Notifications',
    'locationServices': 'Location Services',
    'privacy': 'Privacy',
    'helpSupport': 'Help & Support',
    'about': 'About App',
  };

  static const _hi = {
    'settingsTitle': 'सेटिंग्स',
    'language': 'भाषा',
    'theme': 'थीम',
    'pushNotifications': 'पुश सूचनाएं',
    'locationServices': 'स्थान सेवाएं',
    'privacy': 'गोपनीयता',
    'helpSupport': 'सहायता एवं सहायता',
    'about': 'ऐप के बारे में',
  };

  String get(String key) {
    if (languageCode == 'hi') return _hi[key] ?? _en[key] ?? key;
    return _en[key] ?? key;
  }
}