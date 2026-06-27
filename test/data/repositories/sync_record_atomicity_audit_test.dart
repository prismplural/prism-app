import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Deny-by-default audit of the emit-after-commit invariant.
///
/// Every durable sync emission (`syncRecordCreate/Update/Delete/DeleteMulti`)
/// must execute inside a `runSyncedWrite(...)` so the data write and the durable
/// outbox row commit (or roll back) together and the FFI dispatch fires strictly
/// post-commit. A bare `await _dao.write(); await syncRecord*()` is the reverted
/// dual-write shape that leaks a phantom op on rollback (see
/// `sync_record_mixin.dart` `runSyncedWrite`).
///
/// Unlike a hand-curated whitelist, this scans EVERY `drift_*_repository.dart`
/// (new repos included automatically) and fails on any emission — or any call to
/// an allowlisted wrapped-by-caller helper — that escapes a `runSyncedWrite`.
/// A new dual-write method fails CI unless it is wrapped or deliberately added
/// to the allowlist below with justification.
///
/// `syncRecordReconcile` / `syncRecordBackfill` are intentionally NOT audited:
/// they are divergence-aware live emissions (migration/catch-up), not the
/// durable outbox path. Importer/migration services are out of scope too — they
/// own their own `suppressAndCapture` + post-commit replay fence.
void main() {
  group('emit-after-commit audit (deny-by-default)', () {
    test('every durable emission is inside runSyncedWrite or a trusted helper',
        () {
      final files = _repoFiles();
      expect(files.length, greaterThanOrEqualTo(14),
          reason: 'glob should see the rewritten repositories');

      final violations = <String>[];
      for (final file in files) {
        final base = _basename(file.path);
        final code = _codeOnly(file.readAsStringSync());
        final methods = _methods(code);
        // Only runSyncedWrite is an accepted wrapper. suppress /
        // suppressAndCapture deliberately route emissions OUTSIDE the durable
        // outbox, so counting them as safe would mask a dual-write hidden in a
        // bare suppress block — the exact regression this audit must catch.
        final wraps = _spans(code, const ['runSyncedWrite']);

        final trustedNames = <String>{
          ..._wrappedByCallerHelpers[base] ?? const [],
          ..._importerExempt[base] ?? const [],
        };
        final trustedBodies = <List<int>>[];
        for (final name in trustedNames) {
          final region = _regionFor(code, methods, name);
          if (region == null) {
            violations.add(
                '$base: allowlisted helper `$name` no longer exists — remove '
                'it from the audit allowlist.');
            continue;
          }
          trustedBodies.add([region.bodyOpen, region.bodyClose]);
        }

        // Sites we require to sit inside a wrap: durable emissions, plus calls
        // to the wrapped-by-caller helpers (so a future UNWRAPPED public caller
        // of a helper is caught too). Skip each helper's own signature.
        final relayRegions = <String, _Region>{};
        for (final name in _wrappedByCallerHelpers[base] ?? const []) {
          final r = _regionFor(code, methods, name);
          if (r != null) relayRegions[name] = r;
        }

        final sites = <_Site>[
          for (final m in _emitSites(code)) _Site(m.start, m.group(0)!),
          for (final entry in relayRegions.entries)
            for (final m in _callSites(code, entry.key))
              if (!(m.start >= entry.value.declStart &&
                  m.start < entry.value.bodyOpen))
                _Site(m.start, m.group(0)!),
        ];

        for (final site in sites) {
          if (_inAnySpan(site.offset, wraps)) continue;
          if (_inAnySpan(site.offset, trustedBodies)) continue;
          final method = _enclosing(methods, site.offset);
          violations.add(
              '$base :: $method :: `${site.text.trim()}` emits/relays outside '
              'runSyncedWrite');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Emit-after-commit violation(s):\n'
            '  ${violations.join('\n  ')}\n\n'
            'Fix by wrapping the data write + emission in runSyncedWrite(() async {...}). '
            'If this is a verified helper whose every caller already wraps, add it to '
            '_wrappedByCallerHelpers with a note; if it is an intentional live '
            'migration/importer emission, add it to _importerExempt.',
      );
    });
  });
}

// ── Allowlists ───────────────────────────────────────────────────────────────

/// Private helpers that emit (or relay to an emitter) outside their own
/// `runSyncedWrite` because every caller wraps. The audit re-verifies this: a
/// call to one of these from an unwrapped method is itself a violation.
const _wrappedByCallerHelpers = <String, List<String>>{
  'drift_custom_fields_repository.dart': ['_softDeleteField'],
  'drift_front_session_comments_repository.dart': ['_reparentComments'],
  'drift_fronting_session_repository.dart': [
    '_fanOutPkIdentityAliasDeletes',
    '_softDeleteAttachedComments',
  ],
  'drift_member_groups_repository.dart': [
    '_syncGroupCreateIfAllowed',
    '_syncEntryCreateIfAllowed',
    '_syncGroupUpdateIfAllowed',
    '_syncLegacyPkGroupAliasDeletes',
    '_emitGroupSortStateUpdateIfAllowed',
  ],
  'drift_member_repository.dart': ['_fanOutPkIdentityAliasDeletes'],
  'drift_system_settings_repository.dart': [
    '_syncField',
    '_syncFieldIfThemeEnabled',
    '_syncFieldIfNavEnabled',
  ],
};

/// Intentionally LIVE emissions invoked post-commit by the importer/migration
/// (not the durable outbox path). Their callers are importer services, not repo
/// methods, so their call sites are not audited.
const _importerExempt = <String, List<String>>{
  'drift_fronting_session_repository.dart': ['emitFinalStateCreateIfSurviving'],
};

// ── Static-analysis helpers (operate on a comment/string-stripped view) ───────

const _emitTokens = [
  'syncRecordCreate',
  'syncRecordUpdate',
  'syncRecordDeleteMulti',
  'syncRecordDelete',
];

List<File> _repoFiles() => Directory('lib/data/repositories')
    .listSync()
    .whereType<File>()
    .where((f) =>
        _basename(f.path).startsWith('drift_') &&
        f.path.endsWith('_repository.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

String _basename(String path) => path.split(Platform.pathSeparator).last;

/// Replace comment and string-literal CONTENT with spaces (newlines preserved)
/// so paren/brace matching never trips over a paren in prose or a brace in a
/// string. Handles `//`, `/* */`, single/double/triple and raw strings.
String _codeOnly(String s) {
  final out = StringBuffer();
  var i = 0;
  final n = s.length;
  while (i < n) {
    final c = s[i];
    final c2 = (i + 1 < n) ? s[i + 1] : '';
    if (c == '/' && c2 == '/') {
      while (i < n && s[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (c == '/' && c2 == '*') {
      out.write('  ');
      i += 2;
      while (i < n && !(s[i] == '*' && i + 1 < n && s[i + 1] == '/')) {
        out.write(s[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < n) {
        out.write('  ');
        i += 2;
      }
      continue;
    }
    var raw = false;
    var q = i;
    if (c == 'r' && (c2 == '\'' || c2 == '"')) {
      raw = true;
      q = i + 1;
    }
    final qc = (q < n) ? s[q] : '';
    if (qc == '\'' || qc == '"') {
      final triple = (q + 2 < n) && s[q + 1] == qc && s[q + 2] == qc;
      if (raw) out.write(' ');
      final openLen = triple ? 3 : 1;
      out.write(' ' * openLen);
      i = q + openLen;
      while (i < n) {
        if (!raw && s[i] == '\\') {
          out.write('  ');
          i += 2;
          continue;
        }
        if (triple) {
          if (s[i] == qc && i + 2 < n && s[i + 1] == qc && s[i + 2] == qc) {
            out.write('   ');
            i += 3;
            break;
          }
        } else if (s[i] == qc) {
          out.write(' ');
          i++;
          break;
        } else if (s[i] == '\n') {
          out.write('\n');
          i++;
          break;
        }
        out.write(s[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

int _matchParen(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 0x28) {
      depth++;
    } else if (c == 0x29) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

int _matchBrace(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 0x7b) {
      depth++;
    } else if (c == 0x7d) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// Paren spans of `name(...)` / `name<...>(...)` for the given call names.
List<List<int>> _spans(String code, List<String> names) {
  final spans = <List<int>>[];
  for (final name in names) {
    final re = RegExp(r'\b' + name + r'(?:<[^(]*?>)?\s*\(');
    for (final m in re.allMatches(code)) {
      final open = code.indexOf('(', m.start);
      if (open < 0) continue;
      final close = _matchParen(code, open);
      if (close > 0) spans.add([open, close]);
    }
  }
  return spans;
}

bool _inAnySpan(int off, List<List<int>> spans) =>
    spans.any((sp) => off > sp[0] && off < sp[1]);

final _declRe = RegExp(
  r'\n  (?:Future<[^(]*?>|Future|void|Stream<[^(]*?>|[A-Za-z_]\w*(?:<[^(]*?>)?)'
  r'\s+([A-Za-z_]\w*)\s*(?:<[^(]*?>)?\s*\(',
);

class _Method {
  _Method(this.name, this.start);
  final String name;
  final int start;
}

List<_Method> _methods(String code) =>
    [for (final m in _declRe.allMatches(code)) _Method(m.group(1)!, m.start)];

String _enclosing(List<_Method> methods, int off) {
  var name = '<top-level>';
  for (final m in methods) {
    if (m.start < off) {
      name = m.name;
    } else {
      break;
    }
  }
  return name;
}

class _Region {
  _Region(this.declStart, this.bodyOpen, this.bodyClose);
  final int declStart;
  final int bodyOpen;
  final int bodyClose;
}

/// Declaration + body span for a named method (the first declaration match).
/// Handles both block bodies (`{...}`) and arrow bodies (`=> expr;`).
_Region? _regionFor(String code, List<_Method> methods, String name) {
  final decl = methods.firstWhere((m) => m.name == name,
      orElse: () => _Method('', -1));
  if (decl.start < 0) return null;
  final paramOpen = code.indexOf('(', decl.start);
  if (paramOpen < 0) return null;
  final paramClose = _matchParen(code, paramOpen);
  if (paramClose < 0) return null;
  final bracePos = code.indexOf('{', paramClose);
  final arrowPos = code.indexOf('=>', paramClose);
  if (arrowPos >= 0 && (bracePos < 0 || arrowPos < bracePos)) {
    final end = _stmtEnd(code, arrowPos);
    if (end < 0) return null;
    return _Region(decl.start, arrowPos, end);
  }
  if (bracePos < 0) return null;
  final bodyClose = _matchBrace(code, bracePos);
  if (bodyClose < 0) return null;
  return _Region(decl.start, bracePos, bodyClose);
}

/// Index of the `;` that ends an arrow expression starting at [from], skipping
/// any `;` nested inside `()`/`[]`/`{}`.
int _stmtEnd(String code, int from) {
  var depth = 0;
  for (var i = from; i < code.length; i++) {
    final c = code.codeUnitAt(i);
    if (c == 0x28 || c == 0x5b || c == 0x7b) {
      depth++;
    } else if (c == 0x29 || c == 0x5d || c == 0x7d) {
      depth--;
    } else if (c == 0x3b && depth == 0) {
      return i;
    }
  }
  return -1;
}

Iterable<RegExpMatch> _emitSites(String code) sync* {
  for (final token in _emitTokens) {
    yield* RegExp(r'\b' + token + r'\b\s*\(').allMatches(code);
  }
}

Iterable<RegExpMatch> _callSites(String code, String name) =>
    RegExp(r'\b' + name + r'\s*\(').allMatches(code);

class _Site {
  _Site(this.offset, this.text);
  final int offset;
  final String text;
}
