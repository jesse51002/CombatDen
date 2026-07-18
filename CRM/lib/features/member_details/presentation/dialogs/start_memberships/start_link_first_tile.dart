import 'package:flutter/material.dart';

import 'package:crm/shared/widgets/muted_add_tile.dart';

/// "Add an existing member" — brings someone who's already a
/// member into this run. The copy leads with the END GOAL; the
/// payer-authorization signature is part of the flow the tile
/// opens, deliberately not announced up front. Composes the
/// shared [MutedAddTile] muted-adder idiom.
class StartLinkFirstTile extends StatelessWidget {
  final VoidCallback onTap;

  const StartLinkFirstTile({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MutedAddTile(
      title: 'Add an existing member',
      subtitle: 'Bring someone who’s already a member into '
          'this run.',
      onTap: onTap,
    );
  }
}
