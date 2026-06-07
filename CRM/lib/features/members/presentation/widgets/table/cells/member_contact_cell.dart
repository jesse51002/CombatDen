import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// "Contact" column cell — email with a copy affordance.
///
/// Shows a dash when email is absent.
class MemberContactCell extends StatelessWidget {
  final String? email;

  const MemberContactCell({super.key, this.email});

  @override
  Widget build(BuildContext context) {
    final display = email;
    if (display == null || display.isEmpty) {
      return Text(
        '—',
        style: DesignConstants.h3.copyWith(
          color: DesignConstants.text3rd,
        ),
      );
    }

    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Flexible(
          child: Text(
            display,
            style: DesignConstants.h3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        InkWell(
          onTap: () => debugPrint(
            'Copy email not wired this pass: $display',
          ),
          child: Icon(
            Symbols.content_copy_sharp,
            size: DesignConstants.iconSizeTiny,
            color: DesignConstants.text2nd,
            weight: DesignConstants.iconWeight,
          ),
        ),
      ],
    );
  }
}
