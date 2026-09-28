/// What a View is allowed to depend on, in one list.
///
/// The View rule says: layout, simple display decisions, animation, basic
/// routing. It does NOT say: database logic, backend verification, large
/// business logic, complex API transformations.
///
/// This is a compile-time-ish boundary rather than a comment, so a violation
/// shows up as a missing import instead of being discovered in review.
///
/// ## Why a view must not touch `data/`
///
/// A view that decodes JSON has no single owner for the decode rules. Two views
/// then disagree about what a missing field means, and the disagreement is only
/// visible on the screen that happens to hit the malformed record. Moving the
/// decode behind a ViewModel means the rule is written once.
abstract final class ViewBoundary {
  /// Layers a view may import.
  ///
  /// A view needs its own feature's `domain/models` (to type its fields) and
  /// `core/view` (for the state types). It must not reach into `data/`.
  static const Set<String> allowedViewImports = {
    'domain/models',
    'domain/', // repository-free domain types
    'core/view/',
    'core/widgets/',
    'core/theme/',
    'core/router/',
    'core/i18n/',
  };

  /// Human-readable rule, printed by the architecture check so a failure
  /// explains itself instead of just naming a file.
  static const String rule = '''
VIEW RULE
  Views may contain: layout, simple display decisions, animation, basic routing.
  Views may NOT contain: database logic, backend verification logic,
                         large business logic, complex API transformations.
  Data access belongs in a ViewModel.''';
}

/// What a ViewModel is allowed to own, restated from the project rule so a
/// reviewer has the checklist next to the code.
abstract final class ViewModelBoundary {
  /// A ViewModel manages all of these.
  static const Set<String> owned = {
    'UI state',
    'commands',
    'loading',
    'error',
    'filter state',
    'search state',
    'pagination state',
    'mutation state',
  };

  /// A ViewModel never does these. [ViewModel] imports `foundation` rather than
  /// `widgets` so that importing material.dart is itself a signal.
  static const Set<String> forbidden = {
    'rendering anything',
    'holding a BuildContext',
    'calling setState',
    'importing package:flutter/material.dart',
  };

  static const String rule = '''
VIEWMODEL RULE
  ViewModels manage: UI state, commands, loading, error, filter state,
                     search state, pagination state, mutation state.
  Avoid conflicting boolean states. Prefer explicit state models.''';
}
