class InputValidator {
  static final RegExp _emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
  static final RegExp _phoneRegExp = RegExp(r'^\+?[0-9]{10,12}$');

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email address is required.';
    if (!_emailRegExp.hasMatch(value.trim())) return 'Please enter a valid email address.';
    return null;
  }

  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Phone number is required.';
    final clean = value.replaceAll(RegExp(r'[\s\-]'), '');
    if (!_phoneRegExp.hasMatch(clean)) return 'Please enter a valid 10-digit phone number.';
    return null;
  }

  static String? validateSearchQuery(String? value) {
    if (value == null) return null;
    // Strip control characters & dangerous XSS script vectors
    final sanitized = value.replaceAll(RegExp(r'[<>]'), '');
    if (sanitized.length > 100) return 'Search query is too long.';
    return null;
  }

  static String sanitizeQuery(String input) {
    return input.replaceAll(RegExp(r'[<>]'), '').trim();
  }
}