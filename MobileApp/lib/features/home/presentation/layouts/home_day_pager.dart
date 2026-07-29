import 'package:flutter/material.dart';
import 'package:mobile_app/features/home/data/schedule_generator.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_data.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_header.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_header_metrics.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_status.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_layout.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/date_row_header_delegate.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/day_class_group.dart';

/// `HomeFormat.dayPager` — one day per swipe.
///
/// The date rail stops being a scroll shortcut and becomes the primary
/// control: it drives a horizontal pager, one day per page, and the
/// classes get the room to be wide media cards. Trades cross-day
/// scanning for a much stronger single-day read.
///
/// A [NestedScrollView] rather than the shared vertical scaffold: the
/// header has to scroll away above a pager that owns its own vertical
/// scrolling, and that hand-off is exactly what NestedScrollView is for.
class HomeDayPager extends StatefulWidget {
  const HomeDayPager({super.key, required this.data});

  final HomeLayoutData data;

  @override
  State<HomeDayPager> createState() => _HomeDayPagerState();
}

class _HomeDayPagerState extends State<HomeDayPager> {
  late final PageController _pageController;
  late final ScrollController _dateController;
  int _currentDayIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _dateController = ScrollController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _onDateTap(int index) {
    setState(() => _currentDayIndex = index);
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NestedScrollView(
      headerSliverBuilder: (context, innerScrolled) => [
        SliverToBoxAdapter(child: HomeHeader(data: widget.data)),
        SliverOverlapAbsorber(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          sliver: SliverPersistentHeader(
            pinned: true,
            delegate: DateRowHeaderDelegate(
              currentDayIndex: _currentDayIndex,
              scrollController: _dateController,
              height: kHomeDateRowHeight,
              onDateTap: _onDateTap,
            ),
          ),
        ),
      ],
      body: widget.data.hasSchedule ? _pager() : _statusPage(),
    );
  }

  Widget _pager() {
    return PageView.builder(
      controller: _pageController,
      itemCount: kScheduleDayCount,
      onPageChanged: (index) => setState(() => _currentDayIndex = index),
      itemBuilder: (context, index) => _DayPage(
        key: PageStorageKey<int>(index),
        child: DayClassGroup(
          day: dayAt(index, widget.data.loadedClasses),
          showBookings: widget.data.booked,
          itemLayout: ClassItemLayout.imageTop,
        ),
      ),
    );
  }

  Widget _statusPage() => _DayPage(child: HomeStatus(data: widget.data));
}

/// One page of the pager. Scrolls vertically on its own and re-inserts
/// the space the pinned date rail took, so the day's first class is not
/// hidden underneath it.
class _DayPage extends StatelessWidget {
  const _DayPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverToBoxAdapter(child: child),
      ],
    );
  }
}
