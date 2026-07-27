import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Autofill is banned app-wide, and this is what holds the ban.
///
/// The CRM runs the kiosk — a SHARED front-desk iPad that a queue of members
/// uses one after another. A form field offering autofill there hands the
/// previous member's address, and on the card step their billing details, to
/// whoever is standing at it next. That is a privacy failure with no
/// user-visible warning and no way for the next person to know it happened.
///
/// Until now the rule lived only in `CRM/CLAUDE.md` and in the fact that
/// nobody had added a hint yet — a convention, not a guarantee. The membership
/// flow makes the stakes concrete: one shared field box is now rendered by the
/// kiosk AND the desk, so a hint added for the desk's convenience would reach
/// the shared iPad without anyone editing a kiosk file.
///
/// The ban is app-wide rather than kiosk-scoped for exactly that reason: the
/// dangerous edit is the one made somewhere that looks safe.
void main() {
  test('no widget anywhere in the app offers autofill', () {
    final offenders = <String>[];
    final lib = Directory('lib');

    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Skip the doc comments that EXPLAIN the ban — naming the API in
        // prose is how the rule stays discoverable, and must not trip it.
        final code = line.trimLeft();
        if (code.startsWith('//') || code.startsWith('///')) continue;
        if (line.contains('AutofillHints') ||
            line.contains('AutofillGroup') ||
            line.contains('autofillHints')) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Autofill is banned app-wide: the kiosk is a shared iPad, so a '
          'hint offers the previous member\'s details to the next person. '
          'If a surface genuinely needs autofill, it must opt in locally AND '
          'the kiosk must explicitly opt out — change this test deliberately, '
          'never to make a build pass.',
    );
  });
}
