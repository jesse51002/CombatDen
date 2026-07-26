import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/review/review_lineup_panel.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/review/review_money_side.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/shared/wizard_step_foot.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/who/who_consequence_notice.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_actions.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_step_scaffold.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_who_for.dart';

/// Frame 7 — the lineup and what it costs, on one screen.
///
/// Left is who is getting what, right is the money, and the proration control
/// sits ON the money panel where flipping it visibly moves DUE TODAY. The two
/// used to be separate steps, which is how the old flow ended up promising
/// "prices on the next step" directly above a live price on every row.
///
/// The whole screen is at the surface's form measure: the two halves are read
/// against each other, so a lineup running the full width of a wide dialog
/// would put the row and its price at opposite ends of the desk.
class WizardReviewStep extends StatelessWidget {
  final bool showAddMemberGroup;
  final WizardActions actions;

  const WizardReviewStep({
    super.key,
    required this.showAddMemberGroup,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MembershipWizardCubit>();
    // Removing a membership drops the staged price with it (a stale figure
    // beside a live cart is how a payer is quoted one number and charged
    // another) and RE-STAGES it, in the cubit — what a changed cart costs is
    // the money layer's question, so this screen only renders the answer.
    return BlocBuilder<MembershipWizardCubit, MembershipWizardState>(
      builder: (context, state) {
        final copy = MembershipFlowTheme.copyOf(context);
        final scale = MembershipFlowTheme.of(context);
        return WizardStepScaffold(
          step: MembershipWizardStep.reviewCharges,
          hasWaivers: state.hasWaivers,
          showAddMemberGroup: showAddMemberGroup,
          title: copy.reviewStepTitle,
          subtitle: copy.reviewStepSubtitle(isGroup: state.people.length > 1),
          identity: FlowWhoFor(
            eyebrow: WizardReviewCopy.billedToEyebrow,
            name: state.payer.name,
          ),
          foot: WizardStepFoot(
            note: _footNote(state),
            onEscape: actions.close,
            onBack: cubit.canGoBack ? cubit.back : null,
            // The amount only rides the button once the SERVER has named it —
            // a `$0.00` printed over a price nobody could work out is a lie
            // staff would read back to the payer.
            primaryLabel: state.previewLoad.isReady
                ? WizardReviewCopy.primary(
                    formatMinorUnits(
                      state.dueTodayMinor,
                      currency: state.currency,
                    ),
                  )
                : WizardReviewCopy.primaryUnpriced,
            onPrimary: state.canAdvance ? () => _advance(cubit) : null,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: scale.formMeasure),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingLarge,
                children: [
                  // What the trash can just dropped, in the roster step's own
                  // words — the same control exists there, and one drop must
                  // not be described two ways. Leaving the step forward
                  // answers it (see the primary below), so it carries no
                  // dismiss of its own.
                  if (state.lastConsequence case final dropped?)
                    WhoConsequenceNotice(consequence: dropped),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: DesignConstants.spacingLarge,
                    children: [
                      Expanded(
                        child: WizardReviewLineupPanel(
                          state: state,
                          onEdit: cubit.editFromReview,
                          onRemove: cubit.removeMembership,
                        ),
                      ),
                      Expanded(
                        child: WizardReviewMoneySide(
                          state: state,
                          onProration: cubit.setProration,
                          onRetryPreview: cubit.retryPreview,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The line under the foot's hairline, answering whichever thing is holding
  /// the primary closed.
  String? _footNote(MembershipWizardState state) {
    if (!state.hasAnyMembership) return WizardReviewCopy.nothingLeft;
    if (state.previewLoad.isFailed) return WizardReviewCopy.chargesFailedFoot;
    return null;
  }

  /// Leaving forward answers the consequence notice: it is a statement about
  /// the lineup being left behind, and it must not be waiting on the way back
  /// in. The roster step's own footer does exactly this.
  void _advance(MembershipWizardCubit cubit) {
    cubit.clearConsequence();
    cubit.next();
  }
}
