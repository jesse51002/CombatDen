import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';

const double _kLogoDiameter = 48.0;

/// One tappable row in the "Who's training?" picker: the gym logo in a circle,
/// the member's name, the gym name, and a trailing chevron.
class MemberRow extends StatelessWidget {
  const MemberRow({
    super.key,
    required this.member,
    required this.onTap,
  });

  final MemberIdentity member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
        child: Padding(
          padding: const EdgeInsets.all(DesignConstants.paddingSmall),
          child: Row(
            spacing: DesignConstants.spacingLarge,
            children: [
              _LogoCircle(url: member.gymLogoUrl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DesignConstants.spacingTiny,
                  children: [
                    Text(
                      member.fullName,
                      style: DesignConstants.h2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      member.gymName,
                      style: DesignConstants.pSmall.copyWith(
                        color: DesignConstants.text2nd,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Symbols.chevron_right_sharp,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.text3rd,
                size: DesignConstants.iconSizeLg,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The gym logo in a circle, falling back to a storefront glyph when the gym
/// has no logo or the image can't load.
class _LogoCircle extends StatelessWidget {
  const _LogoCircle({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = _fallback();
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        width: _kLogoDiameter,
        height: _kLogoDiameter,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: _kLogoDiameter,
      height: _kLogoDiameter,
      decoration: BoxDecoration(
        color: DesignConstants.primaryCard,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Symbols.storefront_sharp,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.primaryColor,
        size: DesignConstants.iconSizeMd,
      ),
    );
  }
}
