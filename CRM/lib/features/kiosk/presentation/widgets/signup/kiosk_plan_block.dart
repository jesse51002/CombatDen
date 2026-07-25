import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_plan_block_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';

/// The answer behind a plan card the member cannot pick — ONE popup, whichever
/// reason closed it.
///
/// Two reasons ride it today: a trial they have already had (a kiosk-only rule,
/// one trial to a member, and the desk is still the override) and a RECURRING
/// plan they already hold (the backend's own per-plan conflict, which would
/// otherwise dead-end the whole signup on the review). A second modal for the
/// second reason would fork the kiosk's one modal vocabulary, so the reason —
/// not the popup — is what varies; every string and the glyph come from
/// `kiosk_plan_block_copy.dart`.
///
/// It is the kiosk's one modal vocabulary — the veil + centred popup card the
/// decline screen wears — over the warm [DesignConstants.yellowDark] disc every
/// handoff uses. Warm, never red: nothing is broken and nobody did anything
/// wrong.
///
/// **The plan grid stays live behind it**, so "Pick a membership" is a dismiss
/// rather than a navigation — nothing re-fetches and no scroll position is
/// lost. The blocked plan was never selected, so nothing has to be undone.
///
/// **The countdown is inside the popup, and it is not a cooldown.** This is a
/// shared community iPad: no screen may hold it forever, and a timer drawn
/// behind a popup sneaks the surface away without the member seeing it go.
class KioskPlanBlock extends StatelessWidget {
  const KioskPlanBlock({super.key});

  @override
  Widget build(BuildContext context) {
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
                // The card's containment from the screen edge — a Padding,
                // never a `margin`: a margin is a gap, and a gap belongs to the
                // parent's `spacing:`. It matches the decline popup's inset,
                // which is the surface this one is composed from.
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
                          style: DesignConstants.kioskPanelTitle,
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          kioskPlanBlockBody(state, reason),
                          style: DesignConstants.kioskBody.copyWith(
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

/// The constructive route first, the desk under it — stacked, matching the
/// decline popup: two kiosk-scale labels of this length do not sit comfortably
/// side by side in a [DesignConstants.dialogMaxWidth] popup.
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
        KioskPrimaryButton(text: 'Pick a membership', onPressed: onPick),
        KioskOutlineButton(text: 'Get help at the desk', onPressed: onHelp),
      ],
    );
  }
}

/// The warm disc the kiosk's other handoffs wear, carrying the reason's own
/// glyph.
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
