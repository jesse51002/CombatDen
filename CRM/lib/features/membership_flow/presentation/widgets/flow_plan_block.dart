import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_plan_block_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_buttons.dart';

/// The answer behind a plan card the member cannot pick — ONE popup, whichever
/// reason closed it.
///
/// Two client-side rules close a card, both read off the member's own history:
/// a trial they have already had (kiosk-only, one trial to a member — staff can
/// still grant a repeat from the CRM) and a RECURRING plan they already hold
/// (per plan, mirroring the backend's own conflict guard, which would otherwise
/// dead-end the signup at the review). The reason varies, never the popup:
/// every string and the glyph come from `kiosk_plan_block_copy.dart`.
///
/// Warm [DesignConstants.yellowDark], never red — nothing is broken and nobody
/// did anything wrong. The grid stays live behind it, so "Pick a membership"
/// dismisses rather than navigates; the blocked plan was never selected, so
/// nothing has to be undone. The countdown sits INSIDE the popup and is not a
/// cooldown: no screen may hold a shared iPad forever, and a timer drawn behind
/// a popup would take the surface away unseen.
class FlowPlanBlock extends StatelessWidget {
  const FlowPlanBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.popupCountdown != cur.popupCountdown ||
          prev.planBlockActive != cur.planBlockActive ||
          prev.activePersonIndex != cur.activePersonIndex ||
          prev.persons != cur.persons ||
          prev.isGroup != cur.isGroup,
      builder: (context, state) {
        final reason = state.planBlockActive;
        if (reason == null) return const SizedBox.shrink();
        return SizedBox.expand(
          child: ColoredBox(
            color: DesignConstants.backgroundColor.withValues(alpha: 0.92),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignConstants.dialogMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(DesignConstants.spacingLarge),
                  child: Container(
                    padding: const EdgeInsets.all(DesignConstants.paddingBig),
                    decoration: BoxDecoration(
                      color: DesignConstants.popup,
                      borderRadius:
                          BorderRadius.circular(DesignConstants.radiusCard),
                      border: Border.all(color: DesignConstants.line),
                      boxShadow: DesignConstants.cardShadow,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: DesignConstants.spacingLarge,
                      children: [
                        _BlockIcon(reason: reason),
                        Text(
                          kioskPlanBlockTitle(reason),
                          style: scale.panelTitle,
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          kioskPlanBlockBody(state, reason),
                          style: scale.body.copyWith(
                            color: DesignConstants.text2nd,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        _Actions(
                          onPick: cubit.dismissPlanBlock,
                          onHelp: cubit.planBlockHelp,
                        ),
                        KioskReturnTimer(
                          total: kKioskSignupPopupHold.inSeconds,
                          secondsLeft: state.popupCountdown,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The constructive route first, the desk under it — stacked, because two
/// kiosk-scale labels this long do not fit side by side in a
/// [DesignConstants.dialogMaxWidth] popup.
class _Actions extends StatelessWidget {
  final VoidCallback onPick;
  final VoidCallback onHelp;

  const _Actions({required this.onPick, required this.onHelp});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        FlowPrimaryButton(text: 'Pick a membership', onPressed: onPick),
        FlowOutlineButton(text: 'Get help at the desk', onPressed: onHelp),
      ],
    );
  }
}

/// The warm disc the kiosk's handoffs wear, carrying the reason's own glyph.
class _BlockIcon extends StatelessWidget {
  final KioskPlanBlockReason reason;

  const _BlockIcon({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.yellowDark,
        shape: BoxShape.circle,
      ),
      child: Icon(
        kioskPlanBlockGlyph(reason),
        size: DesignConstants.iconSizeBig,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.okYellow,
      ),
    );
  }
}
