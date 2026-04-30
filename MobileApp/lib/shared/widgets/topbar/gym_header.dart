import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/branding/brand.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/shared/widgets/brand_image.dart';

class GymHeader extends StatefulWidget {
  const GymHeader({
    super.key,
    required this.gymName,
    required this.logoAsset,
  });

  final String gymName;
  final String logoAsset;

  @override
  State<GymHeader> createState() => _GymHeaderState();
}

class _GymHeaderState extends State<GymHeader> {
  static const _tapWindow = Duration(milliseconds: 600);
  static const _tapsToToggle = 3;

  int _taps = 0;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _onLogoTap() {
    _resetTimer?.cancel();
    _taps++;
    if (_taps >= _tapsToToggle) {
      _taps = 0;
      BrandScope.toggle(context);
      final newBrand = BrandScope.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to ${newBrand.displayName}'),
          duration: const Duration(milliseconds: 1500),
        ),
      );
      return;
    }
    _resetTimer = Timer(_tapWindow, () => _taps = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingBig,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onLogoTap,
          child: BrandImage.asset(
            widget.logoAsset,
            width: 100,
            height: 100,
            fit: BoxFit.cover,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(widget.gymName, style: DesignConstants.h1),
            Icon(
              Symbols.expand_more_sharp,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.text,
              size: DesignConstants.iconSizeSm,
            ),
          ],
        ),
      ],
    );
  }
}
