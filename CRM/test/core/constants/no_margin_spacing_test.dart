import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **`margin:` is banned in `lib/`, and this is the ban made executable.**
///
/// CRM/CLAUDE.md: *"Never use `margin` on Container/DecoratedBox for spacing
/// between widgets — use the parent's `spacing:`."* The reason is ownership: a
/// gap between two siblings belongs to the thing that arranges them, so a
/// margin on a child hides it where no parent can see or change it. The waiver
/// editor's `_versionTile` was the last instance and showed the failure mode
/// exactly — the same tile is rendered once above a loop and once inside it, so
/// its own top margin was silently doing the list's spacing job, and the list
/// had no way to reproduce or override it.
///
/// A widget test can't catch this (a margin renders perfectly well), so the
/// rule is checked at the source level, the same way
/// `test/features/kiosk/kiosk_forbidden_imports_test.dart` checks its import
/// ban. Comments are excluded so a line explaining *why* there is no margin
/// doesn't read as a violation.
void main() {
  List<File> libFiles() {
    final root = Directory('lib');
    expect(root.existsSync(), isTrue,
        reason: 'run this suite from the CRM package root');
    return root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  test('the lib tree is non-empty', () {
    expect(libFiles(), isNotEmpty);
  });

  test('no widget in lib/ carries a margin: — gaps belong to the parent', () {
    final offences = <String>[];
    for (final file in libFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].trim();
        if (code.startsWith('//') || code.startsWith('///')) continue;
        if (code.contains('margin:')) {
          offences.add('${file.path}:${i + 1} → $code');
        }
      }
    }
    expect(
      offences,
      isEmpty,
      reason: 'A gap between siblings is the parent\'s `spacing:`, never a '
          'child\'s margin — CRM/CLAUDE.md forbids `margin:` outright. Wrap '
          'the siblings in a Column/Row with `spacing:` instead. Offending '
          'lines:\n${offences.join('\n')}',
    );
  });
}
