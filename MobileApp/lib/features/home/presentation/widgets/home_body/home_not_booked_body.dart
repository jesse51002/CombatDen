import 'package:flutter/material.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/features/home/data/schedule_generator.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/day_class_group.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/pinned_date_row_delegate.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

const double _kTopbarHeight = 268;
const double _kDateRowHeight = 50;
const double _kDayGroupHeight = 592;

class HomeNotBookedBody extends StatefulWidget {
  const HomeNotBookedBody({super.key});

  @override
  State<HomeNotBookedBody> createState() => _HomeNotBookedBodyState();
}

class _HomeNotBookedBodyState extends State<HomeNotBookedBody>
    with AutomaticKeepAliveClientMixin {
  late final ScrollController _verticalController;
  late final ScrollController _dateController;
  int _currentDayIndex = 0;

  @override
  bool get wantKeepAlive => true;

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
    final adjusted = (offset - _kTopbarHeight).clamp(0.0, double.infinity);
    final newIndex = (adjusted / _kDayGroupHeight).floor();
    if (newIndex == _currentDayIndex) return;
    setState(() => _currentDayIndex = newIndex);
  }

  void _onDateTap(int index) {
    final target = _kTopbarHeight + index * _kDayGroupHeight;
    _verticalController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return CustomScrollView(
      controller: _verticalController,
      slivers: [
        SliverToBoxAdapter(
          child: Builder(
            builder: (context) {
              final gym = mockGym;
              return AppTopbar(
                mode: AppTopbarMode.bigLogo,
                showBackButton: false,
                gymName: gym.name,
                logoAsset: gym.logoAsset,
                streakDays: gym.streakDays,
                pointsLabel: gym.pointsLabel,
                rankBadgeAsset: gym.rankBadgeAsset,
              );
            },
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: PinnedDateRowDelegate(
            currentDayIndex: _currentDayIndex,
            scrollController: _dateController,
            height: _kDateRowHeight,
            onDateTap: _onDateTap,
          ),
        ),
        SliverList.builder(
          itemBuilder: (context, index) =>
              DayClassGroup(day: dayAt(index), showBookings: false),
        ),
      ],
    );
  }
}
