import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/change_payer_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/change_payer_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_option_row.dart';

import '../../../bloc/membership_wizard/membership_wizard_fixtures.dart';

/// The payer switch, as the founder drove it.
///
/// Two bugs are pinned here, both found by using the live flow rather than by
/// reading it:
///
/// 1. Somebody already ON the run could not be picked as the payer. The dialog
///    listed the launch member and their authorized payers and nothing else, so
///    the only route to a person already on screen was a roster SEARCH for the
///    name being looked at.
/// 2. Authorizing somebody left the dialog unchanged. The candidate list was a
///    snapshot taken at `show()`, and `showDialog` builds outside the wizard's
///    subtree — so the cubit refreshed correctly and the dialog never heard.
///    Worse, the new payer was then SELECTED, pointing the answer at a row that
///    was not rendered, which is why it read as frozen rather than as stale.
///
/// Both tests fail without their fix; neither asserts on cubit state alone,
/// because state updating correctly is exactly what made bug 2 look fine.
void main() {
  late MockMemberRepository member;
  late MockMembershipsRepository memberships;

  setUpAll(registerWizardFallbacks);

  setUp(() {
    member = MockMemberRepository();
    memberships = MockMembershipsRepository();
    when(() => member.listMembershipPlans(any())).thenAnswer((_) async => []);
    when(() => member.listGymDiscounts(any())).thenAnswer((_) async => []);
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
    when(() => member.getMemberDetail(any())).thenAnswer(
      (_) async => detail(memberId: 'm-child', firstName: 'Ella'),
    );
  });

  /// Marcus opened the run and is paying; Ella is on the roster as a payee.
  /// Nobody is authorized to pay FOR Marcus yet.
  Future<MembershipWizardCubit> openRun() async {
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(
        authorizedToPayFor: [linked(memberId: 'm-child', firstName: 'Ella')],
      ),
      initialTrainingMemberIds: const {'m-child'},
    );
    await cubit.open();
    return cubit;
  }

  /// Mount a host whose one button opens the switch, so the dialog is pushed
  /// the way production pushes it — `showDialog`, outside the wizard subtree.
  /// That route is the whole substance of bug 2 and must not be shortcut.
  Future<void> pumpSwitch(
    WidgetTester tester, {
    required MembershipWizardCubit cubit,
    required Future<String?> Function(MembershipWizardPerson) onAuthorizeInRun,
    Future<String?> Function()? onLinkPayer,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ChangePayerDialog.show(
                context: context,
                cubit: cubit,
                launchMember: detail(),
                onCreatePayer: () async => null,
                onLinkPayer: onLinkPayer ?? () async => null,
                onAuthorizeInRun: onAuthorizeInRun,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(ChangePayerCopy.title), findsOneWidget);
  }

  Finder rowTitled(String title) =>
      find.widgetWithText(WizardOptionRow, title);

  testWidgets('BUG 1: somebody already in the run is offered as a payer, '
      'in a group of their own', (tester) async {
    final cubit = await openRun();
    await pumpSwitch(
      tester,
      cubit: cubit,
      onAuthorizeInRun: (_) async => null,
    );

    // The group heading exists, and Ella is under it — before the fix she
    // appeared nowhere and the heading did not exist at all.
    expect(find.text(ChangePayerCopy.inRunEyebrow), findsOneWidget);
    expect(rowTitled('Ella Bell'), findsOneWidget);
  });

  testWidgets('BUG 1: picking them authorizes FIRST, and only then answers '
      'the question', (tester) async {
    final cubit = await openRun();
    final asked = <String>[];
    await pumpSwitch(
      tester,
      cubit: cubit,
      onAuthorizeInRun: (person) async {
        asked.add(person.memberId);
        return person.memberId;
      },
    );

    await tester.tap(rowTitled('Ella Bell'));
    await tester.pumpAndSettle();

    // The signature was asked for, naming the person picked.
    expect(asked, ['m-child']);
    // And the switch can now be confirmed, which it could not before.
    final confirm = find.widgetWithText(
      ElevatedButton,
      ChangePayerCopy.confirm,
    );
    expect(
      tester.widgetList(confirm).isNotEmpty ||
          find.text(ChangePayerCopy.confirm).evaluate().isNotEmpty,
      isTrue,
    );
  });

  testWidgets('BUG 1: an authorization that is abandoned changes nothing',
      (tester) async {
    final cubit = await openRun();
    await pumpSwitch(
      tester,
      cubit: cubit,
      // Backing out of the agreement returns null.
      onAuthorizeInRun: (_) async => null,
    );

    await tester.tap(rowTitled('Ella Bell'));
    await tester.pumpAndSettle();

    // Still on the switch, still nobody new selected.
    expect(find.text(ChangePayerCopy.title), findsOneWidget);
    expect(cubit.state.payer.memberId, 'm-payer');
  });

  testWidgets('BUG 2: the list SHOWS a payer authorized while it was open',
      (tester) async {
    final cubit = await openRun();
    // Nobody is authorized yet, so the group does not exist.
    expect(cubit.state.payerCandidates, isEmpty);

    await pumpSwitch(
      tester,
      cubit: cubit,
      onAuthorizeInRun: (_) async => null,
      // What the real route does after a signature settles: re-read the launch
      // member's payers onto the run.
      onLinkPayer: () async {
        cubit.setPayerCandidates([
          linked(memberId: 'm-sam', firstName: 'Sam'),
        ]);
        return 'm-sam';
      },
    );

    expect(find.text(ChangePayerCopy.authorizedEyebrow), findsNothing);

    await tester.tap(rowTitled(ChangePayerCopy.linkTitle));
    await tester.pumpAndSettle();

    // The row RENDERS. Asserting the cubit alone would have passed before the
    // fix — the state was always right; the open dialog never rebuilt on it.
    expect(find.text(ChangePayerCopy.authorizedEyebrow), findsOneWidget);
    expect(rowTitled('Sam Bell'), findsOneWidget);
  });

  testWidgets('nobody is listed twice once they are authorized',
      (tester) async {
    final cubit = await openRun();
    // Ella is BOTH on the roster and now an authorized payer.
    cubit.setPayerCandidates([
      linked(memberId: 'm-child', firstName: 'Ella'),
    ]);

    await pumpSwitch(
      tester,
      cubit: cubit,
      onAuthorizeInRun: (_) async => null,
    );

    // One row, under "already authorized" — not a second under "also in this
    // run", and no second signature asked of a pair the gym already holds an
    // agreement for.
    expect(rowTitled('Ella Bell'), findsOneWidget);
    expect(find.text(ChangePayerCopy.inRunEyebrow), findsNothing);
    expect(cubit.state.unauthorizedRosterPayers, isEmpty);
  });
}
