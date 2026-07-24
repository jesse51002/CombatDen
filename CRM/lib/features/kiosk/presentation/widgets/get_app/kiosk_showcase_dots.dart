import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The dot's diameter, and the width the active dot stretches to.
const double _kDotSize = DesignConstants.spacingMedium;
const double _kActiveDotWidth = DesignConstants.spacingBig;

/// How long a dot takes to stretch / relax between slides.
const Duration _kDotMorph = Duration(milliseconds: 300);

/// The showcase's clickable dot pager: a muted dot per slide, the active one
/// stretched into a sapphire capsule. Tapping a dot jumps to that slide and
/// restarts the dwell.
class KioskShowcaseDots extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelected;

  const KioskShowcaseDots({
    super.key,
    required this.labels,
    required this.index,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        for (var i = 0; i < labels.length; i++)
          _Dot(
            label: labels[i],
            active: i == index,
            onTap: () => onSelected(i),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Dot({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: active,
      button: true,
      child: GestureDetector(
        // Opaque over a taller-than-it-looks box: the dot itself is 8px, which
        // is nowhere near a finger target on a touch kiosk. The extra height is
        // hit area only — the painted dot is unchanged, and the row's
        // horizontal rhythm is untouched.
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: DesignConstants.spacingBig,
          child: Center(
            child: AnimatedContainer(
              duration: _kDotMorph,
              curve: Curves.easeOutCubic,
              width: active ? _kActiveDotWidth : _kDotSize,
              height: _kDotSize,
              decoration: ShapeDecoration(
                color: active
                    ? DesignConstants.primaryColor
                    : DesignConstants.line,
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
