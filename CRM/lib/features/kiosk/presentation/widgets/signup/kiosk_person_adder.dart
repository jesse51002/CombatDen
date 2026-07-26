import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/validators.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_field_box.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_field_pair.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/intrinsic_wrap.dart';

/// "Add someone new" — three fields on one row, and the two ways out of them.
///
/// Its Cancel closes the ADDER, never the flow: the flow-wide "Start over"
/// lives a full stage away in the footer's left gutter.
///
/// Next is not "Add Theo" — adding a person is two screens and this is the
/// first. It creates them (a duplicate becomes the match offer, never a stop)
/// and hands off to their own details screen, where the add finishes.
///
/// Email is REQUIRED for every person (founder ruling 12), payee included: it
/// keeps the duplicate gate live for everyone and gives each person app
/// sign-in.
class KioskPersonAdder extends StatefulWidget {
  final VoidCallback onCancel;

  const KioskPersonAdder({super.key, required this.onCancel});

  @override
  State<KioskPersonAdder> createState() => _KioskPersonAdderState();
}

class _KioskPersonAdderState extends State<KioskPersonAdder> {
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _email = TextEditingController();

  /// Validation appears only after a failed Next — a form that turns red
  /// mid-word scolds someone for typing.
  bool _submitted = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _nameError(TextEditingController c) =>
      c.text.trim().isEmpty ? 'Add their name.' : null;

  String? _emailError() {
    final value = _email.text.trim();
    if (value.isEmpty) return 'Add their email — it\'s how they sign in.';
    if (Validators.validateEmail(value) != null) {
      return 'Add the rest of the address.';
    }
    return null;
  }

  bool get _valid =>
      _nameError(_firstName) == null &&
      _nameError(_lastName) == null &&
      _emailError() == null;

  void _next() {
    if (!_valid) {
      setState(() => _submitted = true);
      return;
    }
    context.read<KioskSignupCubit>().addPerson(
          firstName: _firstName.text,
          lastName: _lastName.text,
          email: _email.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    final show = _submitted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        const Hairline(),
        _Head(onFindExisting: cubit.openMatchSearch),
        FlowFieldPair(
          children: [
            FlowFieldBox(
              controller: _firstName,
              label: 'First name',
              hintText: 'Theo',
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
          hintText: 'theo.bell@example.com',
          // Required, and the helper has to say so: the field gates Next, and
          // an "optional" hint over a disabled button reads as a broken screen.
          helperText: 'Each person needs their own — it\'s how they sign in.',
          errorText: show ? _emailError() : null,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: _next,
        ),
        IntrinsicWrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: DesignConstants.spacingLarge,
          runSpacing: DesignConstants.spacingMedium,
          children: [
            KioskOutlineButton(text: 'Cancel', onPressed: widget.onCancel),
            KioskPrimaryButton(
              text: 'Next',
              compact: true,
              onPressed: _valid ? _next : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _Head extends StatelessWidget {
  final VoidCallback onFindExisting;

  const _Head({required this.onFindExisting});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingLarge,
      children: [
        Expanded(
          child: Text('Add someone new', style: DesignConstants.kioskTitle),
        ),
        KioskOutlineButton(
          text: 'or find an existing member',
          onPressed: onFindExisting,
        ),
      ],
    );
  }
}
