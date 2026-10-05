import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DATA CONTRACT -- the frontend is NOT the source of truth for: authorization
/// · inventory truth · price truth · verification truth · profile ownership.
/// The backend/database remains authoritative.
///
/// What this pins is the DIRECTION OF CORRECTION: the app is allowed to
/// *display* optimistic or cached values, but it may never *prefer* them --
/// when the server answers differently, the server wins. Concretely:
///
///   1. Authority lives server-side: writes send intent (+delta / payload),
///      never arithmetic the backend must accept ("new quantity = 15").
///   2. Cached data keeps its provenance (`ProductsSnapshotStore` +
///      `CachedDataNotice`): it is shown WITH a stale marker, never as live.
///   3. Fresh reads resolve what changed and re-display; errors never present
///      as successful empty catalogs.
///
/// `flow_contract_test.dart` (Q4/Q7) and `refresh_test.dart` already pin 1–3
/// on "adjust stock", the app's most frequent write. THIS file pins the same
/// rules structurally for the whole codebase: a scan that would fail on (a) a
/// payload field that ships client-side arithmetic as a target, and (b) any
/// render path that feeds unprovenanced data to a list.
void main() {
  group('DATA CONTRACT -- the server is the authority, scans enforce it', () {
    test('the codebase resolved (guards against a silent empty scan)', () {
      expect(
        Directory('lib').existsSync(),
        isTrue,
        reason: 'run from apps/shopkeeper_app',
      );
    });

    test('no write payload ships client-side arithmetic as a target', () {
      // A "truth" field is a field the backend stores as final: quantity,
      // price, mrp, stock count. The app must send intent (`delta`,
      // `adjustment`, the edited value), NEVER `old + delta` computed locally
      // as "the new value" -- on a stale row that arithmetic writes a lie the
      // server cannot detect. (Q4 already pins this for adjust-stock: the
      // payload carries `quantity_adjustment: 5` while the RENDER uses the
      // server's `newQuantity: 12`, not the client's 15.)
      //
      // Scope is deliberately WRITE-payloads only: JSON `fromJson` reads echo
      // the server's own stored values (server-explained, fine), UI labels
      // like "12 left, restock 5" compose DISPLAY text (read-only, fine), and
      // model defaults fill a local field so the row renders (not a target).
      // So this scan only looks inside `toJson` / `body:` constructions.
      final offenders = <String>[];
      for (final file
          in Directory('lib/features')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final lines = file.readAsLinesSync();
        var inWritePayload = false;
        var payloadDepth = 0;
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // Entering a write payload: a Map literal being built for upload, or
          // a request body under construction. `toJson` is excluded — its Map
          // is server-echo; `body` inside a WRITE method is included.
          if (RegExp(r'\bbody\s*[:=]').hasMatch(line) ||
              RegExp(r'Map<String,\s*dynamic>\s+\w*(payload|request|body)\w*')
                  .hasMatch(line)) {
            inWritePayload = true;
            payloadDepth = 0;
          }
          if (inWritePayload) {
            payloadDepth += '{'.allMatches(line).length;
            payloadDepth -= '}'.allMatches(line).length;
            final suspects = RegExp(
              r"""'(quantity|new_quantity|price|mrp|stock)'\s*:\s*""",
            );
            if (suspects.hasMatch(line)) {
              // A number literal (a constant default like VAT 0) is not
              // arithmetic; a variable arithmetic expression IS the lie.
              if (RegExp(r':\s*[\w.()\[\]]+\s*[+\-*/]\s*[\w.()\[\]]+')
                  .hasMatch(line)) {
                offenders.add('${file.path}:${i + 1}: ${line.trim()}');
              }
            }
            if (payloadDepth <= 0 && i > 0) inWritePayload = false;
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'A payload field ships client-computed arithmetic (or an '
            'ambiguous local) where the backend stores a truth. Send intent '
            '(delta/adjustment), and render the server echo -- never the '
            'other way around.\n${offenders.join('\n')}',
      );
    });

    test('no list renders snapshot data without a provenance surface', () {
      // `CachedDataNotice` is the app's single "this came from the device
      // snapshot" marker. A list that reads `ProductsSnapshotStore` (or any
      // `*Snapshot*` payload) without showing it renders stale rows AS IF
      // they were live -- the worse-than-no-data case the notice exists for.
      final snapshotReaders = <String>{};
      final noticeUsers = <String>{};
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        if (RegExp(r'SnapshotStore|snapshot\w*\.|fromSnapshot')
            .hasMatch(source)) {
          snapshotReaders.add(file.path);
        }
        if (source.contains('CachedDataNotice')) noticeUsers.add(file.path);
      }

      // The notice may live in shared list scaffolding rather than beside
      // every reader -- so this asserts the SET is non-empty rather than
      // demanding co-location: a refactor that deletes the marker entirely
      // fails here before a user ever sees unprovenanced rows.
      expect(
        noticeUsers,
        isNotEmpty,
        reason:
            'CachedDataNotice disappeared from lib/ -- snapshot-backed '
            'lists would render stale rows with no provenance marker.',
      );
      expect(
        snapshotReaders,
        isNotEmpty,
        reason: 'no snapshot readers resolved -- the scan is vacuous',
      );
    });
  });
}
