import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The sequential density ramp: the accent alpha-blended over the page
/// ground at 25 / 50 / 75 / 100%, plus a zero step. One hue, monotone
/// lightness — no new colour tokens, and no categorical palette invented for
/// a grid that is measuring one quantity.
const List<double> kHeatSteps = [0.25, 0.5, 0.75, 1.0];

/// A LABELLED grid caps at step 3: near-white ink on the full accent only
/// measures 3.5:1 in dark mode, which fails AA — on step 3 it clears it.
const int kLabelledMaxStep = 2;

/// The fill for one cell, or **null when the cell has no value at all**.
///
/// A null cell is NOT KNOWABLE YET — a cohort too young to have reached that
/// age — and must never be painted as the bottom of the scale: telling a gym
/// owner they lost every member of a cohort that has not aged into the
/// bucket yet would be a lie. The caller draws a null cell as an absent
/// cell: its outline only.
///
/// A cell that is genuinely zero is a different thing and does get the
/// zero step ([DesignConstants.backgroundAlt]).
Color? heatCellFill(
  double? value,
  double maxValue, {
  bool labelled = false,
}) {
  if (value == null) return null;
  if (value <= 0 || maxValue <= 0) return DesignConstants.backgroundAlt;
  final fraction = (value / maxValue).clamp(0.0, 1.0);
  // Quartile buckets: (0, .25] -> step 1 ... (.75, 1] -> step 4.
  var step = ((fraction * kHeatSteps.length).ceil() - 1)
      .clamp(0, kHeatSteps.length - 1);
  if (labelled && step > kLabelledMaxStep) step = kLabelledMaxStep;
  return Color.alphaBlend(
    DesignConstants.primaryColor.withValues(alpha: kHeatSteps[step]),
    DesignConstants.backgroundColor,
  );
}

/// The four legend swatches, quiet to busy.
List<Color> heatLegendSwatches() => [
      for (final alpha in kHeatSteps)
        Color.alphaBlend(
          DesignConstants.primaryColor.withValues(alpha: alpha),
          DesignConstants.backgroundColor,
        ),
    ];
