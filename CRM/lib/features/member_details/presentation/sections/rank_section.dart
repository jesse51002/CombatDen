import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/rank.dart';
import 'package:crm/features/member_details/presentation/dialogs/coming_soon_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Member's current rank (belt): belt glyph + label on the left,
/// the "classes to next rank" stat on the right, and a full-width
/// Promote action underneath. Rendered only when the member has a
/// rank assigned (the parent passes `null` through otherwise).
class RankSection extends StatelessWidget {
  final Rank rank;

  const RankSection({super.key, required this.rank});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          Text('Rank', style: DesignConstants.h2),
          _RankGrid(rank: rank),
          AppOutlineButton(
            fullWidth: true,
            text: 'Promote',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: () => ComingSoonDialog.show(
              context: context,
              title: 'Promote member',
              message:
                  'Promoting a member to the next rank is '
                  'pending — the rank-update flow is not '
                  'wired on the backend yet.',
            ),
          ),
        ],
      ),
    );
  }
}

class _RankGrid extends StatelessWidget {
  final Rank rank;

  const _RankGrid({required this.rank});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Expanded(child: _BeltDisplay(rank: rank)),
        Expanded(
          child: _RankStat(
            icon: Symbols.trending_up_sharp,
            value: '${rank.classesTillRankup} classes',
            label: 'To next rank',
          ),
        ),
      ],
    );
  }
}

/// Belt glyph (themed by the rank colour) above the rank name.
class _BeltDisplay extends StatelessWidget {
  final Rank rank;

  const _BeltDisplay({required this.rank});

  @override
  Widget build(BuildContext context) {
    final color = _beltColor(rank.color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        _BeltGlyph(imageUrl: rank.imageUrl, color: color),
        Text(
          rank.mainName,
          style: DesignConstants.h2,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Ranks without a sub-division store sub == main; skip
        // the redundant second line in that case.
        if (rank.subName != rank.mainName)
          Text(
            rank.subName,
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.text2nd,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _BeltGlyph extends StatelessWidget {
  final String? imageUrl;
  final Color color;

  const _BeltGlyph({
    required this.imageUrl,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return SizedBox(
        height: DesignConstants.iconSizeBig,
        child: Image.network(
          url,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          errorBuilder: (_, _, _) => _fallbackIcon(),
        ),
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Icon(
      Symbols.workspace_premium_sharp,
      color: color,
      size: DesignConstants.iconSizeBig,
      weight: DesignConstants.iconWeight,
    );
  }
}

/// One labelled stat, mirroring the retention stat tile.
class _RankStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _RankStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Icon(
          icon,
          color: DesignConstants.text,
          size: DesignConstants.iconSizeBig,
          weight: DesignConstants.iconWeight,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingTiny,
            children: [
              Text(
                value,
                style: DesignConstants.h2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: DesignConstants.h3.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Resolve a `#RRGGBB` belt colour (dynamic gym data, not a design
/// token) to a [Color], falling back to the brand colour when the
/// rank has no colour set or it is malformed.
Color _beltColor(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) {
    return DesignConstants.primaryColor;
  }
  final value = int.tryParse(hex.substring(1), radix: 16);
  if (value == null) return DesignConstants.primaryColor;
  return Color(0xFF000000 | value);
}
