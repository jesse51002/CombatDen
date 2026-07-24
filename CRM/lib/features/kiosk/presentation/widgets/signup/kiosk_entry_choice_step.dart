import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_home_columns.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_section_head.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';

/// The signup lane's first screen: brand new here, or already a member.
///
/// **The lane is self-serve for both.** An existing member no longer has to be
/// sent to the desk to start or change a membership — they say so here, find
/// their own name, and carry on. The one thing that never changes is that they
/// type a fresh card at the end.
///
/// It is the kiosk home's own two-way composition ([KioskHomeColumns] over two
/// [KioskHomeHalf]s, split by the vertical "or" seam), so the two binary
/// choices this kiosk offers are drawn by the same object: both heads
/// top-aligned, both buttons on one optical centre, and the feet band dropped
/// because neither half fills it.
///
/// **The two buttons are deliberately different tiers.** Two gradient primaries
/// side by side break the kiosk button ladder and two outlines leave the screen
/// with no primary, which reads flat at 2m. Primary goes to the new-member
/// path: it is the majority case at a signup kiosk, and it is also the only one
/// with no alternative — an existing member can always be handled at the desk,
/// a walk-in with no account cannot. [KioskOutlineButton] is still a
/// full-weight 17px control with a 2px ink border — never the ghost escape
/// tier, so it cannot read as "leave".
class KioskEntryChoiceStep extends StatelessWidget {
  const KioskEntryChoiceStep({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    final gym = selectedGym.gymName;
    return KioskSignupStepScaffold(
      step: KioskSignupStep.entry,
      title: gym == null || gym.trim().isEmpty
          ? 'Welcome in'
          : 'Welcome to ${gym.trim()}',
      subtitle: 'Two ways in. Which one are you?',
      // [KioskHomeColumns] wraps its bands in an `IntrinsicHeight` whose
      // middle band is an `Expanded`, so it needs a BOUNDED height to resolve
      // against — the scaffold's default scrolling body is unbounded. The
      // screen is short and must never scroll anyway.
      fillBody: true,
      // The decision lives in the panel, so the middle column carries no
      // primary — the precedent the match and picker steps already set. No
      // Back either: this is step 1, and the escape answers where they came
      // from.
      foot: const KioskFlowFoot(onPrimary: null),
      child: KioskHomeColumns(
        left: KioskHomeHalf(
          head: const KioskSectionHead(
            title: 'New to the gym',
            subtitle: 'You don\'t have an account here yet.',
          ),
          body: Center(
            child: KioskPrimaryButton(
              text: 'I\'m new here',
              onPressed: cubit.startAsNewMember,
            ),
          ),
        ),
        right: KioskHomeHalf(
          head: const KioskSectionHead(
            title: 'Already a member',
            subtitle: 'You\'ve trained here before, or the desk set you up.',
          ),
          body: Center(
            child: KioskOutlineButton(
              text: 'Find my name',
              onPressed: cubit.startAsExistingMember,
            ),
          ),
        ),
      ),
    );
  }
}
