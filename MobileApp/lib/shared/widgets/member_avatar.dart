import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';

/// The member's avatar in a circle: their photo when present, otherwise their
/// initials on a solid primary fill (a person glyph when there's no name
/// either).
///
/// The fallback fills with [DesignConstants.primaryColor] and paints on
/// [DesignConstants.primaryButtonText] — the slot whose whole job is "readable
/// ON the primary fill" (the pipeline picks body text when it clears WCAG AA
/// there, else the background). The obvious-looking pairing, primary-on-
/// primaryCard, is unreadable by construction: `primaryCard` IS the primary at
/// 9% alpha, so the mark and its background are one hue separated only by that
/// alpha. It scraped by at row scale; at topbar scale it is small text on every
/// screen, where AA is stricter.
///
/// ONE implementation, sized by the caller: the profile picker renders it at
/// row scale, the topbar at glyph scale. Forking a second avatar would let the
/// two drift — the identity mark has to read as the same object everywhere it
/// appears.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.diameter,
    this.photoUrl,
    this.firstName,
    this.lastName,
    this.initialsStyle,
  });

  /// The circle's width and height. A per-instance size, not a design token.
  final double diameter;

  final String? photoUrl;
  final String? firstName;
  final String? lastName;

  /// Text style for the initials fallback. Defaults to [DesignConstants.h2]
  /// (row scale); small renderings pass a smaller style.
  final TextStyle? initialsStyle;

  @override
  Widget build(BuildContext context) {
    final photo = photoUrl;
    final fallback = _fallback();
    if (photo == null || photo.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: photo,
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }

  Widget _fallback() {
    final initials = _initials();
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: initials.isEmpty
          ? Icon(
              Symbols.person_sharp,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.primaryButtonText,
              size: DesignConstants.iconSizeMd,
            )
          : Text(
              initials,
              style: (initialsStyle ?? DesignConstants.h2).copyWith(
                color: DesignConstants.primaryButtonText,
              ),
            ),
    );
  }

  /// Up to two initials from the member's name (first + last, else first).
  String _initials() {
    final first = firstName?.trim() ?? '';
    final last = lastName?.trim() ?? '';
    final a = first.isNotEmpty ? first[0] : '';
    final b = last.isNotEmpty ? last[0] : '';
    return '$a$b'.toUpperCase();
  }
}
