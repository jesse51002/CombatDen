import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// What a signature is about to DO, stated beside the box it is typed in.
///
/// The warm `FlowInlineNotice` is the flow's "you should know this before you
/// carry on"; this is its opposite number, and the two never mean the same
/// thing: green is the outcome somebody is choosing, not a warning about it.
/// It is deliberately said BEFORE the signature rather than only confirmed
/// after it — a payer putting their name to somebody else's bill should not
/// have to sign to find out what they signed.
class SignOutcomeNotice extends StatelessWidget {
  final String message;

  const SignOutcomeNotice({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.greenDark,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.check_circle_sharp,
            size: DesignConstants.iconSizeLarge,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.goodGreen,
          ),
          Expanded(child: Text(message, style: scale.body)),
        ],
      ),
    );
  }
}
