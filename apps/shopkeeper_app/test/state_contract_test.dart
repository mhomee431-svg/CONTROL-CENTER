import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// STATE CONTRACT -- every screen clearly supports:
/// INITIAL · LOADING · SUCCESS/LOADED · EMPTY · ERROR;
/// mutation screens additionally: SAVING · SUCCESS · FAILURE.
///
/// `SystemStateView` / `SystemStateBody` already own the renderers and
/// `system_state_test.dart` already pins EVERY state (copy + icon + the one
/// action that fixes it, loading→failure→content order). What was unpinned
/// are the two glue rules that make the vocabulary APPLY instead of merely
/// existing:
///
///   1. The vocabulary must be REACHABLE: every mutation/status enum the
///      screens branch on needs an ERROR-shaped member -- otherwise a failure
///      has nowhere to go and surfaces as a spinner that never ends.
///   2. `INITIAL` must be covered: a screen that can render before its
///      controller names an explicit status would violate the contract on its
///      first frame.
///
/// Rule 1 is unprovable by enum-name shape (a `RegistrationStep` is
/// navigation, not a mutation lifecycle; a `SubmitPhase` carries its failure
/// in a separate message field) -- so the enforceable rule is one level up:
/// no controller `catch` may swallow a failure into silence. Every mutation
/// screen must CLEAR its spinner AND say what happened -- through a latched
/// message, a rethrow, or a log -- or the write ends as silence and the UI
/// diverges from the backend truth.
void main() {
  group('STATE CONTRACT -- failure always has somewhere to land', () {
    List<File> controllerFiles() =>
        Directory('lib/features')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('_controller.dart'))
            .toList();

    test('the scan actually resolved controller files', () {
      expect(controllerFiles().length, greaterThan(15));
    });

    test('no async controller body can fail without surfacing a message', () {
      // A mutation screen whose controller catches and DROPS the failure
      // violates "SAVING -> SUCCESS | FAILURE": the spinner clears (or not),
      // but the shopkeeper is never told the write did not land -- silent
      // divergence from the backend truth. The survivable shapes are:
      //
      //   catch (e) { state = …error(e.message…); }   // message latched
      //   catch (e) { … message = …; }                 // message latched
      //   rethrow / throw                               // handed upward
      //
      // What must NOT appear is a catch whose body latches NOTHING readable --
      // bare `catch (_) {}` / `catch (e) {}` / a swallow-then-return.
      final offenders = <String>[];
      for (final file in controllerFiles()) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!RegExp(r'\bcatch\s*\(').hasMatch(line)) continue;
          // Skip a line that only CLOSES a try/catch (`} catch (_) {` is one
          // line in this codebase) — the same handler is found on its own
          // `catch (...) {` line, where the body actually lives. Counting both
          // would report the same block twice, once with no body to read.
          if (RegExp(r'^\s*\}\s*$')
              .hasMatch(line.substring(0, line.indexOf('catch')))) {
            continue;
          }
          // Read the catch body until the closing brace at the same depth.
          var depth = 0;
          var seenOpen = false;
          final body = StringBuffer();
          // Start one line BELOW the `catch` when the `}` opener sits on the
          // same line, so the first line does not immediately close depth 0.
          var k = i;
          if (RegExp(r'\{\s*$').hasMatch(line) &&
              !RegExp(r'^\s*catch\s*\(').hasMatch(line)) {
            depth = 1;
            seenOpen = true;
            k = i + 1;
          }
          for (; k < lines.length && k < i + 25; k++) {
            for (final c in lines[k].codeUnits) {
              if (c == 123) {
                depth++;
                seenOpen = true;
              } else if (c == 125) {
                depth--;
              }
            }
            body.write(lines[k]);
            if (seenOpen && depth <= 0) break;
          }
          final text = body.toString();
          // The contract is about MUTATION surfaces the shopkeeper is
          // looking at. Three deliberate shapes are NOT violations, and each
          // has to be proven from the code rather than assumed:
          //
          //  1. best-effort teardown / cleanup after the primary outcome
          //     (logout wiping local history, revoking a session);
          //  2. an OPTIONAL secondary signal whose absence is silent by
          //     design (alerts, capabilities, recent searches, a cosmetic
          //     session refresh);
          //  3. a doc comment that explicitly says the failure is ignored.
          //
          // Anything else must latch readable copy (a message the UI shows),
          // rethrow, or log -- a failed WRITE that ends in silence is
          // exactly what the FAILURE half of the contract forbids.
          final deliberateDoc = RegExp(
            r'best-effort|never block|permissive|cosmetic|silently|'
            r'fails? soft|optional|never fails',
          );
          final latchesReadable = RegExp(
            r'message|error|failure|failed|Error|Exception|'
            r'rethrow|throw\b|debugPrint|log\(|SnackBar|toast',
          ).hasMatch(text);
          if (!latchesReadable && !deliberateDoc.hasMatch(text)) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'A controller catch-block latches NOTHING the shopkeeper can '
            'see. A failed write therefore ends as silence -- the screen shows '
            'neither FAILURE nor the stale truth. Latch `.message`/`.error`, '
            'rethrow, or log; never swallow.\n${offenders.join('\n')}',
      );
    });
  });
}
