import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/who/who_add_group.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/who/who_consequence_notice.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/who/who_foot.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/who/who_load_failed.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/who/who_paying_group.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/who/who_roster_group.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_actions.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_step_scaffold.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_form_panel.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Step 1 — the merged roster: who is joining, and who pays for all of them.
///
/// It is the old `payer` and `members` steps in one, because they were two
/// answers to the same question and splitting them is what put two identically
/// worded adder pairs on two screens pointing in opposite directions. Here
/// there is one roster, one adder pair, and who pays is a control on it.
class WizardWhoStep extends StatelessWidget {
  final bool showAddMemberGroup;
  final WizardActions actions;

  const WizardWhoStep({
    super.key,
    required this.showAddMemberGroup,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MembershipWizardCubit>();
    return BlocBuilder<MembershipWizardCubit, MembershipWizardState>(
      builder: (context, state) {
        final copy = MembershipFlowTheme.copyOf(context);
        final failed = state.payerLoad.isFailed;
        final waiting = state.payerLoad.isLoading && state.payerDetail == null;
        return WizardStepScaffold(
          step: MembershipWizardStep.who,
          hasWaivers: state.hasWaivers,
          showAddMemberGroup: showAddMemberGroup,
          title: copy.rosterStepTitle,
          // The answering line explains the roster; a screen showing a failure
          // or a spinner instead has no roster to explain.
          subtitle: failed || waiting ? null : copy.rosterStepSubtitle,
          foot: WhoFoot(
            state: state,
            cubit: cubit,
            onEscape: actions.close,
          ),
          child: switch ((failed, waiting)) {
            (true, _) => WhoLoadFailed(
                payerName: state.payer.name,
                onRetry: cubit.retryPayerDetail,
              ),
            (_, true) => const _Waiting(),
            _ => _Roster(state: state, cubit: cubit, actions: actions),
          },
        );
      },
    );
  }
}

/// The panel, with whatever the last destructive control dropped stated above
/// it. The notice is answered by the next roster action rather than by a
/// button of its own — every control that can follow it either replaces the
/// consequence or clears it.
class _Roster extends StatelessWidget {
  final MembershipWizardState state;
  final MembershipWizardCubit cubit;
  final WizardActions actions;

  const _Roster({
    required this.state,
    required this.cubit,
    required this.actions,
  });

  /// The consequence notice has no dismiss of its own, so the next control
  /// staff reach for answers it. The roster's own checks already replace or
  /// clear the consequence in the cubit; these three open a dialog instead, so
  /// they clear it on the way.
  VoidCallback _answered(VoidCallback action) => () {
        cubit.clearConsequence();
        action();
      };

  @override
  Widget build(BuildContext context) {
    final consequence = state.lastConsequence;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (consequence != null)
          WhoConsequenceNotice(consequence: consequence),
        FlowFormPanel(
          children: [
            WhoRosterGroup(state: state, cubit: cubit),
            WhoPayingGroup(
              payerName: state.payer.name,
              onChangePayer: _answered(actions.changePayer),
            ),
            WhoAddGroup(
              payerName: state.payer.name,
              onAddNew: _answered(actions.addNewMember),
              onLinkExisting: _answered(actions.linkMember),
            ),
          ],
        ),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(child: AppSpinner()),
    );
  }
}

