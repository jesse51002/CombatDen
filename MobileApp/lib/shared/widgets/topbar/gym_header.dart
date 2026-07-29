import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';

/// The logo's square box. A per-asset dimension, reused by both the real and
/// the themed branch, so it is hoisted rather than typed twice.
const double _kLogoSize = 100;

/// The big-logo topbar variant's brand block: the gym's logo over its name.
/// Brand only — the member's identity control lives in the topbar's trailing
/// flank, not inside the title.
class GymHeader extends StatelessWidget {
  const GymHeader({
    super.key,
    required this.gymName,
    required this.logoAsset,
    this.gymLogoUrl,
  });

  final String gymName;
  final String logoAsset;

  /// The gym's OWN uploaded logo (`gyms.logo_url`, via the member identity).
  /// Preferred over the theme's mark: a gym uploads its logo precisely so
  /// members see *their* gym, and a purchased theme's logo should only stand
  /// in for branding the gym hasn't supplied itself. Null until the gym
  /// uploads one.
  final String? gymLogoUrl;

  @override
  Widget build(BuildContext context) {
    final url = gymLogoUrl?.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingBig,
      children: [
        if (url == null || url.isEmpty)
          _ThemedLogo(asset: logoAsset)
        else
          Image(
            image: CachedNetworkImageProvider(url),
            width: _kLogoSize,
            height: _kLogoSize,
            fit: BoxFit.contain,
            // Permanent brand chrome: a failed load falls back to the themed
            // mark rather than collapsing, the same rule the info bar's rank
            // belt uses. A hole where the logo sits reads as a broken app.
            errorBuilder: (_, _, _) => _ThemedLogo(asset: logoAsset),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                gymName,
                style: DesignConstants.h1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The theme's logo slot, degrading to the bundled asset. The fallback for a
/// gym that hasn't uploaded its own mark (or whose mark failed to load).
class _ThemedLogo extends StatelessWidget {
  const _ThemedLogo({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ThemeImage.image(
        CombatDenSlots.logoPrimary,
        fallback: ApiImage.asset(asset),
      ),
      width: _kLogoSize,
      height: _kLogoSize,
      fit: BoxFit.contain,
    );
  }
}
