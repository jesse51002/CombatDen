import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_belt_band.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';

// Belt art sizes. The 77x50 pair is the shipped one; the tile pair is
// the same aspect stepped down for a board cell.
const double _kBeltWidth = 77;
const double _kBeltHeight = 50;
const double _kBeltTileWidth = 60;
const double _kBeltTileHeight = 39;

/// Where the current rank's belt sits relative to its name.
enum RankHeaderLayout {
  /// Belt and name centred on one line. Ships today.
  centred,

  /// The same line, pinned to the leading edge.
  beltLeft,

  /// The belt becomes a full-width band with the name over its foot.
  beltBleed,

  /// Belt over name, small enough for a board tile.
  tile,
}

/// The member's CURRENT rank: belt art, main rank name, sub-rank name.
class RankHeader extends StatelessWidget {
  const RankHeader({
    super.key,
    required this.rankTitle,
    required this.rankSubtitle,
    required this.rankBadgeAsset,
    this.layout = RankHeaderLayout.centred,
  });

  final String rankTitle;
  final String rankSubtitle;
  final String rankBadgeAsset;
  final RankHeaderLayout layout;

  ImageProvider get _belt => ThemeImage.image(
    CombatDenSlots.rankBelt,
    fallback: ApiImage.rankAsset(rankBadgeAsset),
  );

  @override
  Widget build(BuildContext context) {
    return switch (layout) {
      RankHeaderLayout.centred => _line(centred: true),
      RankHeaderLayout.beltLeft => _line(centred: false),
      RankHeaderLayout.beltBleed => _band(),
      RankHeaderLayout.tile => _tile(),
    };
  }

  Widget _line({required bool centred}) {
    return Row(
      mainAxisAlignment: centred
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      mainAxisSize: centred ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Image(
          image: _belt,
          width: _kBeltWidth,
          height: _kBeltHeight,
          fit: BoxFit.contain,
        ),
        _names(
          centred: centred,
          titleStyle: DesignConstants.h1,
          subtitleStyle: DesignConstants.h2,
        ),
      ],
    );
  }

  Widget _band() {
    return RankBeltBand(
      belt: _belt,
      names: _names(
        centred: false,
        titleStyle: DesignConstants.h1,
        subtitleStyle: DesignConstants.h2,
      ),
    );
  }

  Widget _tile() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Image(
          image: _belt,
          width: _kBeltTileWidth,
          height: _kBeltTileHeight,
          fit: BoxFit.contain,
        ),
        _names(
          centred: true,
          titleStyle: DesignConstants.h2,
          subtitleStyle: DesignConstants.pSmall,
        ),
      ],
    );
  }

  Widget _names({
    required bool centred,
    required TextStyle titleStyle,
    required TextStyle subtitleStyle,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centred
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(rankTitle, style: titleStyle),
        Text(
          rankSubtitle,
          style: subtitleStyle.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}
