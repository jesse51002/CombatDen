import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Small circular instructor avatar.
///
/// Shows the bundled photo when available; otherwise the instructor's
/// initials, falling back to a person glyph when no name is given.
class InstructorAvatar extends StatelessWidget {
  final String? photoAsset;
  final String? name;
  final double diameter;

  const InstructorAvatar({
    super.key,
    this.photoAsset,
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

  @override
  Widget build(BuildContext context) {
    if (photoAsset != null) {
      return CircleAvatar(
        radius: diameter / 2,
        backgroundColor: DesignConstants.backgroundColor,
        backgroundImage: AssetImage(photoAsset!),
      );
    }

    final initials = _initials;
    return CircleAvatar(
      radius: diameter / 2,
      backgroundColor: DesignConstants.primaryColor25,
      child: initials.isNotEmpty
          ? Text(
              initials,
              style: DesignConstants.pSmall.copyWith(
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
