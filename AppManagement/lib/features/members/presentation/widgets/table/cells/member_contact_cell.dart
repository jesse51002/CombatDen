import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// "Contact" column cell — email plus a small copy-to-clipboard
/// affordance. The copy action is a debug no-op for now.
class MemberContactCell extends StatelessWidget {
  final String email;

  const MemberContactCell({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Flexible(
          child: Text(
            email,
            style: DesignConstants.h3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        InkWell(
          onTap: () => debugPrint(
            'Copy email not wired this pass: $email',
          ),
          child: Icon(
            Symbols.content_copy_sharp,
            size: 16,
            color: DesignConstants.text2nd,
            weight: DesignConstants.iconWeight,
          ),
        ),
      ],
    );
  }
}
