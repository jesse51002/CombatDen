import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';

const double _kAvatarDiameter = 48.0;

/// One tappable row in the "Who's training?" picker: the member's avatar in a
/// circle (their photo, or their initials), their name, the gym name, and a
/// trailing chevron. The avatar is the member — not the gym — so two profiles
/// on the same shared email (a family) stay distinguishable at a glance.
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
              _MemberAvatar(member: member),
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

/// The member's avatar in a circle: their photo when present, otherwise their
/// initials on a soft primary tint (a person glyph if there's no name either).
class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member});

  final MemberIdentity member;

  @override
  Widget build(BuildContext context) {
    final photo = member.photoUrl;
    final fallback = _fallback();
    if (photo == null || photo.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: photo,
        width: _kAvatarDiameter,
        height: _kAvatarDiameter,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }

  Widget _fallback() {
    final initials = _initials();
    return Container(
      width: _kAvatarDiameter,
      height: _kAvatarDiameter,
      decoration: BoxDecoration(
        color: DesignConstants.primaryCard,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: initials.isEmpty
          ? Icon(
              Symbols.person_sharp,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.primaryColor,
              size: DesignConstants.iconSizeMd,
            )
          : Text(
              initials,
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.primaryColor,
              ),
            ),
    );
  }

  /// Up to two initials from the member's name (first + last, else first).
  String _initials() {
    final first = member.firstName.trim();
    final last = member.lastName.trim();
    final a = first.isNotEmpty ? first[0] : '';
    final b = last.isNotEmpty ? last[0] : '';
    return '$a$b'.toUpperCase();
  }
}
