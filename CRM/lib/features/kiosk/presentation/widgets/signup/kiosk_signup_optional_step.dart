import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_step_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_optional_fields.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_step_scaffold.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';

/// D1a and E1a — the optional block: date of birth, address, and an emergency
/// contact, for whoever the roster is currently about. Always shown, never
/// hidden behind an "add details" button (founder-locked): a member who has to
/// opt in fills none of it in.
///
/// One screen, two people, and the asymmetry is real. For the PAYER
/// (`extraDetails`) nothing has been written yet, so Continue and Skip both
/// fire the single `createMember` carrying this step's fields and the previous
/// step's; for a PAYEE (`personDetails`) the person already exists, so Continue
/// is a partial `updateMember` of only what was typed and Skip fires NOTHING —
/// which keeps the roster chip honest about what is actually on file.
///
/// A matched EXISTING member gets this screen with every field BLANK: a lobby
/// iPad never prints another member's stored details, and a write built from a
/// form that never showed a value cannot be used to wipe it.
class KioskSignupOptionalStep extends StatefulWidget {
  const KioskSignupOptionalStep({super.key});

  @override
  State<KioskSignupOptionalStep> createState() =>
      _KioskSignupOptionalStepState();
}

class _KioskSignupOptionalStepState extends State<KioskSignupOptionalStep> {
  late final TextEditingController _address;
  late final TextEditingController _ecName;
  late final TextEditingController _ecPhone;
  late final TextEditingController _ecEmail;
  DateTime? _dob;

  @override
  void initState() {
    super.initState();
    final person = context.read<KioskSignupCubit>().state.activePerson;
    // Seeded FROM state so Back-and-forward shows what they typed — except for
    // a matched existing member, whose stored details this must never print.
    final seed = person.wasExisting ? const KioskSignupPerson() : person;
    _dob = seed.dob;
    _address = TextEditingController(text: seed.address ?? '');
    _ecName = TextEditingController(text: seed.ecName ?? '');
    _ecPhone = TextEditingController(text: seed.ecPhone ?? '');
    _ecEmail = TextEditingController(text: seed.ecEmail ?? '');
  }

  @override
  void dispose() {
    _address.dispose();
    _ecName.dispose();
    _ecPhone.dispose();
    _ecEmail.dispose();
    super.dispose();
  }

  /// Continue AND Skip both land here for the PAYER — same values, same call.
  void _commitPayer() {
    context.read<KioskSignupCubit>().submitExtraDetails(
          dob: _dob,
          address: _address.text,
          ecName: _ecName.text,
          ecPhone: _ecPhone.text,
          ecEmail: _ecEmail.text,
        );
  }

  void _commitPayee() {
    context.read<KioskSignupCubit>().submitPersonDetails(
          dob: _dob,
          address: _address.text,
          ecName: _ecName.text,
          ecPhone: _ecPhone.text,
          ecEmail: _ecEmail.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.submitting != cur.submitting ||
          prev.step != cur.step ||
          prev.personDetailsFailed != cur.personDetailsFailed,
      builder: (context, state) {
        final person = state.activePerson;
        final payee = state.step == KioskSignupStep.personDetails;
        // A call in flight makes the whole footer inert so a second tap can't
        // fire a second write. The cubit latches this too — the UI is the
        // courtesy, the latch is the guarantee.
        final busy = state.submitting;
        final commit = payee ? _commitPayee : _commitPayer;
        // Kiosk-only step: the desk edits a member's record on their own
        // profile, so this head lives on the kiosk's own copy. The gym name is
        // read HERE and handed over — the copy takes facts, never a sentence.
        final copy = kioskStepCopy(context);
        return KioskStepScaffold(
          step: payee
              ? KioskSignupStep.personDetails
              : KioskSignupStep.extraDetails,
          title: copy.optionalStepTitle(
            payee: payee,
            firstName: person.firstName,
          ),
          subtitle: copy.optionalStepSubtitle(
            wasExisting: person.wasExisting,
            payee: payee,
            firstName: person.firstName,
            personIndex: state.activePersonIndex,
            personCount: state.persons.length,
            gymName: selectedGym.gymName,
          ),
          foot: FlowFoot(
            primaryLabel:
                payee ? 'Add ${person.firstName}' : 'Continue',
            onPrimary: busy ? null : commit,
            onBack: busy ? null : cubit.back,
            onSkip: busy
                ? null
                : (payee ? cubit.skipPersonDetails : _commitPayer),
            onEscape: cubit.abandon,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingLarge,
            children: [
              if (state.personDetailsFailed)
                FlowInlineNotice(
                  message: 'We couldn\'t save those details. Please try '
                      'again, or skip for now.',
                  onRetry: busy ? null : commit,
                ),
              KioskOptionalFields(
                dob: _dob,
                onDobChanged: (picked) => setState(() => _dob = picked),
                address: _address,
                ecName: _ecName,
                ecPhone: _ecPhone,
                ecEmail: _ecEmail,
              ),
            ],
          ),
        );
      },
    );
  }
}
