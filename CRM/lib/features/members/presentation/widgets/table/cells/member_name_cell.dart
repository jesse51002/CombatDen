import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// "Name" column cell — the member's full name with
/// optional avatar.
class MemberNameCell extends StatelessWidget {
  final String name;
  final String? avatarUrl;

  const MemberNameCell({
    super.key,
    required this.name,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        SizedBox(
          width: DesignConstants.iconSizeLarge,
          height: DesignConstants.iconSizeLarge,
          child: ClipOval(
            child: avatarUrl != null
                ? Image.network(
                    avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) =>
                        _fallbackAvatar(),
                  )
                : _fallbackAvatar(),
          ),
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
          size: DesignConstants.iconSizeSmall,
          color: DesignConstants.text3rd,
          weight: DesignConstants.iconWeight,
        ),
      ),
    );
  }
}
