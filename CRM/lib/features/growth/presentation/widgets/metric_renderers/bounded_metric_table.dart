import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Caps a growth metric table at [DesignConstants.growthTableMaxHeight] and
/// scrolls its rows inside that height, so a long table (a 12-month companion
/// breakdown, a full at-risk list) never dictates the tab's height — a short
/// table still renders at its natural height.
///
/// Follows the app's internal-scroll convention (the member-detail history
/// cards): an explicit controller, an always-visible thumb, and a right
/// gutter so the thumb clears the table instead of overlapping its last
/// column. The section title above the table stays put; only the rows scroll.
class BoundedMetricTable extends StatefulWidget {
  /// The `AppDataTable` (shrink-wrapped) to bound and scroll.
  final Widget table;

  const BoundedMetricTable({super.key, required this.table});

  @override
  State<BoundedMetricTable> createState() => _BoundedMetricTableState();
}

class _BoundedMetricTableState extends State<BoundedMetricTable> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: DesignConstants.growthTableMaxHeight,
      ),
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _controller,
          padding:
              const EdgeInsets.only(right: DesignConstants.spacingLarge),
          child: widget.table,
        ),
      ),
    );
  }
}
