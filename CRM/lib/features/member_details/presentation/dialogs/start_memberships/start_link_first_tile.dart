import 'package:flutter/material.dart';

import 'package:crm/shared/widgets/muted_add_tile.dart';

/// "Someone missing?" — unlinked members can't receive a
/// membership in this run; staff link them first via the
/// existing link flow, then return here. Composes the shared
/// [MutedAddTile] muted-adder idiom.
class StartLinkFirstTile extends StatelessWidget {
  final VoidCallback onTap;

  const StartLinkFirstTile({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MutedAddTile(
      title: 'Someone missing? Authorize them first',
      subtitle: 'Members the payer isn’t authorized to pay for '
          'can’t be enrolled here.',
      onTap: onTap,
    );
  }
}
