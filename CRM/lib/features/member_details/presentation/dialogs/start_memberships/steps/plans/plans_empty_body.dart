import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/empty_state.dart';

/// C1 — the gym has no plan carrying an active price, so there is nothing to
/// sell. Nothing failed, so it reads as a state rather than an error, and the
/// body carries the way out.
class PlansEmptyBody extends StatelessWidget {
  const PlansEmptyBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Symbols.sell_sharp,
      title: WizardPlansCopy.noPlansTitle,
      body: WizardPlansCopy.noPlansBody,
    );
  }
}

/// Every pick was taken back off, so the run has nobody left to price. It is
/// reachable from this step's own trash control, so it says so and points at
/// the roster instead of leaving a blank stage behind.
class PlansNobodyBody extends StatelessWidget {
  const PlansNobodyBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Symbols.group_sharp,
      title: WizardPlansCopy.nobodyTitle,
      body: WizardPlansCopy.nobodyBody,
    );
  }
}

/// The catalogue read did not land. Same shape, an error tone, and a retry —
/// a read that can fail must never render as an empty shelf.
class PlansFailedBody extends StatelessWidget {
  final VoidCallback onRetry;

  const PlansFailedBody({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    return EmptyState(
      icon: Symbols.sell_sharp,
      tone: EmptyStateTone.error,
      title: WizardPlansCopy.plansFailedTitle,
      body: WizardPlansCopy.plansFailedBody,
      action: AppOutlineButton(
        text: copy.retryAction,
        onPressed: onRetry,
        textStyle: scale.buttonOutlineLabel,
        borderWidth: DesignConstants.buttonBorder,
        icon: Icon(
          Symbols.refresh_sharp,
          size: DesignConstants.iconSizeSmall,
          weight: DesignConstants.iconWeight,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingLarge,
          vertical: DesignConstants.spacingMedium,
        ),
      ),
    );
  }
}
