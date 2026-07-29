import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_box.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_frame.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';

// The bundled mark, used until a tenant's `logo_primary` resolves — the
// same file the app's gym carries, mirroring how every other image slot
// names its bundled fallback at the point of use.
const String _kBundledMark = 'gym_logo_global_mma.png';

/// Paints [LoaderShape.mark] marks: the tenant's own logo, resolved
/// through the `logo_primary` image slot with the bundled asset as the
/// fallback — exactly as `GymMark` resolves it in the topbar, so an
/// unbranded build shows the bundled mark rather than a hole.
class LoaderMarkField extends StatelessWidget {
  const LoaderMarkField({super.key, required this.marks, required this.box});

  final List<LoaderMark> marks;
  final LoaderBox box;

  @override
  Widget build(BuildContext context) {
    final extent = math.min(box.size.width, box.size.height);
    return Stack(
      alignment: Alignment.center,
      children: [
        for (final mark in marks)
          Transform.translate(
            offset: Offset(
              mark.x * (box.size.width - extent) / 2,
              -mark.lift * box.liftSpan,
            ),
            child: Opacity(
              opacity: mark.opacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: mark.scale,
                child: Image(
                  image: ThemeImage.image(
                    CombatDenSlots.logoPrimary,
                    fallback: ApiImage.asset(_kBundledMark),
                  ),
                  width: extent,
                  height: extent,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
