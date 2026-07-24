import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Structural guards on the kiosk type ramp.
///
/// The bug these exist to catch: a pass that re-scales SOME kiosk roles and
/// leaves the rest on the admin ramp. That is how the "Get it" button's label
/// ended up bigger than the copy around it — the buttons had been lifted to
/// the mockup's kiosk sizes while the labels stayed at admin scale. The
/// mockup's ramp is internally proportional; ours only stays proportional if
/// the whole ladder moves as a SET, so these tests assert the ORDER rather
/// than any one number, and a half-finished future change fails here instead
/// of on a kiosk in a gym.
///
/// The ladder itself, and what each role is for, is documented on the ramp
/// comment in `design_constants.dart`.
///
/// These are `testWidgets` rather than plain `test`s only because the tokens
/// resolve their family through `GoogleFonts.geist()`: the widget-test binding
/// is what absorbs that font fetch, exactly as the rest of the kiosk suite
/// does. Nothing here pumps a widget.
void main() {
  double size(TextStyle style) {
    final value = style.fontSize;
    expect(value, isNotNull, reason: 'every kiosk token pins a fontSize');
    return value!;
  }

  /// The full ladder, largest first — the same order documented on the ramp in
  /// `design_constants.dart`. Built lazily inside each test: reading a token
  /// at suite-load time resolves `GoogleFonts` outside any test zone, which
  /// strands the whole file.
  Map<String, TextStyle> ladder() => <String, TextStyle>{
        'kioskStreakNum': DesignConstants.kioskStreakNum,
        'kioskDisplay': DesignConstants.kioskDisplay,
        'kioskMetric': DesignConstants.kioskMetric,
        'kioskPanelTitle': DesignConstants.kioskPanelTitle,
        'kioskStatement': DesignConstants.kioskStatement,
        'kioskFieldText': DesignConstants.kioskFieldText,
        'kioskTitle': DesignConstants.kioskTitle,
        'kioskButtonPrimaryLabel': DesignConstants.kioskButtonPrimaryLabel,
        'kioskName': DesignConstants.kioskName,
        'kioskSubtitle': DesignConstants.kioskSubtitle,
        'kioskButtonOutlineLabel': DesignConstants.kioskButtonOutlineLabel,
        'kioskButtonGhostLabel': DesignConstants.kioskButtonGhostLabel,
        'kioskBody': DesignConstants.kioskBody,
        'kioskLabel': DesignConstants.kioskLabel,
        'kioskSectionText': DesignConstants.kioskSectionText,
        'kioskCaption': DesignConstants.kioskCaption,
        'kioskMicro': DesignConstants.kioskMicro,
        'kioskMonoValue': DesignConstants.kioskMonoValue,
        'kioskEyebrow': DesignConstants.kioskEyebrow,
        'kioskTag': DesignConstants.kioskTag,
      };

  group('kiosk type ramp ordering', () {
    testWidgets(
      'section head > subtitle > outline button label > app line',
      (tester) async {
        // The exact chain the founder called out: a heading must out-size the
        // copy under it, and a BUTTON must never out-size either. Mockup
        // `.sub-title` 21 / `.screen-head .sub` 18 / `.btn-outline` 17 /
        // `.app-line` 15.
        final head = size(DesignConstants.kioskTitle);
        final subtitle = size(DesignConstants.kioskSubtitle);
        final outlineLabel = size(DesignConstants.kioskButtonOutlineLabel);
        final appLine = size(DesignConstants.kioskCaption);

        expect(head, greaterThan(subtitle));
        expect(subtitle, greaterThan(outlineLabel));
        expect(outlineLabel, greaterThan(appLine));
      },
    );

    testWidgets('no kiosk button label out-sizes a heading', (tester) async {
      final primaryLabel = size(DesignConstants.kioskButtonPrimaryLabel);
      final outlineLabel = size(DesignConstants.kioskButtonOutlineLabel);
      final ghostLabel = size(DesignConstants.kioskButtonGhostLabel);

      for (final heading in <TextStyle>[
        DesignConstants.kioskDisplay,
        DesignConstants.kioskPanelTitle,
        DesignConstants.kioskTitle,
      ]) {
        expect(primaryLabel, lessThan(size(heading)));
        expect(outlineLabel, lessThan(size(heading)));
        expect(ghostLabel, lessThan(size(heading)));
      }
      // The pair keeps its own order too (the mockup pairs 19 with 17).
      expect(primaryLabel, greaterThan(outlineLabel));
    });

    testWidgets('the escape tier is DEMOTED by weight, not by shrinking',
        (tester) async {
      // The ghost is the quietest button in the ladder, but a member has to
      // find it from ~2m. It keeps the outline's 17px (the kiosk interactive
      // floor) and drops a weight instead — shrinking it below the floor is
      // the failure mode this guards.
      final outline = DesignConstants.kioskButtonOutlineLabel;
      final ghost = DesignConstants.kioskButtonGhostLabel;

      expect(size(ghost), size(outline));
      expect(
        ghost.fontWeight!.value,
        lessThan(outline.fontWeight!.value),
        reason: 'the escape tier is demoted by weight, never by size',
      );
      // And it still reads: text2nd clears AA where text3rd would not.
      expect(ghost.color, DesignConstants.text2nd);
    });

    testWidgets('the whole ladder descends, largest first', (tester) async {
      // Ties are legal (the mockup genuinely sizes some roles alike); an
      // INVERSION is not — that is a role that moved on its own.
      final steps = ladder();
      final names = steps.keys.toList();
      for (var i = 1; i < names.length; i++) {
        final above = names[i - 1];
        final below = names[i];
        expect(
          size(steps[below]!),
          lessThanOrEqualTo(size(steps[above]!)),
          reason: '$below must not out-size $above — the kiosk ramp moves as '
              'a set, so re-scale the whole ladder or none of it',
        );
      }
    });

    testWidgets('every kiosk role clears the admin one it replaced', (
      tester,
    ) async {
      // The half-finished state this suite guards against left the smaller
      // roles on admin tokens. Each kiosk role below is the counterpart of an
      // admin one and must read LARGER — otherwise a kiosk screen has quietly
      // slid back to desk scale.
      expect(
        size(DesignConstants.kioskDisplay),
        greaterThan(size(DesignConstants.h1)),
      );
      expect(
        size(DesignConstants.kioskTitle),
        greaterThan(size(DesignConstants.h2)),
      );
      expect(
        size(DesignConstants.kioskLabel),
        greaterThan(size(DesignConstants.h3)),
      );
      expect(
        size(DesignConstants.kioskBody),
        greaterThan(size(DesignConstants.p)),
      );
      expect(
        size(DesignConstants.kioskCaption),
        greaterThan(size(DesignConstants.p)),
      );
      expect(
        size(DesignConstants.kioskSubtitle),
        greaterThan(size(DesignConstants.pBig)),
      );
      // The kiosk's own secondary button label clears the admin button label
      // (`h3`) — the rung the founder's "Get it" complaint landed on.
      expect(
        size(DesignConstants.kioskButtonOutlineLabel),
        greaterThan(size(DesignConstants.h3)),
      );
    });

    testWidgets('the admin ramp is untouched by the kiosk', (tester) async {
      // A kiosk change must never leak onto the admin surfaces.
      expect(DesignConstants.h1.fontSize, 24);
      expect(DesignConstants.h2.fontSize, 16);
      expect(DesignConstants.h3.fontSize, 13);
      expect(DesignConstants.p.fontSize, 12);
      expect(DesignConstants.pBig.fontSize, 16);
      expect(DesignConstants.pSmall.fontSize, 11);
      expect(DesignConstants.big2.fontSize, 32);
    });
  });

  group('kiosk contrast', () {
    testWidgets('no kiosk type token carries the sub-AA muted ink', (
      tester,
    ) async {
      // `text3rd` (#878D99) measures 3.05:1 on the ground — under the 4.5:1
      // WCAG AA floor PRODUCT.md holds as a hard requirement. It survives on
      // kiosk surfaces only for NON-text (hairlines, the return timer's drain
      // bar, placeholder glyphs); no token that renders WORDS may carry it.
      ladder().forEach((name, style) {
        expect(
          style.color,
          isNot(DesignConstants.text3rd),
          reason: '$name carries words — muted kiosk text is text2nd',
        );
      });
    });

    testWidgets('the kiosk eyebrow reads on text2nd', (tester) async {
      expect(DesignConstants.kioskEyebrow.color, DesignConstants.text2nd);
    });
  });
}
