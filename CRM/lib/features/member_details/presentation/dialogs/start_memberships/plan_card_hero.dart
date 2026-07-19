import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The plan card's 16:9 hero: the plan image (cover), a neutral placeholder
/// on a missing / broken URL (so a 404 never shifts the card), and a
/// top-right selection badge. [selected] draws a filled accent check; an
/// unselected but selectable card shows a quiet empty ring; a disabled card
/// ([showBadge] `false`) shows no badge.
class PlanCardHero extends StatelessWidget {
  final String imageUrl;
  final bool selected;
  final bool showBadge;

  const PlanCardHero({
    super.key,
    required this.imageUrl,
    required this.selected,
    required this.showBadge,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          imageUrl.isEmpty
              ? const _PlaceholderHero()
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _PlaceholderHero(),
                ),
          if (showBadge)
            Positioned(
              top: DesignConstants.spacingMedium,
              right: DesignConstants.spacingMedium,
              child: _SelectBadge(selected: selected),
            ),
        ],
      ),
    );
  }
}

/// Neutral fill + muted image glyph, shown when the plan image is missing or
/// fails to load.
class _PlaceholderHero extends StatelessWidget {
  const _PlaceholderHero();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DesignConstants.card,
      child: Center(
        child: Icon(
          Symbols.image_sharp,
          size: DesignConstants.iconSizeBig,
          color: DesignConstants.text3rd,
          weight: DesignConstants.iconWeight,
        ),
      ),
    );
  }
}

/// Top-right hero affordance: a filled accent check when [selected], else a
/// quiet empty ring inviting a tap. Mirrors the pool-chip check idiom.
class _SelectBadge extends StatelessWidget {
  final bool selected;

  const _SelectBadge({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.iconSizeLarge,
      height: DesignConstants.iconSizeLarge,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? DesignConstants.primaryColor
            : DesignConstants.popup,
        shape: BoxShape.circle,
        border: selected
            ? null
            : Border.all(
                color: DesignConstants.onAccent,
                width: DesignConstants.buttonBorder,
              ),
      ),
      child: selected
          ? Icon(
              Symbols.check_sharp,
              size: DesignConstants.iconSizeTiny,
              color: DesignConstants.onAccent,
              weight: DesignConstants.iconWeight,
            )
          : null,
    );
  }
}
