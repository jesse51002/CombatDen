import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/home/data/models/class_history.dart';
import 'package:mobile_app/features/home/data/repositories/member_class_history_repository.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_detector.dart';
import 'package:mobile_app/features/stats/data/celebration_rules.dart';
import 'package:mobile_app/features/stats/data/celebration_watermark.dart';

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

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await selectedMember.select(
      memberId: 'm1',
      gymId: 'g1',
      gymName: 'Global MMA',
      firstName: 'Jane',
      lastName: 'Doe',
    );
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
      await detector.maybeFire(null);
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
}
