import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

// Device geometry (logical px at 1x). The whole phone is laid out at these
// dimensions and scaled to fit via FittedBox. These are physical-device
// measurements (a real phone's body radius, bezel, dynamic island), not
// fungible app design tokens, so they live as private consts here.
const double _kScreenW = 390;
const double _kScreenH = 844;
const double _kBezel = 14;
const double _kBodyRadius = 66;
const double _kScreenRadius = 52;
const double _kStatusInset = 52; // room below the dynamic island
const double _kIslandW = 122;
const double _kIslandH = 34;
const double _kIslandTopGap = 11;

const double _kBodyW = _kScreenW + _kBezel * 2;
const double _kBodyH = _kScreenH + _kBezel * 2;

/// A realistic phone mockup that wraps [child] in a device body — rounded
/// titanium frame, thin bezel, and a dynamic-island pill — scaled to fit.
/// The child renders at the real screen size (390x844) with a matching
/// `MediaQuery` (including a top status inset so content clears the island),
/// so member-app-sized content measures exactly as on a device.
///
/// Drive the size from the caller (e.g. `SizedBox(height: ...)`); width
/// follows from the device aspect ratio.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _kBodyW / _kBodyH,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _kBodyW,
          height: _kBodyH,
          child: Stack(
            children: [
              // Device body (frame).
              Container(
                decoration: BoxDecoration(
                  color: DesignConstants.text,
                  borderRadius: BorderRadius.circular(_kBodyRadius),
                  boxShadow: [
                    BoxShadow(
                      color: DesignConstants.text.withValues(alpha: 0.25),
                      blurRadius: 32,
                      spreadRadius: 2,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
              ),
              // Screen.
              Positioned(
                left: _kBezel,
                top: _kBezel,
                width: _kScreenW,
                height: _kScreenH,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_kScreenRadius),
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: const Size(_kScreenW, _kScreenH),
                      padding: const EdgeInsets.only(top: _kStatusInset),
                      viewInsets: EdgeInsets.zero,
                      viewPadding: const EdgeInsets.only(top: _kStatusInset),
                    ),
                    child: child,
                  ),
                ),
              ),
              // Dynamic island.
              Positioned(
                top: _kBezel + _kIslandTopGap,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: _kIslandW,
                    height: _kIslandH,
                    decoration: BoxDecoration(
                      color: DesignConstants.text,
                      borderRadius: BorderRadius.circular(_kIslandH / 2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
