import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/features/home/data/schedule_generator.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_schedule_title.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/day_class_group.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/pinned_date_row_delegate.dart';
import 'package:mobile_app/features/home/presentation/widgets/upcoming_sessions/upcoming_sessions_card.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

// Approximate layout heights for scroll-position computation. They drive
// which date pill is highlighted while scrolling, so a few px drift is
// fine — no need for runtime measurement.
const double _kTopbarHeight = 268;
const double _kSectionGap = DesignConstants.spacingBig;
const double _kUpcomingSessionsCardHeight = 290;
const double _kClassScheduleTitleHeight = 20;
const double _kDateRowHeight = 50;
const double _kDayGroupHeight = 592;

// Gaps between sections come from Column(spacing:), so we sum them as
// regular components of the pre-schedule height — there are 2 inter-section
// gaps (topbar→card, card→title) before the date row.
const double _kPreScheduleHeight =
    _kTopbarHeight +
    _kSectionGap +
    _kUpcomingSessionsCardHeight +
    _kSectionGap +
    _kClassScheduleTitleHeight;

class HomeBookedBody extends StatefulWidget {
  const HomeBookedBody({super.key});

  @override
  State<HomeBookedBody> createState() => _HomeBookedBodyState();
}

class _HomeBookedBodyState extends State<HomeBookedBody>
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
    final adjusted = (offset - _kPreScheduleHeight).clamp(
      0.0,
      double.infinity,
    );
    final newIndex = (adjusted / _kDayGroupHeight).floor();
    if (newIndex == _currentDayIndex) return;
    setState(() => _currentDayIndex = newIndex);
  }

  void _onDateTap(int index) {
    final target = _kPreScheduleHeight + index * _kDayGroupHeight;
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: _kSectionGap,
            children: [
              Builder(
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
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: DesignConstants.screenHorizontalPadding,
                ),
                child: const UpcomingSessionsCard(),
              ),
              const ClassScheduleTitle(),
            ],
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
          itemBuilder: (context, index) => DayClassGroup(day: dayAt(index)),
        ),
      ],
    );
  }
}

