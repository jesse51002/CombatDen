import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Email + copy-icon cell for the "Contact" column. The copy icon is
/// its own tap target so it doesn't trigger the row's tap handler.
class ContactCell extends StatelessWidget {
  final String email;
  final VoidCallback onCopy;

  const ContactCell({
    super.key,
    required this.email,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Flexible(
          child: Text(
            email,
            style: DesignConstants.h3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        InkWell(
          onTap: onCopy,
          borderRadius: BorderRadius.circular(DesignConstants.spacingSmall),
          child: Padding(
            padding: const EdgeInsets.all(DesignConstants.spacingTiny),
            child: Icon(
              Symbols.content_copy_sharp,
              size: 20,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.text2nd,
            ),
          ),
        ),
      ],
    );
  }
}
