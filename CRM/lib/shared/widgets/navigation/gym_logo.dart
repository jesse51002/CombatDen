import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';

/// The managed gym's logo, sized to [size]. Shows the gym's **uploaded logo**
/// ([SelectedGym.logoUrl]) when it is set, otherwise the CombatDen brand mark.
///
/// It is NEVER the selected theme's logo: the nav chrome reflects the real gym
/// identity, independent of whatever theme is being previewed. Rebuilds on
/// [selectedGym] changes so a just-saved (or cleared) logo appears immediately.
class GymLogo extends StatelessWidget {
  final double size;

  const GymLogo({super.key, required this.size});

  /// The app's own brand mark — the fallback when the gym has no logo.
  static const AssetImage _combatDenLogo =
      AssetImage('assets/images/combatden_logo.png');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selectedGym,
      builder: (context, _) {
        final logoUrl = selectedGym.logoUrl;
        final hasLogo = logoUrl != null && logoUrl.isNotEmpty;
        return ClipRRect(
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          child: hasLogo
              ? Image.network(
                  logoUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => _fallback(),
                )
              : _fallback(),
        );
      },
    );
  }

  Widget _fallback() => Image(
        image: _combatDenLogo,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
}
