import 'package:flutter/widgets.dart';

import '../l10n/app_text.dart';

/// The app-wide failure vocabulary, as CODES rather than sentences.
///
/// Business logic (repositories, controllers) must not carry user-visible
/// English: it says WHICH thing went wrong, and the wording lives in
/// `lib/l10n/app_en.arb` like every other string in the app. Throwing
/// `ApiException(message: 'Not signed in')` from 37 different files meant 37
/// copies of one sentence that no translator could ever reach.
enum AppMessageCode {
  /// No access token on this device — the session was cleared elsewhere.
  notSignedIn('msgNotSignedIn'),

  /// A shop-scoped call was attempted with no shop selected.
  noShopSelected('msgNoShopSelected'),

  /// The backend rejected the session (HTTP 401).
  sessionExpired('msgSessionExpired'),

  /// The request never reached the backend (HTTP status absent).
  noInternet('msgNoInternet');

  const AppMessageCode(this.l10nKey);

  /// The `app_en.arb` key holding the shopkeeper-facing wording.
  final String l10nKey;
}

/// Localized copy for [code], resolved through the active locale.
String appMessageText(BuildContext context, AppMessageCode code) {
  final text = appText(context);
  return switch (code) {
    AppMessageCode.notSignedIn => text.msgNotSignedIn,
    AppMessageCode.noShopSelected => text.msgNoShopSelected,
    AppMessageCode.sessionExpired => text.msgSessionExpired,
    AppMessageCode.noInternet => text.msgNoInternet,
  };
}

/// English copy for [code], straight from the generated `app_en.arb` output.
///
/// For the few call sites that must hand back a plain `String` without a
/// `BuildContext` (the `_friendly` mappers in controllers). These read the
/// generated catalog rather than restating it, so the wording has one home.
String appMessageEnglish(AppMessageCode code) {
  final text = appTextStatic();
  return switch (code) {
    AppMessageCode.notSignedIn => text.msgNotSignedIn,
    AppMessageCode.noShopSelected => text.msgNoShopSelected,
    AppMessageCode.sessionExpired => text.msgSessionExpired,
    AppMessageCode.noInternet => text.msgNoInternet,
  };
}

/// The generic failure shared by every feature, or `null` when the status
/// carries a feature-specific meaning the caller should word itself.
///
/// Session loss outranks connectivity: a 401 means "sign in again" even if the
/// link also looks down.
AppMessageCode? sessionFailureCode({
  required bool isUnauthorized,
  required int? statusCode,
}) {
  if (isUnauthorized || statusCode == 401) return AppMessageCode.sessionExpired;
  if (statusCode == null) return AppMessageCode.noInternet;
  return null;
}
