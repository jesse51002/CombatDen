import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';

/// "You've already had a trial" — the answer behind a plan card the member
/// cannot pick.
///
/// **Trials are one to a member AT THE KIOSK.** Any trial in their history
/// closes every trial plan on the grid, not just the one they took. Staff can
/// still grant a repeat trial from the CRM; this is a self-serve rule, and the
/// desk is the override the second button offers.
///
/// It is the kiosk's one modal vocabulary — the veil + centred popup card the
/// decline screen wears — over the warm [DesignConstants.yellowDark] disc every
/// handoff uses. Warm, never red: nothing is broken and nobody did anything
/// wrong. The history glyph states the fact rather than the stop screen's
/// person glyph, which is about WHO the member is.
///
/// **The plan grid stays live behind it**, so "Pick a membership" is a dismiss
/// rather than a navigation — nothing re-fetches and no scroll position is
/// lost. The blocked plan was never selected, so nothing has to be undone.
///
/// **The countdown is inside the popup, and it is not a cooldown.** This is a
/// shared community iPad: no screen may hold it forever, and a timer drawn
/// behind a popup sneaks the surface away without the member seeing it go.
class KioskTrialBlock extends StatelessWidget {
  const KioskTrialBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.popupCountdown != cur.popupCountdown ||
          prev.activePersonIndex != cur.activePersonIndex ||
          prev.persons != cur.persons ||
          prev.isGroup != cur.isGroup,
      builder: (context, state) {
        return SizedBox.expand(
          child: ColoredBox(
            color: DesignConstants.backgroundColor.withValues(alpha: 0.92),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignConstants.dialogMaxWidth,
                ),
                child: Container(
                  margin: const EdgeInsets.all(DesignConstants.spacingLarge),
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
                      const _HistoryIcon(),
                      Text(
                        'You\'ve already had a trial',
                        style: DesignConstants.kioskPanelTitle,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        _body(state),
                        style: DesignConstants.kioskBody.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      _Actions(
                        onPick: cubit.dismissTrialBlock,
                        onHelp: cubit.trialBlockHelp,
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
        );
      },
    );
  }

  /// The plan step is walked once per training person, so in a GROUP the popup
  /// must NAME whoever it is about: an unnamed block in the middle of a run of
  /// named turns is ambiguous exactly when it matters most.
  ///
  /// It never names the PLAN. The rule is per member, not per plan — one trial
  /// in their history closes all of them — so naming one would describe a
  /// narrower rule than the grid is actually enforcing.
  String _body(KioskSignupState state) {
    const tail = 'Everything else on the list is open — or the coach at the '
        'desk can talk through the options.';
    if (!state.isGroup) {
      return 'Trials are one to a member, and you\'ve already had yours. '
          '$tail';
    }
    final first = state.activePerson.firstName.trim();
    if (first.isEmpty) {
      return 'Trials are one to a member, and they\'ve already had theirs. '
          '$tail';
    }
    return 'Trials are one to a member, and $first has already had theirs. '
        '$tail';
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

/// The warm disc the kiosk's other handoffs wear, carrying a history glyph:
/// this popup states a thing that already happened.
class _HistoryIcon extends StatelessWidget {
  const _HistoryIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.yellowDark,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.history_sharp,
        size: DesignConstants.iconSizeBig,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.okYellow,
      ),
    );
  }
}
