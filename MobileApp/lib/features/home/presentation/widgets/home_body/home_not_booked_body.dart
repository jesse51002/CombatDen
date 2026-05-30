import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/class_booking/data/class_info.dart';
import 'package:mobile_app/features/class_booking/data/class_repository.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/features/home/data/schedule_generator.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/day_class_group.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/pinned_date_row_delegate.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/schedule_status.dart';
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
  List<ClassInfo>? _classes;
  bool _classesError = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _verticalController = ScrollController()..addListener(_onVerticalScroll);
    _dateController = ScrollController();
    ClassRepository.instance.classes().then(
      (c) {
        if (mounted) setState(() => _classes = c);
      },
      onError: (_) {
        if (mounted) setState(() => _classesError = true);
      },
    );
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
    // Double-tap the schedule to jump straight into the post-class stats
    // flow — a quick-demo shortcut. Double-tap is discrete, so it doesn't
    // fight the list's vertical scroll. Mirrors the class screen's entry
    // (replace, not push: the flow exits back to home on its own).
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () =>
          Navigator.of(context).pushReplacementNamed(AppRoutes.postClassStreak),
      child: CustomScrollView(
        controller: _verticalController,
        slivers: [
          SliverToBoxAdapter(
            child: Builder(
              builder: (context) {
                final gym = mockGym;
                return AppTopbar(
                  mode: AppTopbarMode.bigLogo,
                  showBackButton: false,
                  gymName: selectedGym.displayName,
                  logoAsset: gym.logoAsset,
                  streakDays: gym.streakDays,
                  pointsLabel: gym.pointsLabel,
                  rankBadgeAsset: gym.rankBadgeAsset,
                  onTitleDoubleTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.styleSelect),
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
          _scheduleSliver(),
        ],
      ),
    );
  }

  Widget _scheduleSliver() {
    final classes = _classes;
    if (_classesError) {
      return const SliverToBoxAdapter(
        child: ScheduleStatus(message: "Couldn't load classes right now."),
      );
    }
    if (classes == null) {
      return const SliverToBoxAdapter(child: ScheduleStatus(loading: true));
    }
    if (classes.isEmpty) {
      return const SliverToBoxAdapter(
        child: ScheduleStatus(message: 'No classes scheduled.'),
      );
    }
    return SliverList.builder(
      itemBuilder: (context, index) =>
          DayClassGroup(day: dayAt(index, classes), showBookings: false),
    );
  }
}
