import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/login/presentation/widgets/gate/gate_message_view.dart';

/// Shown when the identity fetch can't reach the server and there is no cached
/// selection to boot from. Offers a retry and a sign-out.
class OfflineView extends StatelessWidget {
  const OfflineView({
    super.key,
    required this.onRetry,
    required this.onSignOut,
  });

  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return GateMessageView(
      icon: GateIcons.offline,
      title: "Can't reach the gym server",
      body: Text(
        'Check your connection and try again.',
        style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        textAlign: TextAlign.center,
      ),
      primaryLabel: 'Retry',
      onPrimary: onRetry,
      secondaryLabel: 'Sign out',
      onSecondary: onSignOut,
    );
  }
}
