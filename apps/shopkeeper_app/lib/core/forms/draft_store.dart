import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Session-scoped storage for half-finished forms.
///
/// "Preserve draft state" for a long form means two different things, and only
/// one of them is this:
///
///  * **Within the session** — the shopkeeper opens a picker, gets a call, backs
///    out of a sub-step, or taps a tab and comes back. Their typing is still
///    worth something. That is what this store does: it holds each form's draft
///    in memory, keyed by form, and hands it back when the form reopens.
///  * **After the app is killed** — that needs a disk store, and the app has no
///    general one (only `flutter_secure_storage`, for tokens). Adding a
///    dependency and a schema-migration story for drafts is a bigger decision
///    than this change should make silently, so it is NOT done here.
///
/// Deliberately in-memory and deliberately loud about it: a draft that survives
/// navigation but not a process kill is the honest middle ground. Anything
/// relying on it must still let the shopkeeper re-enter data if the app dies,
/// which is what this does.
///
/// Not persisted, so nothing here is a security surface — but drafts can hold a
/// shop's unpublished prices, so [clear] is called on save AND on an explicit
/// discard, and nothing writes a draft to disk.
class DraftStore extends ChangeNotifier {
  final Map<String, Object?> _drafts = <String, Object?>{};

  /// The saved draft for [key], or null.
  T? read<T>(String key) {
    final value = _drafts[key];
    return value is T ? value : null;
  }

  /// Whether [key] holds anything.
  ///
  /// Deliberately not `read(key) != null`: a draft can legitimately BE null
  /// (the shopkeeper cleared every field but has not left the form), and "they
  /// typed here and then emptied it" is still an unsaved-change signal.
  bool has(String key) => _drafts.containsKey(key);

  /// Store [draft] under [key] and tell listeners.
  void save<T>(String key, T draft) {
    _drafts[key] = draft;
    notifyListeners();
  }

  /// Forget [key]. Called on a successful save and on a confirmed discard.
  void clear(String key) {
    if (_drafts.remove(key) == null) return;
    notifyListeners();
  }

  /// Every key currently holding a draft — used by tests and by an
  /// "you have unfinished forms" surface later.
  Set<String> get keys => _drafts.keys.toSet();
}

final draftStoreProvider = Provider<DraftStore>((ref) {
  final store = DraftStore();
  ref.onDispose(store.dispose);
  return store;
});
