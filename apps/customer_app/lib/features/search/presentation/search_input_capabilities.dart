import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Optional input modes the search bar can offer, beyond plain typing.
///
/// This is a *vocabulary*, not a feature. [voice] exists so the bar has a named
/// place to hang a voice affordance, and so a kill-switch can hide it, but
/// nothing in this file or anywhere else in the app speaks to a microphone.
/// Adding speech recognition is a separate, explicitly-scoped piece of work.
enum SearchInputCapability { text, voice }

/// Build-time switches for optional search-bar capabilities.
///
/// WHY A COMPILE-TIME FLAG
/// -----------------------
/// A voice affordance that is wired to an unimplemented handler is worse than
/// no affordance: a customer taps it, nothing happens, and the whole bar starts
/// feeling broken. Gating on a `--dart-define` that defaults to `false` means
/// the affordance is genuinely absent from every build until somebody
/// deliberately turns it on *and* supplies an implementation -- so the two
/// changes cannot get out of step and ship a dead button.
class SearchInputFeatureFlags {
  const SearchInputFeatureFlags._();

  /// `--dart-define=VOICE_SEARCH_ENABLED=true`
  ///
  /// Off by default. Turning this on only reveals the affordance; it does not
  /// by itself provide recognition, which is why [searchInputExtensionProvider]
  /// must be overridden in the same change.
  static const bool voiceSearchEnabled = bool.fromEnvironment(
    'VOICE_SEARCH_ENABLED',
    defaultValue: false,
  );
}

/// Which capabilities this build exposes.
class SearchInputCapabilities {
  final Set<SearchInputCapability> enabled;

  const SearchInputCapabilities(this.enabled);

  /// The default set: typing only.
  ///
  /// Always includes [SearchInputCapability.text] -- the bar is a text field
  /// first, and a build that disabled typing would have no search at all.
  const SearchInputCapabilities.textOnly()
    : enabled = const {SearchInputCapability.text};

  bool has(SearchInputCapability capability) => enabled.contains(capability);

  @override
  bool operator ==(Object other) =>
      other is SearchInputCapabilities &&
      other.enabled.length == enabled.length &&
      other.enabled.containsAll(enabled);

  @override
  int get hashCode => Object.hashAllUnordered(enabled);
}

final searchInputCapabilitiesProvider = Provider<SearchInputCapabilities>((
  ref,
) {
  return const SearchInputCapabilities(
    SearchInputFeatureFlags.voiceSearchEnabled
        ? {SearchInputCapability.text, SearchInputCapability.voice}
        : {SearchInputCapability.text},
  );
});

/// The seam a future voice / AI search implementation plugs into.
///
/// WHAT THIS IS FOR
/// ----------------
/// The search bar needs somewhere to put a trailing action and somewhere to send
/// a recognised phrase when it arrives, and neither the bar nor the controller
/// should have to change when that arrives. This interface is that contract.
///
/// It is deliberately tiny and deliberately unimplemented. [noOp] is the
/// shipped default: it builds no affordance, so nothing about this file can be
/// mistaken for working voice search.
///
/// ## Why the callback is a parameter
///
/// [buildAction] receives the bar's delivery callback rather than exposing an
/// `onResult` method for the implementation to call. That inverts the mistake an
/// implementation would otherwise make: a recogniser that called straight into
/// the controller would bypass the debounce, the history write and the analytics
/// event, and a voice search would quietly behave differently from a typed one.
/// Handing the callback in makes the bar the only writer of search text, so
/// there is one path and it is the tested one.
abstract class SearchInputExtension {
  const SearchInputExtension();

  /// Builds the affordance to render in the bar, or returns null for none.
  ///
  /// Returning null (the default) is the "not implemented" answer, and the
  /// field renders nothing -- so a half-finished implementation degrades to an
  /// absent button rather than a dead one.
  ///
  /// [onResult] is how the extension delivers what it recognised. The field
  /// routes it through the same handling as typed input.
  Widget? buildAction(ValueChanged<String> onResult) => null;
}

/// The shipped default: no extension, no affordance, no microphone.
class NoopSearchInputExtension extends SearchInputExtension {
  const NoopSearchInputExtension();
}

/// Override this provider to install a real voice / AI implementation.
///
/// A `Provider`, not a compile-time constant, so a test can install a fake
/// extension and drive the affordance without a platform channel -- which is
/// how the bar's behaviour under an extension is verified at all.
final searchInputExtensionProvider = Provider<SearchInputExtension>(
  (ref) => const NoopSearchInputExtension(),
);
