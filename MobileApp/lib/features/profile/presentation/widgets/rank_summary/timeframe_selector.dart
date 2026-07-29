import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/pills/timeframe_pill.dart';

/// The four ranges, in order, and which one reads as active. Fixed:
/// this is the same control in every arrangement.
const List<String> _kRanges = ['1W', '1M', '1Y', 'ALL'];
const String _kActive = 'ALL';

/// How the four range pills are laid out.
enum TimeframeLayout {
  /// Loose centred row. Ships today.
  pills,

  /// Tight leading-aligned row for a header line.
  inline,

  /// Equal-width pills sharing one full-width track.
  segmented,

  /// Two by two, for a board tile.
  tile,
}

/// 1W / 1M / 1Y / ALL range selector for the rating graph.
class TimeframeSelector extends StatelessWidget {
  const TimeframeSelector({super.key, this.layout = TimeframeLayout.pills});

  final TimeframeLayout layout;

  @override
  Widget build(BuildContext context) {
    return switch (layout) {
      TimeframeLayout.pills => _row(
        spacing: DesignConstants.spacingBig,
        alignment: MainAxisAlignment.center,
      ),
      TimeframeLayout.inline => _row(
        spacing: DesignConstants.spacingMedium,
        alignment: MainAxisAlignment.start,
      ),
      TimeframeLayout.segmented => _segmented(),
      TimeframeLayout.tile => _tile(),
    };
  }

  Widget _pill(String label) =>
      TimeframePill(label: label, isActive: label == _kActive);

  Widget _row({
    required double spacing,
    required MainAxisAlignment alignment,
  }) {
    return Row(
      mainAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      spacing: spacing,
      children: [for (final range in _kRanges) _pill(range)],
    );
  }

  Widget _segmented() {
    return Row(
      spacing: DesignConstants.spacingTiny,
      children: [
        for (final range in _kRanges) Expanded(child: _pill(range)),
      ],
    );
  }

  /// Two by two. Rows rather than a `Wrap`: a pill's own box expands to
  /// whatever width it is offered, so it needs the unbounded main axis a
  /// Row gives it to size to its label instead of to the tile.
  Widget _tile() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        for (var i = 0; i < _kRanges.length; i += 2)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [_pill(_kRanges[i]), _pill(_kRanges[i + 1])],
          ),
      ],
    );
  }
}
