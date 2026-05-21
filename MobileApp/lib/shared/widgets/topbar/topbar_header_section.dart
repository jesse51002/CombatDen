import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';
import 'package:mobile_app/shared/widgets/topbar/gym_header.dart';

/// Top portion of [AppTopbar] — the gym name (with optional big logo above
/// it) plus an optional back-chevron overlay on the leading edge.
///
/// Kept in its own file purely so [AppTopbar] stays under the file-length
/// limit; only [AppTopbar] should reference it.
class TopbarHeaderSection extends StatelessWidget {
  const TopbarHeaderSection({
    super.key,
    required this.mode,
    required this.showBackButton,
    required this.gymName,
    required this.logoAsset,
    required this.onTitleTap,
    this.onTitleDoubleTap,
  });

  final AppTopbarMode mode;
  final bool showBackButton;
  final String gymName;
  final String logoAsset;
  final VoidCallback onTitleTap;
  final VoidCallback? onTitleDoubleTap;

  @override
  Widget build(BuildContext context) {
    final gymLabel = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTitleTap,
      onDoubleTap: onTitleDoubleTap,
      child: mode == AppTopbarMode.bigLogo
          ? GymHeader(gymName: gymName, logoAsset: logoAsset)
          : _GymNameLabel(gymName: gymName),
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        gymLabel,
        if (showBackButton)
          const Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _BackButton(),
            ),
          ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.spacingMedium),
        child: Icon(
          Symbols.chevron_left_sharp,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text,
          size: DesignConstants.iconSize2xl,
        ),
      ),
    );
  }
}

class _GymNameLabel extends StatelessWidget {
  const _GymNameLabel({required this.gymName});

  final String gymName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(gymName, style: DesignConstants.h2),
        Icon(
          Symbols.expand_more_sharp,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text,
          size: DesignConstants.iconSizeSm,
        ),
      ],
    );
  }
}
