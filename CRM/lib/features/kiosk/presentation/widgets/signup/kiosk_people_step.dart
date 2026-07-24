import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_person_adder.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_roster_row.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_form_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';
import 'package:crm/shared/widgets/intrinsic_wrap.dart';

/// E1 — "Anyone else joining?", the roster.
///
/// **Every signup passes through this step** (ruling 8), solo included: with
/// nobody added the primary reads "It's just me" and goes straight on to the
/// plans. A step that only appeared for families would have to be discovered,
/// and a parent who has already typed their own details is exactly the person
/// who will not go looking for it.
///
/// The primary is guarded against an empty cart: a payer who turned "Training
/// too" off with nobody else on the roster would send `memberships: []` and
/// take a 400, so that state cannot advance and says why.
class KioskPeopleStep extends StatefulWidget {
  const KioskPeopleStep({super.key});

  @override
  State<KioskPeopleStep> createState() => _KioskPeopleStepState();
}

class _KioskPeopleStepState extends State<KioskPeopleStep> {
  /// The adder is open. Widget state on purpose: it is a disclosure inside one
  /// screen, and it should always come back collapsed after a person is added.
  bool _adderOpen = false;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.persons != cur.persons ||
          prev.signedWaivers != cur.signedWaivers ||
          prev.submitting != cur.submitting,
      builder: (context, state) {
        final count = state.persons.length;
        final busy = state.submitting;
        final canGo = state.canLeavePeople && !busy;
        return KioskSignupStepScaffold(
          step: KioskSignupStep.people,
          title: 'Anyone else joining?',
          subtitle: 'Add the people you\'re paying for — family, a partner, a '
              'friend. You pay for everyone on one card.',
          foot: KioskFlowFoot(
            primaryLabel:
                count == 1 ? 'It\'s just me' : 'Continue with $count people',
            onPrimary: canGo ? cubit.continueToPlans : null,
            onBack: busy ? null : cubit.back,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingLarge,
            children: [
              KioskSignupFormPanel(
                children: [
                  for (var i = 0; i < count; i++)
                    KioskRosterRow(
                      person: state.persons[i],
                      index: i,
                      removable: state.canRemovePerson(i),
                      onDetails: () => cubit.editPersonDetails(i),
                      onRemove: () => cubit.removePerson(i),
                      onTrainingChanged: cubit.setPayerTraining,
                    ),
                  if (_adderOpen)
                    KioskPersonAdder(
                      onCancel: () => setState(() => _adderOpen = false),
                    )
                  else
                    _AddRow(onAdd: () => setState(() => _adderOpen = true)),
                ],
              ),
              if (!state.canLeavePeople) const _EmptyCartNote(),
            ],
          ),
        );
      },
    );
  }
}

/// The collapsed adder: the two ways to put someone on the roster, side by
/// side, because "already a member" is a genuinely different act from "new".
class _AddRow extends StatelessWidget {
  final VoidCallback onAdd;

  const _AddRow({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    // A Wrap, not a Row: the two kiosk-scale labels are wider than the form
    // panel's measure, and a control a member cannot reach because it fell off
    // the right edge is worse than one on a second line.
    return IntrinsicWrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DesignConstants.spacingLarge,
      runSpacing: DesignConstants.spacingMedium,
      children: [
        KioskOutlineButton(text: 'Add someone new', onPressed: onAdd),
        KioskGhostButton(
          text: 'or find an existing member',
          onPressed: cubit.openMatchSearch,
        ),
      ],
    );
  }
}

/// The one state this screen can reach with nothing to sell: the payer turned
/// "Training too" off and nobody else is on the roster. It is a fact and a way
/// forward, never an error.
class _EmptyCartNote extends StatelessWidget {
  const _EmptyCartNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Add someone, or switch "Training too" back on — there\'s nothing to '
      'sign up for yet.',
      style: DesignConstants.kioskCaption.copyWith(
        color: DesignConstants.text2nd,
      ),
      textAlign: TextAlign.center,
    );
  }
}
