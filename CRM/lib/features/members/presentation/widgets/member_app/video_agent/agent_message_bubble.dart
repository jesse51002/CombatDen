import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A left-aligned message from the agent.
class AgentMessageBubble extends StatelessWidget {
  final String text;

  const AgentMessageBubble({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(DesignConstants.paddingSmall),
          decoration: BoxDecoration(
            color: DesignConstants.card,
            borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          ),
          child: Text(text, style: DesignConstants.p),
        ),
      ),
    );
  }
}
