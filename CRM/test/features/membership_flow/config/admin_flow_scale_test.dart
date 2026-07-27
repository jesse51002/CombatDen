import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';

/// The desk ramp.
///
/// Two properties matter and they pull against each other. The admin scale
/// must resolve to the app's OWN ladder wherever the app has a rung — a flow
/// that quietly invents its own sizes is a second design system — and it must
/// stay a full step under the kiosk everywhere, or the desk dialog reads as an
/// iPad screen shrunk into a browser.
///
/// `testWidgets` only because the tokens resolve their family through
/// `GoogleFonts.geist()` and the binding absorbs that fetch; nothing pumps.
void main() {
  const admin = MembershipFlowScale.admin();
  const kiosk = MembershipFlowScale.kiosk();

  double size(TextStyle style) {
    final value = style.fontSize;
    expect(value, isNotNull, reason: 'every flow role pins a fontSize');
    return value!;
  }

  group('the admin scale resolves to the app\'s own ladder', () {
    testWidgets('every role that HAS an admin rung takes it', (tester) async {
      expect(admin.display, DesignConstants.h1);
      expect(admin.total, DesignConstants.big2);
      expect(admin.subtitle, DesignConstants.pBig);
      expect(admin.metric, DesignConstants.h1);
      expect(admin.panelTitle, DesignConstants.h2);
      expect(admin.fieldText, DesignConstants.pBig);
      expect(admin.title, DesignConstants.h2);
      expect(admin.body, DesignConstants.pBig);
      expect(admin.label, DesignConstants.h3);
      expect(admin.sectionText, DesignConstants.p);
      expect(admin.caption, DesignConstants.p);
      expect(admin.micro, DesignConstants.pSmall);
    });

    testWidgets('the roles the admin ladder LACKS take the flow tokens', (
      tester,
    ) async {
      expect(admin.statement, DesignConstants.flowStatement);
      expect(admin.name, DesignConstants.flowName);
      expect(admin.buttonPrimaryLabel, DesignConstants.flowButtonLabel);
      expect(admin.buttonOutlineLabel, DesignConstants.flowButtonLabel);
      expect(admin.buttonGhostLabel, DesignConstants.flowButtonGhostLabel);
      expect(
        admin.buttonPrimaryPadding,
        DesignConstants.flowButtonPrimaryPadding,
      );
      expect(
        admin.buttonOutlinePadding,
        DesignConstants.flowButtonOutlinePadding,
      );
      expect(admin.buttonGhostPadding, DesignConstants.flowButtonGhostPadding);
    });

    testWidgets('eyebrow and tag stay the SHARED tokens on both surfaces', (
      tester,
    ) async {
      expect(admin.eyebrow, DesignConstants.eyebrow);
      expect(admin.tag, DesignConstants.tag);
      expect(kiosk.eyebrow, DesignConstants.eyebrow);
      expect(kiosk.tag, DesignConstants.tag);
    });

    testWidgets('both surfaces cap a form at the one shared measure', (
      tester,
    ) async {
      expect(admin.formMeasure, DesignConstants.flowFormMeasure);
      expect(kiosk.formMeasure, DesignConstants.flowFormMeasure);
    });
  });

  group('the desk reads at desk distance', () {
    testWidgets('no admin role out-sizes its kiosk counterpart', (
      tester,
    ) async {
      final pairs = <String, List<TextStyle>>{
        'display': [admin.display, kiosk.display],
        'total': [admin.total, kiosk.total],
        'subtitle': [admin.subtitle, kiosk.subtitle],
        'metric': [admin.metric, kiosk.metric],
        'panelTitle': [admin.panelTitle, kiosk.panelTitle],
        'statement': [admin.statement, kiosk.statement],
        'fieldText': [admin.fieldText, kiosk.fieldText],
        'title': [admin.title, kiosk.title],
        'name': [admin.name, kiosk.name],
        'body': [admin.body, kiosk.body],
        'label': [admin.label, kiosk.label],
        'caption': [admin.caption, kiosk.caption],
        'buttonPrimaryLabel': [
          admin.buttonPrimaryLabel,
          kiosk.buttonPrimaryLabel,
        ],
        'buttonOutlineLabel': [
          admin.buttonOutlineLabel,
          kiosk.buttonOutlineLabel,
        ],
        'buttonGhostLabel': [admin.buttonGhostLabel, kiosk.buttonGhostLabel],
      };
      pairs.forEach((role, styles) {
        expect(
          size(styles[0]),
          lessThan(size(styles[1])),
          reason: '$role at the desk must read under the kiosk\'s — a role '
              'that catches up has quietly put an iPad size in a dialog',
        );
      });
    });

    testWidgets('the desk escape is demoted by weight, never by shrinking', (
      tester,
    ) async {
      expect(
        size(admin.buttonGhostLabel),
        size(admin.buttonOutlineLabel),
        reason: 'the way out of a purchase stays the same size as the '
            'secondary action',
      );
      expect(
        admin.buttonGhostLabel.fontWeight!.value,
        lessThan(admin.buttonOutlineLabel.fontWeight!.value),
      );
      expect(admin.buttonGhostLabel.color, DesignConstants.text2nd);
    });

    testWidgets('no desk button label out-sizes a desk heading', (
      tester,
    ) async {
      for (final heading in <TextStyle>[
        admin.display,
        admin.total,
        admin.statement,
      ]) {
        expect(size(admin.buttonPrimaryLabel), lessThan(size(heading)));
        expect(size(admin.buttonOutlineLabel), lessThan(size(heading)));
        expect(size(admin.buttonGhostLabel), lessThan(size(heading)));
      }
    });

    testWidgets('the desk ladder descends where the design says it does', (
      tester,
    ) async {
      // The money total is the biggest thing on the review — staff read it
      // back to the person paying, so it deliberately out-ranks the step head.
      expect(size(admin.total), greaterThan(size(admin.display)));
      expect(size(admin.display), greaterThan(size(admin.statement)));
      expect(size(admin.statement), greaterThan(size(admin.name)));
      expect(size(admin.name), greaterThan(size(admin.label)));
      expect(size(admin.label), greaterThan(size(admin.caption)));
    });
  });

  group('the new tokens are ADDITIVE', () {
    testWidgets('the desk roles carry the sizes the mockups specify', (
      tester,
    ) async {
      expect(DesignConstants.flowStatement.fontSize, 17);
      expect(DesignConstants.flowStatement.fontWeight, FontWeight.w600);
      expect(DesignConstants.flowName.fontSize, 15);
      expect(DesignConstants.flowName.fontWeight, FontWeight.w600);
      expect(DesignConstants.flowButtonLabel.fontSize, 14);
      expect(DesignConstants.flowButtonLabel.fontWeight, FontWeight.w600);
      expect(
        DesignConstants.flowButtonPrimaryPadding,
        const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
      );
    });

    testWidgets('no new token carries the sub-AA muted ink', (tester) async {
      // Same floor the kiosk holds: `text3rd` measures under 4.5:1, and every
      // one of these renders WORDS.
      for (final style in <TextStyle>[
        DesignConstants.flowStatement,
        DesignConstants.flowName,
        DesignConstants.flowButtonLabel,
        DesignConstants.flowButtonGhostLabel,
      ]) {
        expect(style.color, isNot(DesignConstants.text3rd));
      }
    });

    testWidgets('the admin ramp itself is untouched', (tester) async {
      // The kiosk ramp asserts the same thing from its side; adding desk roles
      // must not move the app's own ladder either.
      expect(DesignConstants.h1.fontSize, 24);
      expect(DesignConstants.h2.fontSize, 16);
      expect(DesignConstants.h3.fontSize, 13);
      expect(DesignConstants.p.fontSize, 12);
      expect(DesignConstants.pBig.fontSize, 16);
      expect(DesignConstants.pSmall.fontSize, 11);
      expect(DesignConstants.big2.fontSize, 32);
    });
  });
}
