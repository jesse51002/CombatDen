import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// "Phone" column cell — the member's phone number.
///
/// Shows a dash when there is none, matching [MemberContactCell]'s
/// treatment of a missing email. A half-finished signup often has one of
/// the two and not the other, which is exactly why both columns exist.
class MemberPhoneCell extends StatelessWidget {
  final String? phone;

  const MemberPhoneCell({super.key, this.phone});

  @override
  Widget build(BuildContext context) {
    final display = phone;
    if (display == null || display.isEmpty) {
      return Text(
        '—',
        style: DesignConstants.h3.copyWith(
          color: DesignConstants.text3rd,
        ),
      );
    }

    return Text(
      display,
      style: DesignConstants.h3,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
