import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Chat composer pinned to the bottom of the agent screen. No-op in the
/// prototype; the agent isn't wired yet.
class AgentInputBar extends StatelessWidget {
  const AgentInputBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingSmall,
        vertical: DesignConstants.spacingSmall,
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Expanded(
            child: TextField(
              style: DesignConstants.p,
              cursorColor: DesignConstants.text,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Message the agent',
                hintStyle: DesignConstants.p.copyWith(
                  color: DesignConstants.text3rd,
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => debugPrint('TODO: send to agent'),
            child: Icon(
              Symbols.send_sharp,
              color: DesignConstants.primaryColor,
              weight: DesignConstants.iconWeight,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}
