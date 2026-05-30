import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Small circular person avatar.
///
/// Resolution order: a bundled [photoAsset], then a network [photoUrl]
/// (e.g. the gym's instructor headshots), then the person's initials,
/// finally a person glyph when no name is given. A network photo that is
/// still loading or fails to load shows the initials fallback, so a roster
/// never renders as broken image boxes — it degrades to monograms.
class InstructorAvatar extends StatelessWidget {
  final String? photoAsset;
  final String? photoUrl;
  final String? name;
  final double diameter;

  const InstructorAvatar({
    super.key,
    this.photoAsset,
    this.photoUrl,
    this.name,
    this.diameter = 24,
  });

  String get _initials {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Initials scale with the circle so they read at both a 28px table cell
  /// and a 96px profile header. Snaps to design tokens — never an inline size.
  TextStyle get _initialsStyle {
    if (diameter >= 72) return DesignConstants.big2Bold;
    if (diameter >= 44) return DesignConstants.h2;
    return DesignConstants.pSmall;
  }

  @override
  Widget build(BuildContext context) {
    if (photoAsset != null) {
      return CircleAvatar(
        radius: diameter / 2,
        backgroundColor: DesignConstants.backgroundColor,
        backgroundImage: AssetImage(photoAsset!),
      );
    }

    if (photoUrl != null) {
      return ClipOval(
        child: Image.network(
          photoUrl!,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _fallback,
        ),
      );
    }

    return _fallback;
  }

  Widget get _fallback {
    final initials = _initials;
    return CircleAvatar(
      radius: diameter / 2,
      backgroundColor: DesignConstants.primaryColor25,
      child: initials.isNotEmpty
          ? Text(
              initials,
              style: _initialsStyle.copyWith(
                color: DesignConstants.text,
              ),
            )
          : Icon(
              Symbols.person_sharp,
              size: diameter / 2,
              color: DesignConstants.text3rd,
              weight: DesignConstants.iconWeight,
            ),
    );
  }
}
