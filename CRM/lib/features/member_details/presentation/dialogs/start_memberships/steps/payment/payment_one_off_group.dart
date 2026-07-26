import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_request.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/shared/wizard_pill.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_detail_group.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_card_chip.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// A card entered at the desk for today's one-time invoice only — never saved
/// to a profile, never made the default.
///
/// **Blocked, not hidden.** The old wizard silently ignored a captured
/// one-off card the moment the cart turned recurring or cash went on: staff
/// saw a card chip they had typed in and a charge that never touched it. Here
/// the group always renders, its controls dim, and a warm notice names the
/// reason AND both ways out — because a control that vanishes teaches nobody
/// why, and one that lies about paying is worse.
class WizardPaymentOneOffGroup extends StatelessWidget {
  /// How far the blocked controls are pulled back. Enough to read as inactive
  /// beside the live groups above, not so far that the card staff typed in
  /// becomes unreadable — they still have to be able to see and remove it.
  static const double _blockedOpacity = 0.45;

  final CustomCardCapture? card;

  /// Why the card cannot pay, or null when it is what settles today.
  final OneOffCardBlock? block;

  final VoidCallback onCapture;
  final VoidCallback onRemove;

  const WizardPaymentOneOffGroup({
    super.key,
    required this.card,
    required this.block,
    required this.onCapture,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final blocked = block;
    return FlowDetailGroup(
      eyebrow: WizardPaymentCopy.oneOffEyebrow,
      children: [
        if (blocked != null)
          Align(
            alignment: Alignment.centerLeft,
            child: WizardPill(
              label: WizardPaymentCopy.notUsableTag,
              tone: WizardPillTone.warm,
            ),
          ),
        Opacity(
          // Dimmed rather than removed: the card staff entered is still there
          // and still removable, it simply is not what pays.
          opacity: blocked == null ? 1 : _blockedOpacity,
          child: _Controls(
            card: card,
            onCapture: onCapture,
            onRemove: onRemove,
          ),
        ),
        if (blocked != null)
          FlowInlineNotice(message: _reason(blocked)),
      ],
    );
  }

  /// One sentence per blocker, each naming the cause and both fixes. The
  /// wording is the copy's; only the CHOICE is made here.
  String _reason(OneOffCardBlock blocked) => switch (blocked) {
        OneOffCardBlock.paidWithCash => WizardPaymentCopy.oneOffBlockedByCash,
        OneOffCardBlock.cartHasRecurring =>
          WizardPaymentCopy.oneOffBlockedByRecurring,
        OneOffCardBlock.cartHasNoOneTime =>
          WizardPaymentCopy.oneOffBlockedByNoOneTime,
      };
}

class _Controls extends StatelessWidget {
  final CustomCardCapture? card;
  final VoidCallback onCapture;
  final VoidCallback onRemove;

  const _Controls({
    required this.card,
    required this.onCapture,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final held = card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (held == null)
          Align(
            alignment: Alignment.centerLeft,
            child: AppOutlineButton(
              text: WizardPaymentCopy.useOneOffCard,
              onPressed: onCapture,
              textStyle: scale.buttonOutlineLabel,
            ),
          )
        else ...[
          Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              FlowCardChip(brand: held.brand, last4: held.lastFour),
              const Spacer(),
              AppOutlineButton(
                text: WizardPaymentCopy.changeCard,
                onPressed: onCapture,
                textStyle: scale.buttonOutlineLabel,
              ),
              AppOutlineButton(
                text: WizardPaymentCopy.removeCard,
                onPressed: onRemove,
                textStyle: scale.buttonOutlineLabel,
                borderColor: DesignConstants.badRed,
                textColor: DesignConstants.badRed,
              ),
            ],
          ),
          Text(
            WizardPaymentCopy.oneOffNote,
            style: scale.caption.copyWith(color: DesignConstants.text2nd),
          ),
        ],
      ],
    );
  }
}
