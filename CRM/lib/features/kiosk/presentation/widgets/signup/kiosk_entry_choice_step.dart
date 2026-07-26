import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_home_columns.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_section_head.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_step_scaffold.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';

/// The signup lane's first screen: brand new here, or already a member. The
/// lane is self-serve for both — an existing member finds their own name and
/// carries on rather than being sent to the desk — and either way types a
/// fresh card at the end.
///
/// It reuses the kiosk home's two-way composition ([KioskHomeColumns] over two
/// [KioskHomeHalf]s), so both binary choices this kiosk offers are drawn by
/// the same object.
///
/// The two buttons are deliberately different tiers: two primaries break the
/// kiosk button ladder, two outlines leave the screen with no primary and read
/// flat at 2m. Primary goes to the new-member path — the majority case, and
/// the only one with no alternative, since an existing member can always be
/// handled at the desk. [KioskOutlineButton] is never the ghost escape tier,
/// so it cannot read as "leave".
class KioskEntryChoiceStep extends StatelessWidget {
  const KioskEntryChoiceStep({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    final gym = selectedGym.gymName;
    return KioskStepScaffold(
      step: KioskSignupStep.entry,
      title: gym == null || gym.trim().isEmpty
          ? 'Welcome in'
          : 'Welcome to ${gym.trim()}',
      subtitle: 'Two ways in. Which one are you?',
      // [KioskHomeColumns] needs a BOUNDED height to resolve its `Expanded`
      // band against; the scaffold's default scrolling body is unbounded.
      fillBody: true,
      // The decision lives in the panel, so no primary. No Back either: this
      // is step 1, and the escape answers where they came from.
      foot: FlowFoot(onPrimary: null, onEscape: cubit.abandon),
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
