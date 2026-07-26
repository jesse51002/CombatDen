import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/utils/validators.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_form_panel.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_step_scaffold.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_field_box.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_field_pair.dart';

/// D1 — who you are. First name, last name, email, phone.
///
/// Field order and validation mirror the admin `MemberCreateForm`, with two
/// deliberate differences: email is REQUIRED for every person (ruling 12),
/// payer and payee alike, which keeps the duplicate gate live for everyone and
/// gives each person app sign-in; and there is no photo field, which a
/// self-serve iPad has no business taking.
///
/// Nothing here is written — the member is created at the END of the next step
/// so one request carries every field they gave, which is why abandoning from
/// this screen writes nothing and the footer's escape needs no confirm.
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
  /// turns red mid-word scolds a member for still typing.
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    // Seeded FROM state, so stepping Back shows what the member typed.
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
    return FlowStepScaffold(
      step: KioskSignupStep.details,
      title: 'Let\'s get you started',
      subtitle: 'Two minutes, and you can train today.',
      // Step 1 has no Back — home is where they came from, and the escape in
      // the left gutter already answers that.
      foot: FlowFoot(onPrimary: _valid ? _continue : null),
      child: FlowFormPanel(
        children: [
          FlowFieldPair(
            children: [
              FlowFieldBox(
                controller: _firstName,
                label: 'First name',
                hintText: 'Marcus',
                errorText: show ? _nameError(_firstName) : null,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              FlowFieldBox(
                controller: _lastName,
                label: 'Last name',
                hintText: 'Bell',
                errorText: show ? _nameError(_lastName) : null,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          FlowFieldBox(
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
          FlowFieldBox(
            controller: _phone,
            label: 'Phone',
            // Optional is the EXCEPTION on this step, so it is marked here; on
            // the next step it is the rule, said once at the top instead.
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
