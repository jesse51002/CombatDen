import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans/picked_membership_card.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans/plans_already_has.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans/plans_grid.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The plans step's body: what this person already holds, the memberships
/// picked for them so far, then the catalogue.
///
/// It sits on the GROUND at the form measure rather than inside a
/// `FlowFormPanel` — the picked cards are objects in their own right and a
/// white panel around a grid of white cards reads as a form containing a form.
class PlansBody extends StatelessWidget {
  final MembershipWizardState state;
  final MembershipWizardCubit cubit;
  final String memberId;
  final String firstName;
  final String? blockedNote;
  final ValueChanged<MembershipPlanResponse> onBlocked;

  const PlansBody({
    super.key,
    required this.state,
    required this.cubit,
    required this.memberId,
    required this.firstName,
    required this.blockedNote,
    required this.onBlocked,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final held = state.currentMembershipsOf(memberId);
    final drafts = state.currentDrafts;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: scale.formMeasure),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            if (held.isNotEmpty) PlansAlreadyHas(memberships: held),
            for (var i = 0; i < drafts.length; i++)
              PickedMembershipCard(
                cubit: cubit,
                discounts: state.discounts,
                cart: state.config.cart,
                draft: drafts[i],
                index: i + 1,
                total: drafts.length,
                memberId: memberId,
                firstName: firstName,
              ),
            if (held.isNotEmpty || drafts.isNotEmpty) const Hairline(),
            PlansGrid(
              state: state,
              memberId: memberId,
              blockedNote: blockedNote,
              onPick: cubit.togglePlan,
              onBlocked: onBlocked,
            ),
          ],
        ),
      ),
    );
  }
}
