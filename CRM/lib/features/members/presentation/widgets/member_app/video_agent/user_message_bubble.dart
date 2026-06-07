import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A right-aligned message from the admin, tinted with the brand color.
class UserMessageBubble extends StatelessWidget {
  final String text;

  const UserMessageBubble({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(DesignConstants.paddingSmall),
          decoration: BoxDecoration(
            color: DesignConstants.primaryColor25,
            borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          ),
          child: Text(text, style: DesignConstants.p),
        ),
      ),
    );
  }
}
