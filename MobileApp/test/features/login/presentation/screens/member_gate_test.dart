import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theme_flutter/customization_service.dart';
import 'package:theme_flutter/data/customization_api_client.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/login/presentation/screens/app_shell.dart';
import 'package:mobile_app/features/login/presentation/screens/member_gate.dart';
import 'package:mobile_app/features/login/presentation/widgets/gate/offline_banner.dart';
import 'package:mobile_app/features/login/presentation/widgets/gate/offline_view.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';
import 'package:mobile_app/features/member_select/data/repositories/member_portal_repository.dart';
import 'package:mobile_app/shared/widgets/loading_screen.dart';

/// A `ThemeService` whose [selectDesign] never touches the network.
///
/// `MemberGate.dispose()` fire-and-forgets `GymThemeHydration.reset()` on
/// EVERY unmount (any path, per its own doc comment) — including every test
/// in this file — which calls `ThemeRuntime.selectDesign`. The real
/// `ThemeService.selectDesign` makes a genuine `dio` request; started but
/// never awaited by the time a test tears down, it trips flutter_test's
/// "Timer is still pending" invariant. Overriding it to resolve immediately
/// keeps `AppShell`'s `ThemeRuntime.activeDesignId` / `ThemeRuntime.changes`
/// reads satisfied (both come from the base class untouched) without ever
/// opening a socket.
class _FakeThemeService extends ThemeService {
  _FakeThemeService()
      : super(
          ThemeApiClient(appId: 'combatden', designId: 'default'),
          expectedColorKeys: const [],
          expectedImageKeys: const [],
          expectedFontKeys: const [],
          expectedTextKeys: const [],
          expectedIconKeys: const [],
        );

  @override
  Future<bool> selectDesign(String designId) async => true;
}

/// `AppShell` (reached on the success path) reads `ThemeRuntime.activeDesignId`
/// / `ThemeRuntime.changes` during build, which throw until the engine's
/// `ThemeService` is registered in the package's `GetIt` — normally done by
/// `main.dart`'s `ThemeRuntime.initialize`, a real network call this test
/// suite never runs. Registering [_FakeThemeService] satisfies both without
/// touching the network or `main.dart`. Test-only; production boot unchanged.
void _ensureThemeRuntimeReady() {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<ThemeService>()) return;
  getIt.registerSingleton<ThemeService>(_FakeThemeService());
}

class _MockMemberPortalRepository extends Mock
    implements MemberPortalRepository {}

MemberIdentity _member(String id) => MemberIdentity(
      memberId: id,
      gymId: 'gym-$id',
      gymName: 'Gym $id',
      firstName: 'First',
      lastName: id,
    );

/// Every screen `MemberGate` can build lives happily under a bare
/// [MaterialApp] — none of the paths this file exercises read a `LoginBloc`
/// from context (that only happens on a sign-out tap, which nothing here
/// presses).
Widget _host(Widget child) => MaterialApp(home: child);

Route<dynamic> _fakeRoute(RouteSettings settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const SizedBox.shrink(),
    );

/// Replaces the current tree and pumps once — forces `MemberGate.dispose()`
/// (which fire-and-forgets `selectedMember.reset()` /
/// `GymThemeHydration.reset()`) to run and its microtasks to drain BEFORE the
/// test ends, so no async leftover from this test can land mid-flight in the
/// next one (both touch the same process-wide `selectedMember` singleton).
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000');
    _ensureThemeRuntimeReady();
  });

  tearDown(() => selectedMember.reset());

  group('the boot identity fetch retries a transport failure', () {
    testWidgets(
      'a NetworkException on the 1st attempt then success reaches the app '
      'with no offline banner ever shown (the bug this fixes)',
      (tester) async {
        final repository = _MockMemberPortalRepository();
        var calls = 0;
        when(() => repository.getMyMembers()).thenAnswer((_) async {
          calls++;
          if (calls == 1) {
            throw const NetworkException('connection error');
          }
          return [_member('m1')];
        });

        await tester.pumpWidget(_host(MemberGate(
          onGenerateRoute: _fakeRoute,
          repository: repository,
        )));
        // initState -> _resolve -> 1st attempt (fails synchronously enough
        // to resolve within a plain pump).
        await tester.pump();

        // Still on the branded splash — no flicker to the offline banner
        // while the retry is pending.
        expect(find.byType(LoadingScreen), findsOneWidget);
        expect(find.byType(OfflineBanner), findsNothing);
        expect(find.byType(OfflineView), findsNothing);
        expect(calls, 1);

        // Fire the ~400ms backoff -> 2nd attempt, which succeeds.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(calls, 2);
        expect(find.byType(AppShell), findsOneWidget);
        expect(find.byType(OfflineBanner), findsNothing);
        expect(find.byType(OfflineView), findsNothing);

        await _unmount(tester);
      },
    );

    testWidgets(
      'a NetworkException on all three attempts still falls through to the '
      'read-degraded offline banner, exactly as before',
      (tester) async {
        // A cached selection from a prior session, so the offline path boots
        // read-degraded (OfflineApp + banner) rather than the bare offline
        // screen.
        await selectedMember.select(
          memberId: 'm1',
          gymId: 'g1',
          gymName: 'Global MMA',
          firstName: 'Jane',
          lastName: 'Doe',
        );

        final repository = _MockMemberPortalRepository();
        var calls = 0;
        when(() => repository.getMyMembers()).thenAnswer((_) async {
          calls++;
          throw const NetworkException('connection error');
        });

        await tester.pumpWidget(_host(MemberGate(
          onGenerateRoute: _fakeRoute,
          repository: repository,
        )));
        await tester.pump(); // 1st attempt fails
        expect(calls, 1);

        await tester.pump(const Duration(milliseconds: 500)); // 2nd attempt
        expect(calls, 2);

        await tester.pump(const Duration(milliseconds: 1300)); // 3rd attempt
        await tester.pumpAndSettle();

        expect(calls, 3);
        expect(find.byType(OfflineBanner), findsOneWidget);
        expect(find.byType(AppShell), findsOneWidget); // OfflineApp wraps it

        await _unmount(tester);
      },
    );
  });

  group('a non-transport failure is never retried', () {
    testWidgets(
      'a ServerException goes straight to the offline/retry screen after '
      'EXACTLY one attempt (a 500 is not worth three round trips)',
      (tester) async {
        final repository = _MockMemberPortalRepository();
        var calls = 0;
        when(() => repository.getMyMembers()).thenAnswer((_) async {
          calls++;
          throw const ServerException('boom', statusCode: 500);
        });

        await tester.pumpWidget(_host(MemberGate(
          onGenerateRoute: _fakeRoute,
          repository: repository,
        )));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(calls, 1);
        expect(find.byType(OfflineView), findsOneWidget);
        expect(find.byType(OfflineBanner), findsNothing);

        await _unmount(tester);
      },
    );
  });
}
