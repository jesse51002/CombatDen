import 'package:flutter/material.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_data.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_header.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_status.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/date_row_header_delegate.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/date_tab.dart';

/// The vertical schedule scaffold: header, date rail, day list.
///
/// Four of the five home formats are this shape and differ only in what
/// [scheduleSliver] builds and how tall a day runs. Shared so the
/// scroll-to-date and date-follows-scroll behaviour is written once and
/// cannot drift apart between formats.
class HomeScheduleScroll extends StatefulWidget {
  const HomeScheduleScroll({
    super.key,
    required this.data,
    required this.headerHeight,
    required this.dayGroupHeight,
    required this.dateRowHeight,
    required this.scheduleSliver,
    this.headerBleed = false,
    this.pinDateRow = true,
    this.dateTabStyle = DateTabStyle.underline,
  });

  final HomeLayoutData data;

  /// Everything above the date rail, in pixels. Approximate on purpose:
  /// it only decides which date pill highlights while scrolling, so a
  /// few px of drift costs nothing and runtime measurement would cost a
  /// layout pass per frame.
  final double headerHeight;
  final double dayGroupHeight;
  final double dateRowHeight;

  final Widget Function(BuildContext context) scheduleSliver;

  final bool headerBleed;
  final bool pinDateRow;
  final DateTabStyle dateTabStyle;

  @override
  State<HomeScheduleScroll> createState() => _HomeScheduleScrollState();
}

class _HomeScheduleScrollState extends State<HomeScheduleScroll> {
  late final ScrollController _verticalController;
  late final ScrollController _dateController;
  int _currentDayIndex = 0;

  @override
  void initState() {
    super.initState();
    _verticalController = ScrollController()..addListener(_onVerticalScroll);
    _dateController = ScrollController();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _onVerticalScroll() {
    final offset = _verticalController.offset;
    final adjusted = (offset - widget.headerHeight).clamp(0.0, double.infinity);
    final newIndex = (adjusted / widget.dayGroupHeight).floor();
    if (newIndex == _currentDayIndex) return;
    setState(() => _currentDayIndex = newIndex);
  }

  void _onDateTap(int index) {
    final target = widget.headerHeight + index * widget.dayGroupHeight;
    _verticalController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: _verticalController,
      slivers: [
        SliverToBoxAdapter(
          child: HomeHeader(data: widget.data, bleed: widget.headerBleed),
        ),
        SliverPersistentHeader(
          pinned: widget.pinDateRow,
          delegate: DateRowHeaderDelegate(
            currentDayIndex: _currentDayIndex,
            scrollController: _dateController,
            height: widget.dateRowHeight,
            onDateTap: _onDateTap,
            style: widget.dateTabStyle,
          ),
        ),
        if (widget.data.hasSchedule)
          widget.scheduleSliver(context)
        else
          SliverToBoxAdapter(child: HomeStatus(data: widget.data)),
      ],
    );
  }
}
