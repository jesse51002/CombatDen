import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The dismiss action. Built only where the screen supplies an
/// `onClose`; every layout places it in its own top-right corner.
///
/// [plated] seats the glyph on a round elevated chip. Values whose stage
/// runs UNDER the close (`figureTop` anchors the body to the top edge,
/// `fullBleed` gives it the whole canvas) need it or the X reads as part
/// of the illustration; the framed values do not, and pass false so
/// their close is the same bare glyph that ships today.
class CelebrationClose extends StatelessWidget {
  const CelebrationClose({
    super.key,
    required this.onClose,
    this.plated = false,
  });

  final VoidCallback onClose;
  final bool plated;

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(
      Symbols.close_sharp,
      color: DesignConstants.text,
      weight: DesignConstants.iconWeight,
      size: DesignConstants.iconSizeXl,
    );

    return IconButton(
      onPressed: onClose,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: plated
          ? Container(
              padding: EdgeInsets.all(DesignConstants.spacingMedium),
              decoration: BoxDecoration(
                color: DesignConstants.card,
                shape: BoxShape.circle,
              ),
              child: glyph,
            )
          : glyph,
    );
  }
}
