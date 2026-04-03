import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Displays an email address with a copy button.
///
/// The copy button stops propagation so it does not
/// trigger the row's onTap.
class ContactCell extends StatelessWidget {
  final String? email;

  const ContactCell({
    super.key,
    this.email,
  });

  @override
  Widget build(BuildContext context) {
    if (email == null || email!.isEmpty) {
      return Text(
        '—',
        style: DesignConstants.h3.copyWith(
          color: DesignConstants.text,
        ),
      );
    }

    return Semantics(
      label: 'Copy email address',
      button: true,
      child: GestureDetector(
        onTap: () {
          Clipboard.setData(
            ClipboardData(text: email!),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email copied'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            Flexible(
              child: Text(
                email!,
                style: DesignConstants.h3.copyWith(
                  color: DesignConstants.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(
              width: DesignConstants.spacingSmall,
            ),
            Icon(
              Symbols.content_copy_sharp,
              size: 16,
              color: DesignConstants.text3rd,
              weight: DesignConstants.iconWeight,
            ),
          ],
        ),
      ),
    );
  }
}
