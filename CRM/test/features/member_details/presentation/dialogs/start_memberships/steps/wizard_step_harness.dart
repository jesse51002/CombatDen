import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_actions.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/config/staff_flow_copy.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_buttons.dart';

/// How the six wizard steps are mounted for a widget test, and how the host
/// actions they fire are recorded.
///
/// Every step is a plain `StatelessWidget`/`StatefulWidget` over the cubit, so
/// a test drives the CUBIT with its own public methods and asserts what the
/// step renders. State is never hand-constructed: the derived getters are the
/// point, and a hand-built state can be one the cubit could never produce.

/// The seven host callbacks, each counted, so a test can assert WHICH one a
/// control fired rather than that something happened.
class RecordedWizardActions {
  int closed = 0;
  int addedNewMember = 0;
  int linkedMember = 0;
  int changedPayer = 0;
  int updatedSavedCard = 0;
  int capturedOneOffCard = 0;

  /// The member ids the receipt's rows asked to open, in tap order.
  final List<String> viewedMembers = <String>[];

  late final WizardActions actions = WizardActions(
    close: () => closed++,
    viewMember: viewedMembers.add,
    addNewMember: () => addedNewMember++,
    linkMember: () => linkedMember++,
    changePayer: () => changedPayer++,
    updateSavedCard: () => updatedSavedCard++,
    captureOneOffCard: () => capturedOneOffCard++,
  );
}

/// Mount one step the way `StartMembershipsWizard` does: the cubit above it,
/// and ONE scale plus ONE voice above that.
///
/// [size] is the desk dialog's own measure — `WizardStepScaffold`'s shell uses
/// `Expanded`, so the step needs a bounded height or it cannot lay out at all.
///
/// Animations are disabled through the MediaQuery rather than left running:
/// the shared `AppSpinner` repeats forever, and `pumpAndSettle` can never
/// settle against a looping animation — three of these steps render one.
Future<void> pumpWizardStep(
  WidgetTester tester, {
  required MembershipWizardCubit cubit,
  required Widget step,
  Size size = const Size(1100, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: BlocProvider<MembershipWizardCubit>.value(
          value: cubit,
          child: MembershipFlowTheme(
            scale: const MembershipFlowScale.admin(),
            copy: const StaffFlowCopy(),
            child: step,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The foot's primary button, by its rendered words — `onPressed == null` is
/// how every step says "this cannot be left forwards yet".
FlowPrimaryButton wizardPrimary(WidgetTester tester, String label) =>
    tester.widget<FlowPrimaryButton>(
      find.widgetWithText(FlowPrimaryButton, label),
    );

/// The desk's own voice, for tests that assert a shared component's wording
/// rather than restating it.
const StaffFlowCopy staffCopy = StaffFlowCopy();
