// ignore_for_file: avoid_print

/// One-off codemod: move inline user-visible strings into `lib/l10n/app_en.arb`.
///
/// Usage (from `apps/shopkeeper_app`):
///
/// ```
/// dart run tool/localize_ui_strings.dart --all          # dry run + report
/// dart run tool/localize_ui_strings.dart --all --write  # apply
/// dart run tool/localize_ui_strings.dart lib/features/products --write
/// ```
///
/// What it rewrites, and only when the literal is the *value of a display
/// position*:
///
/// * `Text('Continue')`                        -> `Text(appText(context).key)`
/// * `labelText / hintText / helperText /      -> catalog lookup
///   tooltip / semanticsLabel: 'Continue'`
/// * `title / subtitle / label / message / body / placeholder / ...` when the
///   enclosing call is a known display widget, a private widget in the same
///   file, or one of the state objects whose `message` the UI renders.
///
/// A literal inside a `const` expression makes that constructor non-constant,
/// so the enclosing `const` keyword is dropped as part of the rewrite.
///
/// Anything else — payload map values, `Key('…')`, `code: 'MANUAL'`-style
/// data, assignments (`final x = '…'`), `return '…'`, default parameter
/// values, `static const` tables — is left untouched and listed in the report
/// so a human can decide.
library;

import 'dart:convert';
import 'dart:io';

/// Named arguments that are always display copy.
const _alwaysDisplayArgs = <String>{
  'labelText',
  'hintText',
  'helperText',
  'tooltip',
  'semanticsLabel',
};

/// Named arguments that are display copy only for allow-listed callees.
const _displayArgNames = <String>{
  'title',
  'subtitle',
  'label',
  'message',
  'body',
  'placeholder',
  'header',
  'description',
  'hint',
  'caption',
  'fallbackMessage',
  'emptyMessage',
  'errorMessage',
  'successMessage',
};

/// Callees whose `title:`/`message:`/… arguments are rendered verbatim.
/// Private (`_Widget`) callees are accepted too: they are display widgets
/// declared in the same file.
const _displayCallees = <String>{
  'CapabilityGate',
  'PosMessageView',
  'FilterChoice',
  'FilterSection',
  'SettingsSection',
  'SettingsTile',
  'SettingsNotice',
  'SettingsIntro',
  'LegalSection',
  'FormFieldCard',
  'RegisterStepHeader',
  'PrimaryButton',
  'ShopInfoRow',
  'resolve',
  'empty',
  'copyWith',
  'PosState',
  'ProductsState',
  'HolidaysState',
  'ShopHoursState',
  'SessionsState',
  'ImportState',
  'SystemStateSpec',
  'InfoRow',
  'SheetHeader',
  'SectionCard',
};


enum _Kind { ident, string, number, punct, comment }

class _Tok {
  _Tok(this.kind, this.start, this.end, this.text);

  final _Kind kind;
  final int start;
  final int end;
  final String text;

  bool get isComment => kind == _Kind.comment;
  bool get isIdent => kind == _Kind.ident;
  bool get isString => kind == _Kind.string;
}

final _identChar = RegExp(r'[A-Za-z0-9_$]');

/// Given [src] and the index of an opening quote, returns the index just past
/// the closing quote. Handles escapes, raw literals and `${…}` interpolations —
/// which may themselves contain string literals using the same quote character
/// (`'${name ?? ''}'`), the case a naive scanner gets wrong.
int _scanString(String src, int quoteIdx, bool raw) {
  final n = src.length;
  final q = src.codeUnitAt(quoteIdx);
  final triple = quoteIdx + 2 < n &&
      src.codeUnitAt(quoteIdx + 1) == q &&
      src.codeUnitAt(quoteIdx + 2) == q;
  var j = quoteIdx + (triple ? 3 : 1);
  while (j < n) {
    final c = src.codeUnitAt(j);
    if (!raw && c == 0x5C) {
      j += j + 1 < n ? 2 : 1;
      continue;
    }
    if (!raw && c == 0x24 && j + 1 < n) {
      final next = src.codeUnitAt(j + 1);
      if (next == 0x7B) {
        j = _scanInterpolationEnd(src, j + 2);
        continue;
      }
      if (_identChar.hasMatch(src[j + 1])) {
        j++;
        while (j < n && _identChar.hasMatch(src[j])) {
          j++;
        }
        continue;
      }
      j++;
      continue;
    }
    if (triple) {
      if (c == q &&
          j + 2 < n &&
          src.codeUnitAt(j + 1) == q &&
          src.codeUnitAt(j + 2) == q) {
        return j + 3;
      }
    } else if (c == q) {
      return j + 1;
    } else if (c == 0x0A) {
      return j; // unterminated on this line
    }
    j++;
  }
  return n;
}

/// Scans the inside of `${ … }` starting just after the brace and returns the
/// index just past the matching close brace, counting nested braces and
/// skipping nested string literals.
int _scanInterpolationEnd(String src, int start) {
  final n = src.length;
  var depth = 1;
  var j = start;
  while (j < n) {
    final c = src[j];
    if (c == '{') {
      depth++;
      j++;
      continue;
    }
    if (c == '}') {
      depth--;
      j++;
      if (depth == 0) return j;
      continue;
    }
    if (c == '"' || c == "'") {
      final raw = j > 0 && src[j - 1] == 'r';
      j = _scanString(src, j, raw);
      continue;
    }
    j++;
  }
  return n;
}


/// Splits Dart source into identifiers, string literals, punctuation and
/// comments. Strings are whole tokens, so brackets inside them can never be
/// mistaken for structure.
List<_Tok> _tokenize(String src) {
  final out = <_Tok>[];
  final n = src.length;
  var i = 0;
  while (i < n) {
    final c = src.codeUnitAt(i);
    // Whitespace.
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      i++;
      continue;
    }
    // Comments.
    if (c == 0x2F && i + 1 < n && src.codeUnitAt(i + 1) == 0x2F) {
      final s = i;
      while (i < n && src.codeUnitAt(i) != 0x0A) {
        i++;
      }
      out.add(_Tok(_Kind.comment, s, i, src.substring(s, i)));
      continue;
    }
    if (c == 0x2F && i + 1 < n && src.codeUnitAt(i + 1) == 0x2A) {
      final s = i;
      i += 2;
      while (i + 1 < n &&
          !(src.codeUnitAt(i) == 0x2A && src.codeUnitAt(i + 1) == 0x2F)) {
        i++;
      }
      i = i + 1 < n ? i + 2 : n;
      out.add(_Tok(_Kind.comment, s, i, src.substring(s, i)));
      continue;
    }
    // String literals, including raw and triple-quoted forms.
    final raw = src[i] == 'r' &&
        i + 1 < n &&
        (src.codeUnitAt(i + 1) == 0x22 || src.codeUnitAt(i + 1) == 0x27);
    final q = src.codeUnitAt(raw ? i + 1 : i);
    if (q == 0x22 || q == 0x27) {
      final start = i;
      final end = _scanString(src, raw ? i + 1 : i, raw);
      i = end;
      out.add(_Tok(_Kind.string, start, end, src.substring(start, end)));
      continue;
    }
    // Identifiers and numbers.
    if (_identChar.hasMatch(src[i])) {
      final s = i;
      while (i < n && _identChar.hasMatch(src[i])) {
        i++;
      }
      final text = src.substring(s, i);
      final isNumber = RegExp(r'^[0-9]').hasMatch(text);
      out.add(_Tok(isNumber ? _Kind.number : _Kind.ident, s, i, text));
      continue;
    }
    out.add(_Tok(_Kind.punct, i, i + 1, src[i]));
    i++;
  }
  return out;
}


/// A display-position literal (or run of adjacent literals) that can be
/// replaced by a catalog lookup, plus the `const` keyword (if any) that has to
/// go with it.
class _DisplayLiteral {
  _DisplayLiteral(
    this.token,
    this.callee,
    this.argName,
    this.constStart, {
    required this.run,
    required this.end,
  });

  final _Tok token;
  final String callee;
  final String? argName;
  final int? constStart;

  /// Adjacent literals parsed as one message.
  final List<_Tok> run;

  /// Offset just past the last literal of [run].
  final int end;
}

class _Analyzed {
  final List<_DisplayLiteral> targets = [];
  final List<String> skipped = [];
}

class _Open {
  _Open(this.kind, this.callee, this.constStart);

  final String kind;
  final String callee;
  final int? constStart;
}

/// Walks back from an opening bracket to the callee name and whether that
/// call/collection is prefixed with `const` (`const Foo(`, `const [`,
/// `const Foo<T>(`).
(int?, String?) _calleeBefore(List<_Tok> toks, int openIdx) {
  var j = openIdx - 1;
  while (j >= 0 && toks[j].isComment) {
    j--;
  }
  // Skip an immediately preceding generic argument list: `Foo<T>(`.
  if (j >= 0 && (toks[j].text == '>' || toks[j].text == ']')) {
    final close = toks[j].text;
    final open = close == '>' ? '<' : '[';
    var depth = 0;
    while (j >= 0) {
      if (toks[j].text == close) depth++;
      if (toks[j].text == open) {
        depth--;
        if (depth == 0) break;
      }
      j--;
    }
    j--;
    while (j >= 0 && toks[j].isComment) {
      j--;
    }
  }
  String? callee;
  if (j >= 0 && toks[j].isIdent && toks[j].text != 'const') {
    callee = toks[j].text;
    j--;
    while (j >= 0 && toks[j].isComment) {
      j--;
    }
    // Chained segments: `SystemStateSpec.resolve(` -> callee stays `resolve`.
    while (j >= 0 && toks[j].text == '.') {
      j--;
      while (j >= 0 && toks[j].isComment) {
        j--;
      }
      if (j >= 0 && toks[j].isIdent) {
        j--;
        while (j >= 0 && toks[j].isComment) {
          j--;
        }
      } else {
        break;
      }
    }
  }
  int? constStart;
  if (j >= 0 && toks[j].isIdent && toks[j].text == 'const') {
    constStart = toks[j].start;
  }
  return (constStart, callee);
}

/// True when the statement owning [idx] is a field/static declaration, i.e. a
/// place where no `BuildContext` exists and the literal must stay put.
bool _inFieldDeclaration(String src, List<_Tok> toks, int idx) {
  final startIdx = _statementStart(toks, idx);
  final startOffset = startIdx < toks.length ? toks[startIdx].start : 0;
  final head = src.substring(startOffset, toks[idx].start).trimLeft();
  return RegExp(r'^(static|const|final|late)\b').hasMatch(head) ||
      RegExp(r'^static\s').hasMatch(head);
}

/// Index of the first token of the statement containing [idx].
int _statementStart(List<_Tok> toks, int idx) {
  var j = idx - 1;
  var depth = 0;
  while (j >= 0) {
    final t = toks[j];
    if (t.kind == _Kind.punct) {
      if (t.text == ')' || t.text == ']' || t.text == '}') {
        depth++;
      } else if (t.text == '(' || t.text == '[' || t.text == '{') {
        if (depth == 0) return j + 1;
        depth--;
      } else if (t.text == ';' && depth == 0) {
        return j + 1;
      }
    }
    j--;
  }
  return 0;
}


int _prevMeaningfulIdx(List<_Tok> toks, int i) {
  for (var j = i - 1; j >= 0; j--) {
    if (!toks[j].isComment) return j;
  }
  return -1;
}

/// Finds every display-position literal in one file.
_Analyzed _analyze(List<_Tok> toks, String src) {
  final out = _Analyzed();
  final stack = <_Open>[];
  for (var i = 0; i < toks.length; i++) {
    final t = toks[i];
    if (t.isComment) continue;
    if (t.kind == _Kind.punct) {
      if (t.text == '(' || t.text == '[' || t.text == '{') {
        final (constStart, callee) = _calleeBefore(toks, i);
        stack.add(_Open(t.text, callee ?? '', constStart));
      } else if (t.text == ')' || t.text == ']' || t.text == '}') {
        if (stack.isNotEmpty) stack.removeLast();
      }
      continue;
    }
    if (!t.isString) continue;

    final pIdx = _prevMeaningfulIdx(toks, i);
    if (pIdx < 0) continue;
    final prev = toks[pIdx];
    String? argName;
    var display = false;

    if (prev.text == '(') {
      // First positional argument: only `Text('…')` qualifies.
      final callee = stack.isEmpty ? '' : stack.last.callee;
      display = callee == 'Text';
    } else if (prev.text == ':') {
      final nIdx = _prevMeaningfulIdx(toks, pIdx);
      if (nIdx < 0 || !toks[nIdx].isIdent) continue;
      argName = toks[nIdx].text;
      final callee = stack.isEmpty ? '' : stack.last.callee;
      display = _alwaysDisplayArgs.contains(argName) ||
          (_displayArgNames.contains(argName) &&
              (_displayCallees.contains(callee) || callee.startsWith('_')));
    }
    if (!display) continue;

    // Everything below is a display literal; decide whether we may rewrite it.
    final line = _lineNumberAt(src, t.start);
    String? skip;
    if (prev.text == '=') {
      skip = 'assigned, not rendered directly';
    } else if (_inFieldDeclaration(src, toks, i)) {
      skip = 'static/const table needs a manual refactor';
    } else if (t.text.length < 3) {
      skip = 'empty literal';
    } else if (t.text.startsWith("'''") || t.text.startsWith('"""')) {
      skip = 'multi-line literal';
    }
    if (skip != null) {
      out.skipped.add('line $line: $skip — ${t.text}');
      continue;
    }

    // Adjacent literals are a single message: `'a ' 'b'` is `a b`.
    final run = <_Tok>[t];
    var last = i;
    while (last + 1 < toks.length && toks[last + 1].isString) {
      last++;
      run.add(toks[last]);
    }

    int? constStart;
    for (final open in stack.reversed) {
      if (open.constStart != null) {
        constStart = open.constStart;
        break;
      }
    }
    out.targets.add(_DisplayLiteral(
      run.first,
      stack.last.callee,
      argName,
      constStart,
      run: run,
      end: run.last.end,
    ));
  }
  return out;
}

int _lineNumberAt(String src, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < src.length; i++) {
    if (src.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}


/// A literal's text value plus any interpolations, ready for the catalog.
class _Parsed {
  _Parsed(this.value, this.placeholders, this.expressions);

  final String value;
  final List<String> placeholders;
  final List<String> expressions;
}

/// Turns a Dart string literal into its value, replacing `$name` / `${expr}`
/// with `{name}`-style ICU placeholders.
_Parsed? _parseLiteral(String raw) {
  if (raw.length < 2) return null;
  final isRaw = raw.startsWith('r"') || raw.startsWith("r'");
  final body = raw.substring(isRaw ? 2 : 1, raw.length - 1);
  if (body.contains('\n')) return null;
  final buf = StringBuffer();
  final placeholders = <String>[];
  final expressions = <String>[];
  var i = 0;
  while (i < body.length) {
    final c = body[i];
    if (!isRaw && c == '\\' && i + 1 < body.length) {
      final n = body[i + 1];
      if (n == 'u' && i + 2 < body.length) {
        final braced = body[i + 2] == '{';
        final end = braced ? body.indexOf('}', i + 3) : i + 6;
        if (end > 0) {
          final hex = body.substring(braced ? i + 3 : i + 2, end);
          final code = int.tryParse(hex, radix: 16);
          if (code != null) {
            buf.writeCharCode(code);
            i = braced ? end + 1 : end;
            continue;
          }
        }
      }
      buf.write(switch (n) {
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        '"' => '"',
        "'" => "'",
        '\\' => '\\',
        r'$' => r'$',
        _ => n,
      });
      i += 2;
      continue;
    }
    if (c == r'$' && i + 1 < body.length) {
      String? expr;
      var next = i + 1;
      if (body[next] == '{') {
        final end = _scanInterpolationEnd(body, next + 1);
        expr = body.substring(next + 1, end - 1);
        next = end;
      } else if (RegExp(r'[A-Za-z_]').hasMatch(body[next])) {
        var j = next;
        while (j < body.length && RegExp(r'[A-Za-z0-9_]').hasMatch(body[j])) {
          j++;
        }
        expr = body.substring(next, j);
        next = j;
      }
      if (expr != null) {
        final name = _placeholderName(expr, placeholders);
        placeholders.add(name);
        expressions.add(expr);
        buf.write('{$name}');
        i = next;
        continue;
      }
    }
    buf.write(c);
    i++;
  }
  return _Parsed(buf.toString(), placeholders, expressions);
}

/// Parses a run of adjacent string literals as one value: Dart concatenates
/// them, so `'a ' 'b'` is the single message `a b`.
_Parsed? _parseRun(List<_Tok> run) {
  if (run.isEmpty) return null;
  if (run.length == 1) return _parseLiteral(run.first.text);
  final placeholders = <String>[];
  final expressions = <String>[];
  final buffer = StringBuffer();
  for (final token in run) {
    var parsed = _parseLiteral(token.text);
    if (parsed == null) return null;
    var value = parsed.value;
    for (var i = 0; i < parsed.placeholders.length; i++) {
      final expression = parsed.expressions[i];
      final shared = expressions.indexOf(expression);
      final String name;
      if (shared == -1) {
        // Names must be unique across the whole merged message, not just
        // within this part: ICU would otherwise collapse them.
        name = _placeholderName(expression, placeholders);
        expressions.add(expression);
        placeholders.add(name);
        if (name != parsed.placeholders[i]) {
          value = value.replaceAll(
              '{${parsed.placeholders[i]}}', '{$name}');
        }
      } else {
        name = placeholders[shared];
        if (name != parsed.placeholders[i]) {
          value = value.replaceAll(
              '{${parsed.placeholders[i]}}', '{$name}');
        }
      }
    }
    buffer.write(value);
  }
  return _Parsed(buffer.toString(), placeholders, expressions);
}

String _placeholderName(String expr, List<String> taken) {
  final match = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)$').firstMatch(expr);
  final base = match?.group(1) ?? 'value';
  var name = base;
  var n = 2;
  while (taken.contains(name)) {
    name = '$base$n';
    n++;
  }
  return name;
}

/// Short phrases are shared across screens (`commonRetry`, `commonSave`);
/// longer sentences get a file-scoped key so two screens can diverge later.
String _keyFor(String prefix, _Parsed parsed) {
  final isShort = parsed.placeholders.isEmpty &&
      parsed.value.length <= 24 &&
      RegExp(r"^[A-Za-z0-9 &'’.,!?()/-]+$").hasMatch(parsed.value);
  return '${isShort ? 'common' : prefix}${_wordsOf(parsed.value)}';
}

/// `products_screen.dart` -> `productsScreen`.
String _filePrefix(String path) {
  final file = path.split(RegExp(r'[/\\]')).last.replaceAll('.dart', '');
  final words = file.split(RegExp(r'[^A-Za-z0-9]+'));
  if (words.isEmpty) return 'ui';
  return words.first +
      words
          .skip(1)
          .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
          .join();
}

/// `Add to stock` -> `AddToStock`, capped so keys stay readable.
String _wordsOf(String value) {
  final parts = value
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(5)
      .map((w) => w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))
      .join();
  return parts.isEmpty ? 'Text' : parts;
}


/// The catalog being extended. Existing text is preserved byte for byte; new
/// entries are appended in alphabetical order before the closing brace.
class _Catalog {
  _Catalog(this.original, this.existing);

  factory _Catalog.fromText(String text) {
    final map = jsonDecode(text) as Map<String, dynamic>;
    return _Catalog(
      text,
      {
        for (final e in map.entries)
          if (!e.key.startsWith('@')) e.key: e.value,
      },
    );
  }

  final String original;
  final Map<String, String> existing;

  Set<String> get taken => existing.keys.toSet();
  final Map<String, _Parsed> added = {};

  /// Reuses an identical existing entry so re-runs are idempotent, otherwise
  /// appends a fresh key (with a numeric suffix when the name is taken).
  String add(String key, _Parsed parsed) {
    if (existing[key] == parsed.value && !added.containsKey(key)) {
      return key;
    }
    var candidate = key;
    var n = 2;
    while (existing.containsKey(candidate) || added.containsKey(candidate)) {
      candidate = '$key${n++}';
    }
    added[candidate] = parsed;
    return candidate;
  }

  String render() {
    if (added.isEmpty) return original;
    final nl = original.contains('\r\n') ? '\r\n' : '\n';
    final keys = added.keys.toList()..sort();
    final entries = <String>[];
    for (final key in keys) {
      final parsed = added[key]!;
      entries.add('  ${jsonEncode(key)}: ${jsonEncode(parsed.value)}');
      if (parsed.placeholders.isNotEmpty) {
        final seen = <String>{};
        final placeholders = parsed.placeholders
            .where(seen.add)
            .map((p) => '      ${jsonEncode(p)}: { "type": "Object" }')
            .join(',$nl');
        entries.add('  ${jsonEncode('@$key')}: {$nl'
            '    "placeholders": {$nl'
            '$placeholders$nl'
            '    }$nl'
            '  }');
      }
    }
    final base = original.trimRight();
    // `base` ends with the object's closing brace; the previous last entry has
    // no comma, which the comma we add here supplies.
    return '${base.substring(0, base.length - 1)},$nl'
        '${entries.join(',$nl')}$nl}$nl';
  }
}

/// Relative import path to `app_text.dart`, in this repo's `../` style.
String _relativeImportPath(String filePath) {
  final dir = filePath.replaceAll('\\', '/').split('/')..removeLast();
  final dirParts = dir.where((p) => p.isNotEmpty && p != '.').toList();
  const target = ['lib', 'core', 'l10n', 'app_text.dart'];
  var common = 0;
  while (common < dirParts.length &&
      common < target.length - 1 &&
      dirParts[common] == target[common]) {
    common++;
  }
  final ups = dirParts.length - common;
  return '${'../' * ups}${target.sublist(common).join('/')}';
}

/// Offset right after the import [rel] should follow, keeping this repo's
/// convention: a block of `package:` imports, then a block of relative ones.
int _importInsertOffset(String src, String rel) {
  final re = RegExp(r"^import\s+'([^']+)';", multiLine: true);
  final relative = rel.startsWith('.');
  var after = -1;
  int? firstOfKind;
  int? lastAny;
  for (final m in re.allMatches(src)) {
    final path = m.group(1)!;
    final isRelative = path.startsWith('.');
    if (isRelative != relative) continue;
    firstOfKind ??= m.start;
    lastAny = m.end;
    if (path.compareTo(rel) < 0) after = m.end;
  }
  if (firstOfKind == null) {
    // No import of this kind yet: append after the whole import block.
    for (final m in re.allMatches(src)) {
      lastAny = m.end;
    }
    return lastAny ?? -1;
  }
  return after == -1 ? firstOfKind : after;
}


/// True when the file mentions `context` in actual code. Comments do not count:
/// prose like "the caller decides whether its own context makes a Retry
/// meaningful" must not make a context-free utility look like a widget.
bool _hasContextIdentifier(String src) {
  final code = src
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');
  return RegExp(r'\bcontext\b').hasMatch(code);
}

/// Guards against a mis-parse producing an unbalanced message: ICU would fail
/// the whole `gen-l10n` run on it, so it never reaches the catalog.
String? _braceIssue(_Parsed parsed) {
  var depth = 0;
  for (var i = 0; i < parsed.value.length; i++) {
    final c = parsed.value[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth < 0) return 'unbalanced } in value';
    }
  }
  if (depth != 0) return 'unbalanced { in value';
  for (final p in parsed.placeholders) {
    if (!parsed.value.contains('{$p}')) {
      return 'placeholder {$p} missing from value';
    }
  }
  return null;
}

/// Rewrites one file and records the catalog entries it needs.
void _processFile({
  required File file,
  required _Catalog catalog,
  required bool write,
  required bool force,
  required StringBuffer localized,
  required List<String> skipped,
  required Map<String, int> byPosition,
  required Map<String, String> addedPreview,
}) {
  final src = file.readAsStringSync();
  final analyzed = _analyze(_tokenize(src), src);
  for (final s in analyzed.skipped) {
    skipped.add('${file.path}\n      $s');
  }
  if (analyzed.targets.isEmpty) return;
  if (!force && !_hasContextIdentifier(src)) {
    skipped.add('${file.path}\n      no BuildContext in this file — '
        '${analyzed.targets.length} display strings need a manual pass');
    return;
  }

  final edits = <(int, int, String)>[];
  final constStarts = <int>{};
  final keyByValue = <String, String>{};
  final prefix = _filePrefix(file.path);
  var converted = 0;

  for (final target in analyzed.targets) {
    final parsed = _parseRun(target.run);
    if (parsed == null) {
      skipped.add('${file.path}\n      line '
          '${_lineNumberAt(src, target.token.start)}: unparseable — '
          '${target.run.map((t) => t.text).join(' ')}');
      continue;
    }
    final issue = _braceIssue(parsed);
    if (issue != null) {
      skipped.add('${file.path}\n      line '
          '${_lineNumberAt(src, target.token.start)}: $issue — '
          '${target.run.map((t) => t.text).join(' ')}');
      continue;
    }
    final key = keyByValue.putIfAbsent(parsed.value, () {
      final created = catalog.add(_keyFor(prefix, parsed), parsed);
      addedPreview[created] = parsed.value;
      return created;
    });
    final call = parsed.expressions.isEmpty
        ? 'appText(context).$key'
        : 'appText(context).$key(${parsed.expressions.join(', ')})';
    edits.add((target.token.start, target.end, call));
    if (target.constStart != null) constStarts.add(target.constStart!);
    final position = '${target.callee}.${target.argName ?? 'positional'}';
    byPosition[position] = (byPosition[position] ?? 0) + 1;
    converted++;
  }
  if (edits.isEmpty) return;

  // A `const` expression cannot hold a runtime lookup any more.
  for (final start in constStarts) {
    final match = RegExp(r'^const\s+').firstMatch(src.substring(start));
    if (match != null) {
      edits.add((start, start + match.end, ''));
    }
  }

  if (!src.contains('app_text.dart')) {
    final rel = _relativeImportPath(file.path);
    final at = _importInsertOffset(src, rel);
    if (at != -1) {
      final nl = src.contains('\r\n') ? '\r\n' : '\n';
      final atLineStart = at == 0 || src[at - 1] == '\n';
      edits.add((at, at, atLineStart ? "import '$rel';$nl" : "${nl}import '$rel';"));
    }
  }

  edits.sort((a, b) => b.$1.compareTo(a.$1));
  var out = src;
  for (final edit in edits) {
    out = out.substring(0, edit.$1) + edit.$3 + out.substring(edit.$2);
  }
  localized.writeln('  ${file.path}  ($converted strings)');
  if (write) {
    file.writeAsStringSync(out);
  }
}

void main(List<String> argv) {
  final write = argv.contains('--write');
  final force = argv.contains('--force');
  final roots = argv.where((a) => !a.startsWith('--')).toList();
  if (roots.isEmpty) {
    print('usage: dart run tool/localize_ui_strings.dart <dir|file>... '
        '[--write]');
    print('example: dart run tool/localize_ui_strings.dart lib --write');
    return;
  }

  final files = <File>[];
  for (final path in roots) {
    switch (FileSystemEntity.typeSync(path)) {
      case FileSystemEntityType.directory:
        for (final f in Directory(path).listSync(recursive: true)) {
          if (f is File &&
              f.path.endsWith('.dart') &&
              !f.path.replaceAll('\\', '/').split('/').contains('l10n')) {
            files.add(f);
          }
        }
      case FileSystemEntityType.file:
        files.add(File(path));
      default:
        print('not found: $path');
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));

  final catalog =
      _Catalog.fromText(File('lib/l10n/app_en.arb').readAsStringSync());
  final localized = StringBuffer();
  final skipped = <String>[];
  final byPosition = <String, int>{};
  final added = <String, String>{};

  for (final file in files) {
    _processFile(
      file: file,
      catalog: catalog,
      write: write,
      force: force,
      localized: localized,
      skipped: skipped,
      byPosition: byPosition,
      addedPreview: added,
    );
  }
  if (write) {
    File('lib/l10n/app_en.arb').writeAsStringSync(catalog.render());
  }

  print(write ? 'APPLIED' : 'DRY RUN — pass --write to apply');
  print('\nFiles touched:\n$localized');
  print('Rewrites by position (calibration):');
  final positions = byPosition.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in positions) {
    print('  ${e.value.toString().padLeft(4)}  ${e.key}');
  }
  print('\nCatalog keys used: ${added.length}');
  for (final e in added.entries.take(10)) {
    print('  ${e.key} = ${jsonEncode(e.value)}');
  }
  if (added.length > 10) {
    print('  ... and ${added.length - 10} more');
  }
  print('Newly appended entries: ${catalog.added.length}');
  print('\nLeft for manual work: ${skipped.length}');
  for (final s in skipped.take(30)) {
    print('  $s');
  }
  if (skipped.length > 30) {
    print('  ... and ${skipped.length - 30} more');
  }
}
