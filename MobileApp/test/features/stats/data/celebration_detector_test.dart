import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/home/data/models/class_history.dart';
import 'package:mobile_app/features/home/data/repositories/member_class_history_repository.dart';
import 'package:mobile_app/features/profile/data/models/billing_personal_info.dart';
import 'package:mobile_app/features/profile/data/models/billing_retention.dart';
import 'package:mobile_app/features/profile/data/models/member_profile.dart';
import 'package:mobile_app/features/profile/data/models/member_promotion.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_detector.dart';
import 'package:mobile_app/features/stats/data/celebration_rules.dart';
import 'package:mobile_app/features/stats/data/celebration_watermark.dart';
import 'package:mobile_app/features/stats/data/promotion_watermark.dart';

/// Serves a canned class-history head — the detector's only I/O, so the whole
/// decision path is drivable without a backend.
class _FakeHistoryRepo implements MemberClassHistoryRepository {
  _FakeHistoryRepo(this.rows);

  final List<MemberClassHistoryRow> rows;

  @override
  Future<MemberClassHistory> getHistory({
    required String gymId,
    required String memberId,
    int limit = 20,
    int offset = 0,
  }) async {
    return MemberClassHistory(
      upcoming: const [],
      history: rows,
      hasMore: false,
    );
  }
}

/// A class-history read that always fails — the promotion leg needs no network
/// and must survive it.
class _FailingHistoryRepo implements MemberClassHistoryRepository {
  @override
  Future<MemberClassHistory> getHistory({
    required String gymId,
    required String memberId,
    int limit = 20,
    int offset = 0,
  }) async {
    throw Exception('history unavailable');
  }
}

MemberClassHistoryRow _attended({
  required String occurredAt,
  required String originalDate,
  String className = 'Boxing Fundamentals',
  int pointsWorth = 25,
}) {
  return MemberClassHistoryRow(
    classId: 'c1',
    className: className,
    imageUrl: '',
    originalDate: originalDate,
    originalTime: '18:00',
    durationMinutes: 60,
    status: MemberClassHistoryStatus.attended,
    pointsWorth: pointsWorth,
    occurredAt: occurredAt,
  );
}

MemberProfile _profile({MemberPromotion? promotion}) => MemberProfile(
      memberId: 'm1',
      gymId: 'g1',
      firstName: 'Jane',
      lastName: 'Doe',
      personalInfo: const BillingPersonalInfo(),
      retention: const BillingRetention(
        classStreakWeeks: 2,
        pointsBalance: 120,
        videosWatched: 0,
      ),
      latestPromotion: promotion,
    );

MemberPromotion _promotion({
  String activityId = 'act-1',
  DateTime? promotedAt,
  String? newRankName = 'Purple Belt',
}) =>
    MemberPromotion(
      activityId: activityId,
      promotedAt: promotedAt ?? DateTime.utc(2026, 7, 25, 12),
      oldRankName: 'Blue Belt · 2 Stripes',
      newRankName: newRankName,
      oldImageUrl: 'https://cdn.test/blue.png',
      newImageUrl: 'https://cdn.test/purple.png',
    );

/// Records the routes pushed, so the argument the flow was seeded with can be
/// read back off the route settings.
class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

/// A bare app whose navigator answers any named route, so a push can be
/// observed without building the real celebration screens.
Future<GlobalKey<NavigatorState>> _pumpNavigator(
  WidgetTester tester,
  _RecordingObserver observer,
) async {
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: key,
      navigatorObservers: [observer],
      home: const SizedBox.shrink(),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const SizedBox.shrink(),
      ),
    ),
  );
  observer.pushed.clear();
  return key;
}

CelebrationData _argumentsOf(Route<dynamic> route) =>
    route.settings.arguments! as CelebrationData;

void main() {
  const watermark = CelebrationWatermark();
  const promotionWatermark = PromotionWatermark();

  Future<void> selectGym({bool rankEnabled = true}) => selectedMember.select(
        memberId: 'm1',
        gymId: 'g1',
        gymName: 'Global MMA',
        firstName: 'Jane',
        lastName: 'Doe',
        gymRankEnabled: rankEnabled,
      );

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await selectGym();
  });

  tearDown(() => selectedMember.reset());

  group('CelebrationDetector.fireNow (the debug trigger)', () {
    test('leaves the watermark untouched where maybeFire advances it',
        () async {
      final seen = DateTime.utc(2026, 7, 1, 18);
      await watermark.mark('m1', seen);
      final detector = CelebrationDetector(
        historyRepository: _FakeHistoryRepo([
          _attended(
            occurredAt: '2026-07-23T18:00:00Z',
            originalDate: '2026-07-23',
          ),
        ]),
      );

      // The whole point: a preview must not consume the celebration the
      // founder was about to test.
      await detector.fireNow(null);
      expect(await watermark.lastSeen('m1'), seen);

      // Same detector, same data — the real path DOES burn it.
      await detector.maybeFire(null, null);
      expect(
        await watermark.lastSeen('m1'),
        DateTime.parse('2026-07-23T18:00:00Z'),
      );
    });

    testWidgets('still opens the flow when nothing has been attended',
        (tester) async {
      final observer = _RecordingObserver();
      final navigator = await _pumpNavigator(tester, observer);
      final detector = CelebrationDetector(
        historyRepository: _FakeHistoryRepo(const []),
      );

      await detector.fireNow(navigator.currentState);
      await tester.pumpAndSettle();

      expect(observer.pushed, hasLength(1));
      final route = observer.pushed.single;
      expect(route.settings.name, AppRoutes.postClassStreak);

      // A trigger that silently did nothing on a fresh member would be
      // useless, so the fallback payload has to be renderable.
      final data = _argumentsOf(route);
      expect(data.className, isNotEmpty);
      expect(data.pointsWorth, greaterThan(0));
      expect(data.occurredAt, isNotNull);
      expect(
        data.completedWeekdayIndices,
        <int>[sundayStripIndex(DateTime.now())],
      );

      // And it did not invent a watermark on the way.
      expect(await watermark.lastSeen('m1'), isNull);
    });

    testWidgets('carries the REAL attended class when there is one',
        (tester) async {
      final observer = _RecordingObserver();
      final navigator = await _pumpNavigator(tester, observer);
      final detector = CelebrationDetector(
        historyRepository: _FakeHistoryRepo([
          _attended(
            occurredAt: '2026-07-20T18:00:00Z',
            originalDate: '2026-07-20',
            className: 'Muay Thai Sparring',
            pointsWorth: 40,
          ),
          _attended(
            occurredAt: '2026-07-23T18:00:00Z',
            originalDate: '2026-07-23',
            className: 'No-Gi Grappling',
            pointsWorth: 30,
          ),
        ]),
      );

      await detector.fireNow(navigator.currentState);
      await tester.pumpAndSettle();

      final data = _argumentsOf(observer.pushed.single);
      expect(data.className, 'No-Gi Grappling');
      expect(data.pointsWorth, 30);
      expect(data.occurredAt, DateTime.parse('2026-07-23T18:00:00Z'));
      // Mon 2026-07-20 and Thu 2026-07-23 are the same Sunday-first week.
      expect(data.completedWeekdayIndices, <int>[1, 4]);
    });
  });

  group('the promotion leg fires ONCE per activity_id', () {
    testWidgets('an unseen promotion opens the flow on the belt card',
        (tester) async {
      // Seed the promotion watermark to something else, so the unseen row
      // fires rather than seeding.
      await promotionWatermark.mark('m1', 'an-older-row');
      final observer = _RecordingObserver();
      final navigator = await _pumpNavigator(tester, observer);
      final detector = CelebrationDetector(
        historyRepository: _FakeHistoryRepo(const []),
      );

      await detector.maybeFire(
        navigator.currentState,
        _profile(promotion: _promotion()),
      );
      await tester.pumpAndSettle();

      expect(observer.pushed, hasLength(1));
      final route = observer.pushed.single;
      expect(route.settings.name, AppRoutes.promotion);
      final data = _argumentsOf(route);
      expect(data.promoted, isTrue);
      // No class behind it, so the promotion is the whole flow.
      expect(data.occurredAt, isNull);
      expect(await promotionWatermark.lastSeen('m1'), 'act-1');
    });

    testWidgets('the SAME activity id never fires twice', (tester) async {
      await promotionWatermark.mark('m1', 'an-older-row');
      final observer = _RecordingObserver();
      final navigator = await _pumpNavigator(tester, observer);
      final detector = CelebrationDetector(
        historyRepository: _FakeHistoryRepo(const []),
      );

      await detector.maybeFire(
        navigator.currentState,
        _profile(promotion: _promotion()),
      );
      await tester.pumpAndSettle();
      expect(observer.pushed, hasLength(1));

      observer.pushed.clear();
      await detector.maybeFire(
        navigator.currentState,
        _profile(promotion: _promotion()),
      );
      await tester.pumpAndSettle();
      expect(observer.pushed, isEmpty);
    });

    testWidgets('a CHANGED promoted_at on the same row does not re-fire',
        (tester) async {
      await promotionWatermark.mark('m1', 'act-1');
      final observer = _RecordingObserver();
      final navigator = await _pumpNavigator(tester, observer);
      final detector = CelebrationDetector(
        historyRepository: _FakeHistoryRepo(const []),
      );

      // The watermark keys on the id alone; `promoted_at` is display and
      // ordering only, so re-recording it must change nothing.
      await detector.maybeFire(
        navigator.currentState,
        _profile(
          promotion: _promotion(promotedAt: DateTime.utc(2030, 1, 1)),
        ),
      );
      await tester.pumpAndSettle();

      expect(observer.pushed, isEmpty);
    });

    testWidgets('a null watermark SEEDS silently and shows nothing',
        (tester) async {
      final observer = _RecordingObserver();
      final navigator = await _pumpNavigator(tester, observer);
      final detector = CelebrationDetector(
        historyRepository: _FakeHistoryRepo(const []),
      );

      expect(await promotionWatermark.lastSeen('m1'), isNull);
      await detector.maybeFire(
        navigator.currentState,
        _profile(promotion: _promotion()),
      );
      await tester.pumpAndSettle();

      // Reinstall / second device / member switch: the belt is recorded as
      // seen, and nothing is replayed.
      expect(observer.pushed, isEmpty);
      expect(await promotionWatermark.lastSeen('m1'), 'act-1');
    });

    testWidgets('a promotion with no NAME is marked and never shown',
        (tester) async {
      await promotionWatermark.mark('m1', 'an-older-row');
      final observer = _RecordingObserver();
      final navigator = await _pumpNavigator(tester, observer);
      final detector = CelebrationDetector(
        historyRepository: _FakeHistoryRepo(const []),
      );

      await detector.maybeFire(
        navigator.currentState,
        _profile(promotion: _promotion(newRankName: null)),
      );
      await tester.pumpAndSettle();

      // Marking rather than skipping is what stops an unrenderable row being
      // reconsidered on every later open.
      expect(observer.pushed, isEmpty);
      expect(await promotionWatermark.lastSeen('m1'), 'act-1');
    });

    testWidgets('a gym with ranks OFF leaves the watermark ALONE',
        (tester) async {
      await selectGym(rankEnabled: false);
      final observer = _RecordingObserver();
      final navigator = await _pumpNavigator(tester, observer);
      final detector = CelebrationDetector(
        historyRepository: _FakeHistoryRepo(const []),
      );

      await detector.maybeFire(
        navigator.currentState,
        _profile(promotion: _promotion()),
      );
      await tester.pumpAndSettle();

      expect(observer.pushed, isEmpty);
      // Nothing to have been SEEN — so if the gym turns ranks back on, the
      // member is introduced to the ladder they are now on.
      expect(await promotionWatermark.lastSeen('m1'), isNull);
    });
  });

  group('the two legs are independent', () {
    testWidgets('a failing class read cannot swallow the promotion',
        (tester) async {
      await promotionWatermark.mark('m1', 'an-older-row');
      final observer = _RecordingObserver();
      final navigator = await _pumpNavigator(tester, observer);
      final detector = CelebrationDetector(
        historyRepository: _FailingHistoryRepo(),
      );

      await detector.maybeFire(
        navigator.currentState,
        _profile(promotion: _promotion()),
      );
      await tester.pumpAndSettle();

      expect(observer.pushed, hasLength(1));
      expect(observer.pushed.single.settings.name, AppRoutes.promotion);
      expect(_argumentsOf(observer.pushed.single).occurredAt, isNull);
    });

    testWidgets('both pending opens on the belt and carries the class payload',
        (tester) async {
      await promotionWatermark.mark('m1', 'an-older-row');
      // Both watermarks have to be seeded for both legs to FIRE rather than
      // seed silently — the realistic case is a member who has used the app.
      await watermark.mark('m1', DateTime.utc(2026, 7, 1, 18));
      final observer = _RecordingObserver();
      final navigator = await _pumpNavigator(tester, observer);
      final detector = CelebrationDetector(
        historyRepository: _FakeHistoryRepo([
          _attended(
            occurredAt: '2026-07-23T18:00:00Z',
            originalDate: '2026-07-23',
            className: 'No-Gi Grappling',
            pointsWorth: 30,
          ),
        ]),
      );

      await detector.maybeFire(
        navigator.currentState,
        _profile(promotion: _promotion()),
      );
      await tester.pumpAndSettle();

      final route = observer.pushed.single;
      expect(route.settings.name, AppRoutes.promotion);
      final data = _argumentsOf(route);
      expect(data.promoted, isTrue);
      // The class flow continues behind it — the payload is the real class.
      expect(data.className, 'No-Gi Grappling');
      expect(data.occurredAt, DateTime.parse('2026-07-23T18:00:00Z'));
      // Both watermarks burned in one pass.
      expect(await promotionWatermark.lastSeen('m1'), 'act-1');
      expect(
        await watermark.lastSeen('m1'),
        DateTime.parse('2026-07-23T18:00:00Z'),
      );
    });

    testWidgets('nothing pending pushes nothing at all', (tester) async {
      await promotionWatermark.mark('m1', 'act-1');
      await watermark.mark('m1', DateTime.utc(2026, 7, 23, 18));
      final observer = _RecordingObserver();
      final navigator = await _pumpNavigator(tester, observer);
      final detector = CelebrationDetector(
        historyRepository: _FakeHistoryRepo([
          _attended(
            occurredAt: '2026-07-23T18:00:00Z',
            originalDate: '2026-07-23',
          ),
        ]),
      );

      await detector.maybeFire(
        navigator.currentState,
        _profile(promotion: _promotion()),
      );
      await tester.pumpAndSettle();

      expect(observer.pushed, isEmpty);
    });
  });
}
