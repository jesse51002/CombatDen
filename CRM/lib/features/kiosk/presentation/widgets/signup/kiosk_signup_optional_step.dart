import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_optional_fields.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_waiver_status.dart';

/// D1a **and** E1a — the optional block: date of birth, address, and an
/// emergency contact, for whoever the roster is currently about.
///
/// **It is always shown, never hidden behind an "add details" button**
/// (founder-locked). A member who is never asked to opt in fills most of it
/// in; a member who has to opt in fills none of it in.
///
/// **One screen, two people, and the asymmetry is real.** For the PAYER
/// (`extraDetails`) nothing has been written yet, so Continue and Skip fire
/// the single `createMember` call carrying this step's fields and the previous
/// step's — abandoning anywhere earlier writes nothing at all. For a PAYEE
/// (`personDetails`) the person already exists (the adder's Next created
/// them), so Continue is a partial `updateMember` of only what was typed and
/// **Skip fires nothing at all** — which is what keeps the roster chip honest
/// about what is actually on file.
///
/// **A matched EXISTING member gets this screen with every field BLANK.** A
/// lobby iPad never prints another member's stored address, and a write built
/// from a form that never showed a value cannot be used to wipe it.
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
    // Seeded FROM state so a member who steps Back and forward again sees what
    // they typed — except for a matched existing member, whose stored details
    // this screen never held and must never print.
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
  /// The only difference between the two buttons is which member they give
  /// permission to.
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
        // A call is in flight: the whole footer goes inert so a second tap
        // can't fire a second write. The cubit latches this too — the UI is
        // the courtesy, the latch is the guarantee.
        final busy = state.submitting;
        final commit = payee ? _commitPayee : _commitPayer;
        return KioskSignupStepScaffold(
          step: payee
              ? KioskSignupStep.personDetails
              : KioskSignupStep.extraDetails,
          title: payee
              ? 'A bit more about ${person.firstName}'
              : 'A bit more about you',
          subtitle: _subtitle(state, payee: payee),
          foot: KioskFlowFoot(
            primaryLabel:
                payee ? 'Add ${person.firstName}' : 'Continue',
            onPrimary: busy ? null : commit,
            onBack: busy ? null : cubit.back,
            onSkip: busy
                ? null
                : (payee ? cubit.skipPersonDetails : _commitPayer),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingLarge,
            children: [
              if (state.personDetailsFailed)
                KioskWaiverNotice(
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

  /// The optionality, said ONCE where it is read. A matched existing member
  /// gets the honest reason their form is blank instead.
  String _subtitle(KioskSignupState state, {required bool payee}) {
    final person = state.activePerson;
    if (person.wasExisting) {
      return '${person.firstName} already has details with us — we don\'t '
          'show them on a shared screen.';
    }
    if (payee) {
      final total = state.persons.length;
      return 'Person ${state.activePersonIndex + 1} of $total · all optional';
    }
    final gym = selectedGym.gymName;
    return gym == null || gym.trim().isEmpty
        ? 'Only gym staff sees this · all of it is optional'
        : 'Only ${gym.trim()} staff sees this · all of it is optional';
  }
}
