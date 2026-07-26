import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/create_invite_actions.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// The invite-or-not footer. Two things are load-bearing and easy to break:
/// the two commits must stay EQUALLY prominent (no default to click through),
/// and the three-button row must fit the narrow dialog it lives in.
void main() {
  Widget wrap(Widget child, {double width = DesignConstants.dialogMaxWidth}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    );
  }

  testWidgets(
    'offers BOTH commits with the same treatment — neither is the default',
    (t) async {
      var asked = <bool>[];
      await t.pumpWidget(wrap(CreateInviteActions(
        createLabel: 'Add',
        onCreate: asked.add,
        onCancel: () {},
      )));

      expect(find.text('Add & invite'), findsOneWidget);
      expect(find.text('Add without inviting'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // Same widget type for both commits: one is not visually demoted into
      // the "are you sure" slot, which is what a default looks like.
      expect(find.byType(AppPrimaryButton), findsNWidgets(2));

      await t.tap(find.text('Add without inviting'));
      await t.tap(find.text('Add & invite'));
      expect(asked, [false, true]);
    },
  );

  testWidgets(
    'fits BOTH the narrow and the wide dialog without overflowing',
    (t) async {
      // Side by side the two commits need ~684px, so the narrow surface must
      // stack them rather than overflow. The longest labels are exercised.
      for (final width in [
        DesignConstants.dialogMaxWidth,
        DesignConstants.dialogMaxWidthWide,
      ]) {
        await t.pumpWidget(wrap(
          CreateInviteActions(
            createLabel: 'Create',
            onCreate: (_) {},
            onCancel: () {},
          ),
          width: width,
        ));
        expect(t.takeException(), isNull, reason: 'overflowed at $width');
        // Both commits stay reachable at either width.
        expect(find.text('Create & invite'), findsOneWidget);
        expect(find.text('Create without inviting'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'with nobody to invite it collapses to a single plain commit',
    (t) async {
      final asked = <bool>[];
      await t.pumpWidget(wrap(CreateInviteActions(
        createLabel: 'Create',
        canInvite: false,
        onCreate: asked.add,
        onCancel: () {},
      )));

      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Create & invite'), findsNothing);
      expect(find.text('Create without inviting'), findsNothing);

      await t.tap(find.text('Create'));
      // A create with no email never asks for an invite.
      expect(asked, [false]);
    },
  );

  testWidgets('a create in flight makes every choice inert', (t) async {
    final asked = <bool>[];
    await t.pumpWidget(wrap(CreateInviteActions(
      createLabel: 'Create',
      busy: true,
      onCreate: asked.add,
      onCancel: () {},
    )));

    await t.tap(find.text('Create without inviting'));
    expect(asked, isEmpty);
  });
}
