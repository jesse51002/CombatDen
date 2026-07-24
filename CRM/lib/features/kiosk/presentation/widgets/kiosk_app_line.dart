import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The muted "get / use the app" line — a tiny brand glyph beside a soft
/// caption. A calm nudge, never a loud CTA.
class KioskAppLine extends StatelessWidget {
  final String text;

  /// Cap on how tall the caption may grow as it wraps; it ellipsizes past it.
  /// Null (the default) lets it wrap freely — the glance's panel footer, where
  /// nothing sits beside it. The home's adopt strip caps it at two, because a
  /// long gym name would otherwise grow the one-row strip back into a stack.
  final int? maxLines;

  const KioskAppLine({super.key, required this.text, this.maxLines});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Container(
          width: DesignConstants.spinnerSizeSmall,
          height: DesignConstants.spinnerSizeSmall,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: DesignConstants.primaryGradient,
            borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          ),
          child: Icon(
            Symbols.adjust_sharp,
            size: DesignConstants.iconSizeTiny,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.onAccent,
          ),
        ),
        Flexible(
          child: Text(
            text,
            style: DesignConstants.kioskCaption.copyWith(
              color: DesignConstants.text2nd,
            ),
            textAlign: TextAlign.center,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
