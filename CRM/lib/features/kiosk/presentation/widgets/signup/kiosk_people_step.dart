import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_flow_views.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_person_adder.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_step_scaffold.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_form_panel.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_roster_row.dart';
import 'package:crm/shared/widgets/intrinsic_wrap.dart';

/// E1 — "Anyone else joining?", the roster.
///
/// Every signup passes through this step (founder ruling 8), solo included:
/// with nobody added the primary reads "It's just me". A step that only
/// appeared for families would have to be discovered.
///
/// At least one person must be getting a membership — every row's check unticks
/// individually, and a cart of nothing would send `memberships: []` and take a
/// 400. The primary goes unavailable there, with the reason and the fix stated
/// beside it rather than a dead button.
class KioskPeopleStep extends StatefulWidget {
  const KioskPeopleStep({super.key});

  @override
  State<KioskPeopleStep> createState() => _KioskPeopleStepState();
}

class _KioskPeopleStepState extends State<KioskPeopleStep> {
  /// The adder is open. Widget state on purpose: a disclosure inside one
  /// screen, always collapsed again after a person is added.
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
        // Continue needs BOTH a payer and at least one person training; each
        // block states its own reason below.
        final canGo = hasPayer && state.anyoneTraining && !busy;
        return KioskStepScaffold(
          step: KioskSignupStep.people,
          title: 'Anyone else joining?',
          subtitle: 'Add the people you\'re paying for — family, a partner, a '
              'friend. You pay for everyone on one card.',
          foot: FlowFoot(
            primaryLabel:
                count == 1 ? 'It\'s just me' : 'Continue with $count people',
            onPrimary: canGo ? cubit.continueToPlans : null,
            // No route back with no payer (no payer screen behind this one),
            // and none for an ADOPTED existing payer: the kiosk never typed
            // their details and must not offer a form that would PUT over the
            // gym's own record.
            onBack: busy || !hasPayer || state.payer.wasExisting
                ? null
                : cubit.back,
            onEscape: cubit.abandon,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingLarge,
            children: [
              FlowFormPanel(
                children: [
                  for (var i = 0; i < count; i++)
                    FlowRosterRow(
                      person: kioskRosterPerson(state, i),
                      isGroup: state.isGroup,
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
/// side — "already a member" is a different act from "new".
class _AddRow extends StatelessWidget {
  final VoidCallback onAdd;

  const _AddRow({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    // A Wrap, not a Row: the two kiosk-scale labels are wider than the form
    // panel's measure and must fall to a second line, never off the edge.
    return IntrinsicWrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DesignConstants.spacingLarge,
      runSpacing: DesignConstants.spacingMedium,
      children: [
        KioskOutlineButton(text: 'Add someone new', onPressed: onAdd),
        // Secondary tier, not ghost: finding an existing member is another way
        // IN, and the kiosk reserves ghost for leaving a flow.
        KioskOutlineButton(
          text: 'or find an existing member',
          onPressed: cubit.openMatchSearch,
        ),
      ],
    );
  }
}

/// Hand the paying over to somebody else without giving up your own seat.
///
/// It sits BELOW the panel and outside the add row on purpose: adding somebody
/// and changing who pays are different acts, and a member reaching for one must
/// never land on the other. It withdraws once anything commits and whenever
/// nobody is getting a membership (see [KioskSignupState.canSwitchPayer]).
class _PayerSwitchRow extends StatelessWidget {
  const _PayerSwitchRow();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: KioskOutlineButton(
        text: 'Change who is paying',
        onPressed: context.read<KioskSignupCubit>().openPayerPick,
      ),
    );
  }
}

/// Choose the payer after the previous one was deleted — the required fix for
/// the no-payer block, offered right where the block is.
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

/// The no-payer block's reason: the previous payer was deleted and none has
/// been chosen, so Continue waits. It points at the fix.
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

/// The empty-cart block: every person's membership check is unticked. It states
/// the rule and points at the fix, and never reads as an error.
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
