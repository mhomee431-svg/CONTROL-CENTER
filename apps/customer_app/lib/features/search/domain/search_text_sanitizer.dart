import 'package:flutter/services.dart';

/// Keeps a search query free of characters that cannot survive a URL.
///
/// WHY NOT THE OBVIOUS REGEX
/// -------------------------
/// A previous filter allowed only `[a-zA-Z0-9\s\-_.]`, which silently
/// deletes every character outside that set. That looked harmless until the
/// first customer searched for "L'OrÃ©al" and got "LOrÃ©al", and it hard-blocks
/// any voice search: a recognised phrase containing an apostrophe, an accent or
/// a non-Latin script would be mangled before the customer ever saw it.
///
/// The rule here is "no control characters", which is the actual requirement --
/// a newline or tab pasted into a single-line field breaks the query parameter
/// on the results URL. Everything a person might legitimately type or say is
/// left exactly as they entered it.
///
/// Lives in `domain/` rather than beside the field because it is a pure text
/// rule with no Flutter-widget dependency, which is what makes it directly
/// unit-testable.
class SearchTextSanitizer {
  const SearchTextSanitizer._();

  /// Matches the control characters that must never reach the query string.
  static final RegExp _control = RegExp(r'[\x00-\x1F\x7F]');

  /// Strips control characters from [input].
  static String sanitize(String input) => input.replaceAll(_control, '');

  /// The formatter applied by the search field.
  ///
  /// A formatter, not a filter, because filtering *rejects* a keystroke the
  /// caret then cannot see; this normalises the whole value, so a pasted string
  /// with a stray newline is cleaned up rather than silently refused.
  static final TextInputFormatter formatter = TextInputFormatter.withFunction((
    oldValue,
    newValue,
  ) {
    final cleaned = sanitize(newValue.text);
    if (cleaned == newValue.text) return newValue;
    return newValue.copyWith(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  });
}
