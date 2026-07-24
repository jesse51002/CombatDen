import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/utils/validators.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_field_box.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_field_pair.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_form_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';

/// D1 — who you are. First name, last name, email, phone.
///
/// The field order and validation mirror the admin `MemberCreateForm`, so a
/// member created at the kiosk and a member created at the desk are the same
/// record made the same way. Two differences, both deliberate:
///
/// * **Email is REQUIRED for every person** (ruling 12), payer and payee
///   alike. It keeps the duplicate gate live for everyone and gives each
///   person app sign-in.
/// * **No photo field.** A member photo is a unique upload of the actual
///   person; a self-serve iPad has no business taking one.
///
/// Nothing here is written. The member is created at the END of the next step
/// so one request carries every field they gave — so abandoning from this
/// screen writes nothing at all, and the footer's escape needs no confirm.
class KioskSignupDetailsStep extends StatefulWidget {
  const KioskSignupDetailsStep({super.key});

  @override
  State<KioskSignupDetailsStep> createState() => _KioskSignupDetailsStepState();
}

class _KioskSignupDetailsStepState extends State<KioskSignupDetailsStep> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phone;

  /// Validation messages only appear after a failed Continue — a form that
  /// turns red while a member is still typing their own address is scolding
  /// them for being mid-word.
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    // Seeded FROM state, so stepping Back into this screen shows what the
    // member typed rather than an empty form.
    final person = context.read<KioskSignupCubit>().state.activePerson;
    _firstName = TextEditingController(text: person.firstName);
    _lastName = TextEditingController(text: person.lastName);
    _email = TextEditingController(text: person.email);
    _phone = TextEditingController(text: person.phone ?? '');
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  String? _nameError(TextEditingController c) =>
      c.text.trim().isEmpty ? 'Add your name so we know who you are.' : null;

  String? _emailError() {
    final value = _email.text.trim();
    if (value.isEmpty) return 'Add your email — it\'s how you sign in.';
    if (Validators.validateEmail(value) != null) {
      return 'Add the rest of the address — it needs a .com or similar '
          'on the end.';
    }
    return null;
  }

  bool get _valid =>
      _nameError(_firstName) == null &&
      _nameError(_lastName) == null &&
      _emailError() == null;

  void _continue() {
    if (!_valid) {
      setState(() => _submitted = true);
      return;
    }
    context.read<KioskSignupCubit>().submitDetails(
          firstName: _firstName.text,
          lastName: _lastName.text,
          email: _email.text,
          phone: _phone.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final show = _submitted;
    return KioskSignupStepScaffold(
      step: KioskSignupStep.details,
      title: 'Let\'s get you started',
      subtitle: 'Two minutes, and you can train today.',
      // Step 1 has no Back — home is where they came from, and the escape in
      // the left gutter already answers that.
      foot: KioskFlowFoot(onPrimary: _valid ? _continue : null),
      child: KioskSignupFormPanel(
        children: [
          KioskSignupFieldPair(
            children: [
              KioskFieldBox(
                controller: _firstName,
                label: 'First name',
                hintText: 'Marcus',
                errorText: show ? _nameError(_firstName) : null,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              KioskFieldBox(
                controller: _lastName,
                label: 'Last name',
                hintText: 'Bell',
                errorText: show ? _nameError(_lastName) : null,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          KioskFieldBox(
            controller: _email,
            label: 'Email',
            hintText: 'you@example.com',
            icon: Symbols.mail_sharp,
            helperText: 'This is how you sign in to the app, and where your '
                'receipt goes.',
            errorText: show ? _emailError() : null,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          KioskFieldBox(
            controller: _phone,
            label: 'Phone',
            // Optional is the EXCEPTION on this step, so it is marked here.
            // On the next step optional is the rule, so it is said once at
            // the top instead of on every field.
            labelNote: 'optional',
            hintText: '(555) 000-0000',
            icon: Symbols.call_sharp,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onSubmitted: _continue,
          ),
        ],
      ),
    );
  }
}
