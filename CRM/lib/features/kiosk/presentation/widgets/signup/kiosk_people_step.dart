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
/// **At least one person must be getting a membership.** Every row's check can
/// be unticked individually, so a member can reach the all-unticked state by
/// hand — a cart of nothing would send `memberships: []` and take a 400. The
/// primary goes unavailable there, and the screen says plainly why and what to
/// do about it: a dead button with no explanation is the failure mode this
/// avoids.
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
        final hasPayer = state.hasPayer;
        // Continue needs BOTH a payer and at least one person getting a
        // membership. Each block shows its own plain reason below — never a
        // dead button.
        final canGo = hasPayer && state.anyoneTraining && !busy;
        return KioskSignupStepScaffold(
          step: KioskSignupStep.people,
          title: 'Anyone else joining?',
          subtitle: 'Add the people you\'re paying for — family, a partner, a '
              'friend. You pay for everyone on one card.',
          foot: KioskFlowFoot(
            primaryLabel:
                count == 1 ? 'It\'s just me' : 'Continue with $count people',
            onPrimary: canGo ? cubit.continueToPlans : null,
            // No route back with no payer (there is no payer's screen behind
            // this one), and an ADOPTED existing payer has nothing behind it
            // either: the kiosk never typed their details and must not offer a
            // route into a form that would PUT over the gym's own record.
            onBack: busy || !hasPayer || state.payer.wasExisting
                ? null
                : cubit.back,
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
                      isGroup: state.isGroup,
                      removable: state.canRemovePerson(i),
                      onDetails: () => cubit.editPersonDetails(i),
                      onRemove: () => cubit.askRemovePerson(i),
                      onTrainingChanged: (on) =>
                          cubit.setPersonTraining(i, on),
                    ),
                  if (_adderOpen)
                    KioskPersonAdder(
                      onCancel: () => setState(() => _adderOpen = false),
                    )
                  else
                    _AddRow(onAdd: () => setState(() => _adderOpen = true)),
                ],
              ),
              // The payer was deleted: offer the way to choose the next one,
              // and say plainly that the flow waits on it.
              if (!hasPayer)
                const _ChoosePayerRow()
              else if (state.canSwitchPayer)
                const _PayerSwitchRow(),
              if (!hasPayer)
                const _NeedsPayerNote()
              else if (!state.anyoneTraining)
                const _NeedsOneNote(),
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
        // The SECONDARY tier, not the ghost one: finding an existing member is
        // another way IN, and the kiosk reserves ghost for leaving a flow.
        KioskOutlineButton(
          text: 'or find an existing member',
          onPressed: cubit.openMatchSearch,
        ),
      ],
    );
  }
}

/// Hand the paying over to somebody else — a partner, a parent, or anyone
/// already on this roster — without giving up your own seat.
///
/// It is a CHANGE-of-role action, and the label says so: "someone else is
/// paying" announced a fact about a third party, which is not what the button
/// does. It sits BELOW the panel and outside the add row on purpose — adding
/// somebody and changing who pays are different acts, and a member reaching
/// for one must never land on the other.
///
/// It withdraws the moment anything commits, and whenever nobody is getting a
/// membership (see [KioskSignupState.canSwitchPayer]): with no money to move
/// there is no payer to argue about.
class _PayerSwitchRow extends StatelessWidget {
  const _PayerSwitchRow();

  @override
  Widget build(BuildContext context) {
    return Center(
      // Secondary tier: this is an action, not an escape.
      child: KioskOutlineButton(
        text: 'Change who is paying',
        onPressed: context.read<KioskSignupCubit>().openPayerPick,
      ),
    );
  }
}

/// Choose the payer after the previous one was deleted. It is the REQUIRED
/// fix for the no-payer block, so it is offered right where the block is — the
/// same secondary tier as "Change who is paying", because choosing a payer is
/// another way IN, not an escape.
class _ChoosePayerRow extends StatelessWidget {
  const _ChoosePayerRow();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: KioskOutlineButton(
        text: 'Choose who\'s paying',
        onPressed: context.read<KioskSignupCubit>().openPayerPick,
      ),
    );
  }
}

/// The no-payer block's plain reason. The previous payer was deleted and none
/// has been chosen, so Continue waits — and, exactly like the empty-cart note,
/// it points at the fix rather than leaving a dead button to explain itself.
class _NeedsPayerNote extends StatelessWidget {
  const _NeedsPayerNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Choose who\'s paying to continue.',
      style: DesignConstants.kioskCaption.copyWith(
        color: DesignConstants.text2nd,
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// The one state this screen can reach with nothing to sell: every person's
/// membership check is unticked.
///
/// It states the rule and points at the fix, and it never reads as an error —
/// nobody did anything wrong, the screen just cannot go anywhere yet. It is
/// what stops the disabled Continue from being a dead button with no
/// explanation beside it.
class _NeedsOneNote extends StatelessWidget {
  const _NeedsOneNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Tick whoever\'s getting a membership — we need at least one to carry '
      'on.',
      style: DesignConstants.kioskCaption.copyWith(
        color: DesignConstants.text2nd,
      ),
      textAlign: TextAlign.center,
    );
  }
}
