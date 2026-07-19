import 'package:flutter/material.dart';

import 'package:crm/shared/widgets/muted_add_tile.dart';

/// "Add an existing member" — someone who's already a member,
/// added for the payer to purchase a membership for. The copy
/// leads with the END GOAL; the payer-authorization signature
/// is part of the flow the tile opens, deliberately not
/// announced up front. Composes the shared [MutedAddTile]
/// muted-adder idiom.
class StartLinkFirstTile extends StatelessWidget {
  final String payerFirstName;
  final VoidCallback onTap;

  const StartLinkFirstTile({
    super.key,
    required this.payerFirstName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MutedAddTile(
      title: 'Add an existing member',
      subtitle: 'Choose an existing member $payerFirstName '
          'will purchase a membership for.',
      onTap: onTap,
    );
  }
}
