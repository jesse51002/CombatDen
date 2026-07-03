import 'package:flutter/material.dart';

import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_step.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// The wizard's footer actions: the step-dependent primary
/// label (Next / Next member / Review / Preview charges /
/// Continue to payment / Pay / Done) and the Cancel/Back
/// secondary. Which callback the primary fires is decided
/// by the step here; enabling, loading, navigation and the
/// actual mutations stay with the orchestrator.
class StartMembershipsFooter extends StatelessWidget {
  final StartMembershipsStep step;

  /// True when another selected member still needs
  /// configuring after the current one — drives the
  /// discounts step's "Next member" vs "Review" label.
  final bool hasNextMember;

  /// True while editing one member's lineup from the review
  /// step — the discounts step then returns straight to
  /// review instead of walking to the next member.
  final bool isEditing;
  final bool canAdvance;
  final bool isStarting;
  final VoidCallback onNext;
  final VoidCallback onPay;
  final VoidCallback onBack;

  const StartMembershipsFooter({
    super.key,
    required this.step,
    required this.hasNextMember,
    required this.isEditing,
    required this.canAdvance,
    required this.isStarting,
    required this.onNext,
    required this.onPay,
    required this.onBack,
  });

  bool get _atFirst =>
      step == StartMembershipsStep.payer;

  bool get _atResults =>
      step == StartMembershipsStep.results;

  String get _primaryLabel {
    switch (step) {
      case StartMembershipsStep.payer:
      case StartMembershipsStep.members:
      case StartMembershipsStep.plans:
        return 'Next';
      case StartMembershipsStep.discounts:
        if (isEditing) return 'Back to review';
        return hasNextMember ? 'Next member' : 'Review';
      case StartMembershipsStep.review:
        return 'Preview charges';
      case StartMembershipsStep.signWaivers:
        return 'Preview charges';
      case StartMembershipsStep.preview:
        return 'Continue to payment';
      case StartMembershipsStep.payment:
        return 'Pay';
      case StartMembershipsStep.results:
        return 'Done';
    }
  }

  void _onPrimary(BuildContext context) {
    switch (step) {
      case StartMembershipsStep.payment:
        onPay();
      case StartMembershipsStep.results:
        Navigator.of(context).pop();
      default:
        onNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialogActions(
      primaryLabel: _primaryLabel,
      isLoading: _atResults && isStarting,
      primaryOnPressed: canAdvance
          ? () => _onPrimary(context)
          : null,
      secondaryLabel: _atResults
          ? null
          : (_atFirst ? 'Cancel' : 'Back'),
      secondaryOnPressed: _atFirst
          ? () => Navigator.of(context).pop()
          : onBack,
    );
  }
}
