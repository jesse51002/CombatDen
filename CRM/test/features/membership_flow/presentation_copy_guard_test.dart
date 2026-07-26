import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The shared component set states NO sentence of its own.
///
/// Every user-facing word a flow widget renders arrives through
/// `MembershipFlowCopy`, so a wording change is a change to BOTH surfaces or
/// to neither. A literal left in `presentation/` is the drift this module
/// exists to prevent, in its most quietly damaging form: the kiosk keeps
/// saying "I'm getting a membership" while the desk says it too, at staff, in
/// the member's voice — and nobody notices until a gym owner does.
///
/// The heuristic is deliberately blunt: a quoted literal holding a SPACE and a
/// real word reads as a sentence. Everything a component legitimately still
/// holds — an import path, a currency code, an interpolated number — clears it
/// without an exemption list, which is what keeps the guard honest.
void main() {
  const root = 'lib/features/membership_flow/presentation';

  /// A word of three or more lowercase letters. `'USD'`, `'$number'` and a
  /// date pattern like `'d MMMM y'` all fail this on purpose.
  final wordy = RegExp(r'[a-z]{3}');

  /// Paths, not prose.
  bool isPath(String literal) =>
      literal.startsWith('package:') ||
      literal.startsWith('dart:') ||
      literal.endsWith('.dart');

  /// Every quoted literal on one line of Dart, with comments removed FIRST.
  ///
  /// Scanning character by character is what makes the comment strip correct:
  /// an apostrophe inside `// the buy row's thumb` would otherwise open a
  /// phantom string and flag a doc comment as copy.
  List<String> literalsIn(String line) {
    final found = <String>[];
    final buffer = StringBuffer();
    String? quote;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (quote == null) {
        if (char == '/' && i + 1 < line.length && line[i + 1] == '/') break;
        if (char == '\'' || char == '"') {
          quote = char;
          buffer.clear();
        }
        continue;
      }
      if (char == r'\') {
        // Keep the escaped character, drop the backslash: `'I\'m …'` is one
        // literal, not two.
        if (i + 1 < line.length) buffer.write(line[i + 1]);
        i++;
        continue;
      }
      if (char == quote) {
        found.add(buffer.toString());
        quote = null;
        continue;
      }
      buffer.write(char);
    }
    return found;
  }

  List<File> dartFilesUnder(String path) {
    final dir = Directory(path);
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'the shared component set moved or was renamed — point this '
          'guard at wherever `presentation/` lives now, or it silently '
          'protects nothing',
    );
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  test('the shared component set is non-empty', () {
    expect(dartFilesUnder(root), isNotEmpty);
  });

  test('no shared flow component holds a sentence of its own', () {
    final offences = <String>[];
    for (final file in dartFilesUnder(root)) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
        for (final literal in literalsIn(lines[i])) {
          if (isPath(literal)) continue;
          if (!literal.contains(' ')) continue;
          if (!wordy.hasMatch(literal)) continue;
          offences.add('${file.path}:${i + 1} → "$literal"');
        }
      }
    }
    expect(
      offences,
      isEmpty,
      reason: 'A shared component renders BOTH surfaces, so a sentence baked '
          'into one is a wording decision made for a surface that was not in '
          'the room. Move it to `MembershipFlowCopy` (an abstract method, so '
          'the second surface cannot forget to answer it) and take it from '
          '`MembershipFlowTheme.copyOf(context)`. Offending literals:\n'
          '${offences.join('\n')}',
    );
  });
}
