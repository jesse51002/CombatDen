import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/login/presentation/widgets/gate/gate_message_view.dart';

/// Shown when the caller's confirmed email matches no member row at any gym —
/// reachable because sign-up is open. Names the email so the person can check
/// they used the address their gym has on file, and offers a re-check (the
/// gym may have just added them) and a sign-out.
class NoMembershipView extends StatelessWidget {
  const NoMembershipView({
    super.key,
    required this.email,
    required this.onCheckAgain,
    required this.onSignOut,
  });

  final String? email;
  final VoidCallback onCheckAgain;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return GateMessageView(
      icon: GateIcons.noMembership,
      title: 'No gym has this email yet',
      body: Text.rich(
        TextSpan(
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          children: [
            const TextSpan(text: 'Ask your gym to add you'),
            if (email != null && email!.isNotEmpty) ...[
              const TextSpan(text: ' with '),
              TextSpan(
                text: email,
                style: DesignConstants.h3.copyWith(
                  color: DesignConstants.text,
                ),
              ),
            ],
            const TextSpan(text: '. Once they do, come back and check again.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
      primaryLabel: 'Check again',
      onPrimary: onCheckAgain,
      secondaryLabel: 'Sign out',
      onSecondary: onSignOut,
    );
  }
}
