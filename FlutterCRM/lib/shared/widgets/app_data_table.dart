import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Column definition for [AppDataTable].
class AppDataTableColumn {
  /// Header text for this column.
  final String label;

  /// Minimum column width in logical pixels.
  final double? minWidth;

  /// Maximum column width in logical pixels.
  final double? maxWidth;

  /// If true, column expands to fill remaining space.
  final bool fill;

  const AppDataTableColumn({
    required this.label,
    this.minWidth,
    this.maxWidth,
    this.fill = false,
  });
}

/// Row definition for [AppDataTable].
class AppDataTableRow {
  /// One widget per column — must match columns length.
  final List<Widget> cells;

  /// Row-level tap handler.
  final VoidCallback? onTap;

  const AppDataTableRow({
    required this.cells,
    this.onTap,
  });
}

/// A generic, reusable data table with sticky header,
/// infinite scroll, row taps, and dividers.
///
/// When the available width is narrower than the sum
/// of all column [minWidth] values, the table becomes
/// horizontally scrollable with a visible scrollbar.
class AppDataTable extends StatefulWidget {
  final List<AppDataTableColumn> columns;
  final List<AppDataTableRow> rows;
  final Color? rowDividerColor;
  final TextStyle? headerTextStyle;
  final Color? headerTextColor;
  final bool infiniteScroll;
  final VoidCallback? onLoadMore;
  final bool stickyHeader;
  final bool isLoadingMore;

  /// When true, wraps the table in a card-style
  /// container with [DesignConstants.card] background.
  final bool showBackground;

  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.rowDividerColor,
    this.headerTextStyle,
    this.headerTextColor,
    this.infiniteScroll = false,
    this.onLoadMore,
    this.stickyHeader = true,
    this.isLoadingMore = false,
    this.showBackground = false,
  });

  @override
  State<AppDataTable> createState() =>
      _AppDataTableState();
}

class _AppDataTableState extends State<AppDataTable> {
  final ScrollController _scrollController =
      ScrollController();
  final ScrollController _hScrollController =
      ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.infiniteScroll) {
      _scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _hScrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.infiniteScroll) return;
    if (widget.isLoadingMore) return;
    if (widget.onLoadMore == null) return;

    final maxScroll =
        _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;

    if (currentScroll >= maxScroll * 0.8) {
      widget.onLoadMore!();
    }
  }

  /// Computes the actual total width the table needs
  /// when every column uses at least its [minWidth].
  double _minTableWidth() {
    final columns = widget.columns;
    final totalGap = DesignConstants.spacingSmall *
        (columns.length - 1);
    double total = 0;
    for (final col in columns) {
      total += col.minWidth ?? 80;
    }
    return total + totalGap;
  }

  @override
  Widget build(BuildContext context) {
    final dividerColor = widget.rowDividerColor ??
        DesignConstants.divider;
    final headerStyle = widget.headerTextStyle ??
        DesignConstants.pSmall;
    final headerColor = widget.headerTextColor ??
        DesignConstants.text3rd;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth -
            (DesignConstants.screenHorizontalPadding *
                2);
        final minWidth = _minTableWidth();

        // Always compute columns against the wider
        // of viewport or minimum table width so
        // columns fill on wide screens and stay at
        // minWidth on narrow ones.
        final tableWidth = viewportWidth > minWidth
            ? viewportWidth
            : minWidth;

        final columnWidths =
            _computeColumnWidths(tableWidth);

        final totalGap = DesignConstants.spacingSmall *
            (widget.columns.length - 1);
        final contentWidth = columnWidths.fold(
              0.0,
              (sum, w) => sum + w,
            ) +
            totalGap;

        final header = _buildHeader(
          columnWidths,
          headerStyle,
          headerColor,
        );

        final body = ListView.separated(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          itemCount: widget.rows.length +
              (widget.isLoadingMore ? 1 : 0),
          separatorBuilder: (_, _) => Padding(
            padding: const EdgeInsets.symmetric(
              vertical: DesignConstants.spacingLarge,
            ),
            child: Container(
              height: 2,
              color: dividerColor,
            ),
          ),
          itemBuilder: (context, index) {
            if (index == widget.rows.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical:
                      DesignConstants.spacingLarge,
                ),
                child: Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DesignConstants
                          .primaryColor,
                    ),
                  ),
                ),
              );
            }

            return _buildRow(
              widget.rows[index],
              columnWidths,
            );
          },
        );

        final tableContent = Column(
          spacing: DesignConstants.spacingMedium,
          children: [
            header,
            Expanded(child: body),
          ],
        );

        Widget table = Padding(
          padding: const EdgeInsets.symmetric(
            horizontal:
                DesignConstants.screenHorizontalPadding,
          ),
          child: Scrollbar(
            controller: _hScrollController,
            thumbVisibility:
                contentWidth > viewportWidth,
            scrollbarOrientation:
                ScrollbarOrientation.bottom,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _hScrollController,
              child: SizedBox(
                width: contentWidth,
                height: constraints.maxHeight,
                child: tableContent,
              ),
            ),
          ),
        );

        if (widget.showBackground) {
          table = Container(
            decoration: BoxDecoration(
              color: DesignConstants.card,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusSmall,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              vertical: DesignConstants.paddingSmall,
            ),
            child: table,
          );
        }

        return table;
      },
    );
  }

  Widget _buildHeader(
    List<double> columnWidths,
    TextStyle style,
    Color color,
  ) {
    return SizedBox(
      height: DesignConstants.tableRowHeight,
      child: Row(
        children: List.generate(
          widget.columns.length,
          (i) {
            final isLast =
                i == widget.columns.length - 1;
            return Padding(
              padding: EdgeInsets.only(
                right: isLast
                    ? 0
                    : DesignConstants.spacingSmall,
              ),
              child: SizedBox(
                width: columnWidths[i],
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    header: true,
                    child: Text(
                      widget.columns[i].label,
                      style: DesignConstants.h2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRow(
    AppDataTableRow row,
    List<double> columnWidths,
  ) {
    final content = SizedBox(
      height: DesignConstants.tableRowHeight,
      child: Row(
        children: List.generate(
          columnWidths.length,
          (i) {
            final isLast =
                i == columnWidths.length - 1;
            return Padding(
              padding: EdgeInsets.only(
                right: isLast
                    ? 0
                    : DesignConstants.spacingSmall,
              ),
              child: SizedBox(
                width: columnWidths[i],
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: row.cells[i],
                ),
              ),
            );
          },
        ),
      ),
    );

    if (row.onTap != null) {
      return InkWell(
        onTap: row.onTap,
        child: content,
      );
    }

    return content;
  }

  /// Computes column widths based on available space.
  ///
  /// Non-fill columns get their [minWidth] (or 80 as
  /// fallback). Fill columns split remaining space
  /// equally, respecting min/max constraints.
  ///
  /// Uses iterative allocation so that columns clamped
  /// to min/max don't steal space from siblings.
  List<double> _computeColumnWidths(
    double availableWidth,
  ) {
    final columns = widget.columns;
    final totalGap = DesignConstants.spacingSmall *
        (columns.length - 1);
    final usableWidth = availableWidth - totalGap;
    final widths =
        List<double>.filled(columns.length, 0);

    // Allocate non-fill columns first.
    final unresolved = <int>[];
    double usedWidth = 0;
    for (int i = 0; i < columns.length; i++) {
      if (columns[i].fill) {
        unresolved.add(i);
      } else {
        final w = columns[i].minWidth ?? 80;
        widths[i] = w;
        usedWidth += w;
      }
    }

    // Iteratively distribute remaining space among
    // fill columns. Columns that hit min/max are
    // locked and remaining space is re-split.
    while (unresolved.isNotEmpty) {
      final remaining = usableWidth - usedWidth;
      final perFill =
          remaining / unresolved.length;

      final locked = <int>[];
      for (final i in unresolved) {
        final min = columns[i].minWidth;
        final max = columns[i].maxWidth;
        if (min != null && perFill < min) {
          widths[i] = min;
          usedWidth += min;
          locked.add(i);
        } else if (max != null && perFill > max) {
          widths[i] = max;
          usedWidth += max;
          locked.add(i);
        }
      }

      if (locked.isEmpty) {
        // No clamping needed — assign perFill to
        // all remaining columns.
        for (final i in unresolved) {
          widths[i] = perFill;
        }
        break;
      }

      // Remove locked columns and re-distribute.
      unresolved.removeWhere(locked.contains);
    }

    return widths;
  }
}
