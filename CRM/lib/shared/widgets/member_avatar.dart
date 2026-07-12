import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Circular member avatar: the member's photo, or their initials on a soft
/// accent fill when no usable photo exists. A network photo that fails to
/// load degrades to the initials fallback, so a roster never renders as
/// broken image boxes — it falls back to a monogram.
///
/// Callers pass a [DesignConstants]-derived [size]; the initials scale with
/// it so the same widget reads at a small list cell and a large header.
class MemberAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;

  const MemberAvatar({
    super.key,
    required this.name,
    required this.size,
    this.photoUrl,
  });

  /// Up to two initials — the first letters of the first two words of [name].
  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  /// Initials scale with the circle — snapped to type tokens, never inlined.
  TextStyle get _initialsStyle {
    if (size >= DesignConstants.rewardAvatarSize) {
      return DesignConstants.big2Bold;
    }
    if (size >= DesignConstants.rankBeltSmall) return DesignConstants.h2;
    return DesignConstants.pSmall;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: name,
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: ClipOval(child: _content()),
      ),
    );
  }

  Widget _content() {
    final url = photoUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return ColoredBox(
      color: DesignConstants.accentSoft,
      child: Center(
        child: Text(
          _initials,
          style: _initialsStyle.copyWith(color: DesignConstants.text),
        ),
      ),
    );
  }
}
