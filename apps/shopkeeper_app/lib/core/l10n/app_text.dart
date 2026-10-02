import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_en.dart';

/// The single entry point for turning a user-visible string INTO a widget.
///
/// Why this exists: `AppLocalizations.of(context)` is generated non-nullable
/// (`nullable-getter: false` in l10n.yaml) because every screen in the shipped
/// app sits under `MaterialApp`, which registers the delegate. But the same
/// widgets are rendered by ~40 test harnesses — and by isolated widget
/// previews — that build a bare `MaterialApp` without the delegate, where
/// `of(context)` throws.
///
/// [appText] resolves through the real delegate when there is one, and falls
/// back to the *generated* English implementation when there is not. The
/// fallback is `AppLocalizationsEn`, i.e. the compiled contents of
/// `app_en.arb` — never a hand-copied literal — so there is exactly one source
/// of truth for wording and the fallback cannot drift from the catalog.
///
/// Business logic never calls this. It returns message CODES
/// (see `core/errors/app_message_code.dart`) or structured descriptors
/// (see `core/l10n/relative_time.dart`); only the widget layer resolves them
/// here.
AppLocalizations appText(BuildContext context) =>
    Localizations.of<AppLocalizations>(context, AppLocalizations) ??
    AppLocalizationsEn();

/// The generated English catalog, for the layers that must hand back a plain
/// `String` with no `BuildContext` (transport copy, controller mappers).
/// Byte-identical to the fallback [appText] uses.
AppLocalizations appTextStatic() => AppLocalizationsEn();

/// The locale the surrounding `Localizations` scope resolved, for date and
/// number formatting. Falls back to English outside a real app tree.
Locale appTextLocale(BuildContext context) =>
    Localizations.maybeLocaleOf(context) ?? const Locale('en');
