import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Displays a member's avatar and name.
///
/// Used in all table views. Avatar fills the 30px row
/// height.
class NameCell extends StatelessWidget {
  final String name;
  final String? avatarUrl;

  const NameCell({
    super.key,
    required this.name,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: DesignConstants.tableRowHeight,
          height: DesignConstants.tableRowHeight,
          child: ClipOval(
            child: avatarUrl != null
                ? Image.network(
                    avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _fallbackAvatar(),
                  )
                : _fallbackAvatar(),
          ),
        ),
        const SizedBox(
          width: DesignConstants.spacingMedium,
        ),
        Flexible(
          child: Text(
            name,
            style: DesignConstants.h3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _fallbackAvatar() {
    return Container(
      color: DesignConstants.card,
      child: Center(
        child: Icon(
          Symbols.person_sharp,
          size: 18,
          color: DesignConstants.text3rd,
          weight: DesignConstants.iconWeight,
        ),
      ),
    );
  }
}
