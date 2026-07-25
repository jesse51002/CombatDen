import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_dob_field.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_field_box.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_detail_group.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_field_pair.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_form_panel.dart';

/// The optional block's five fields — date of birth, address, and an
/// emergency contact — in the ONE layout used for everyone on the roster.
///
/// Nothing here marks an empty field as a problem: partial is the normal case,
/// and the optionality is stated once, in the screen's subtitle.
class KioskOptionalFields extends StatelessWidget {
  final DateTime? dob;
  final ValueChanged<DateTime?> onDobChanged;

  final TextEditingController address;
  final TextEditingController ecName;
  final TextEditingController ecPhone;
  final TextEditingController ecEmail;

  const KioskOptionalFields({
    super.key,
    required this.dob,
    required this.onDobChanged,
    required this.address,
    required this.ecName,
    required this.ecPhone,
    required this.ecEmail,
  });

  @override
  Widget build(BuildContext context) {
    return KioskSignupFormPanel(
      children: [
        KioskSignupDetailGroup(
          children: [
            KioskSignupFieldPair(
              children: [
                KioskDobField(value: dob, onChanged: onDobChanged),
                KioskFieldBox(
                  controller: address,
                  label: 'Address',
                  hintText: 'Street, city, ZIP',
                  icon: Symbols.location_on_sharp,
                  textInputAction: TextInputAction.next,
                ),
              ],
            ),
          ],
        ),
        KioskSignupDetailGroup(
          eyebrow: 'Emergency contact',
          children: [
            KioskFieldBox(
              controller: ecName,
              label: 'Name',
              hintText: 'Who we should call',
              icon: Symbols.person_sharp,
              textInputAction: TextInputAction.next,
            ),
            KioskSignupFieldPair(
              children: [
                KioskFieldBox(
                  controller: ecPhone,
                  label: 'Phone',
                  hintText: '(555) 000-0000',
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                ),
                KioskFieldBox(
                  controller: ecEmail,
                  label: 'Email',
                  hintText: 'dana@example.com',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
