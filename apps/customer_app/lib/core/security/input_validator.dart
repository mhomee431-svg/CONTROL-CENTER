import '../validation/validators.dart';

/// Legacy facade kept so existing call sites keep compiling.
///
/// It is a THIN DELEGATE, not a second source of truth. The rules below used to
/// live here and disagreed with the screens that bypassed this class:
///   - `validatePhone` accepted `^[+?]?[0-9]{10,12}$`, so `1234567890` passed
///     here but was rejected by `login_screen`'s `^[6-9]\d{9}$`.
///   - `validateEmail` capped the TLD at `{2,4}`, rejecting `.museum`.
///
/// New code should call `PhoneValidator` / `EmailValidator` / `SearchValidator`
/// directly. This class is a migration seam, not a place to add rules.
class InputValidator {
  static String? validateEmail(String? value) => EmailValidator.validate(value);

  static String? validatePhone(String? value) => PhoneValidator.validate(value);

  static String? validateSearchQuery(String? value) =>
      SearchValidator.validate(value);

  static String sanitizeQuery(String input) => SearchValidator.sanitize(input);
}
