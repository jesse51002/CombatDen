import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_welcome_screen.dart';
import 'package:crm/features/membership_flow/config/kiosk_flow_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';

class _MockKioskFlowCubit extends MockCubit<KioskFlowState>
    implements KioskFlowCubit {}

class _MockKioskSignupCubit extends MockCubit<KioskSignupState>
    implements KioskSignupCubit {}

/// **The last screen of the signup may not read "you're all set" when it
/// isn't.**
///
/// A partial receipt now offers `Next` into this screen (founder ruling), so the
/// warm unconditional greeting — a green check over "Welcome to {gym},
/// {name}!" — can be reached with somebody's membership still outstanding. On
/// that arrival the screen carries the lane's own inline notice naming the front
/// desk; the greeting itself stays true and unchanged (they ARE a member of this
/// gym, and the receipt they just read carried the per-person detail).
///
/// Every other route into welcome — the all-created receipt, the 409 idempotent
/// replay, a landed start with nothing to itemise — has nothing outstanding, and
/// must not carry the notice: a warning on a clean signup is the mirror-image
/// lie.
void main() {
  late _MockKioskFlowCubit flow;
  late _MockKioskSignupCubit signup;

  setUp(() {
    selectedGym.setActiveGym(
      gymId: 'gym-1',
      displayName: 'Iron Den',
      role: EmployeeRole.owner,
      timezone: 'America/Chicago',
      logoUrl: null,
      stripeAccountId: 'acct_iron',
    );
    flow = _MockKioskFlowCubit();
    // No warmed catalogues: the showcase drops out and the app card carries the
    // screen alone, which keeps this test about the greeting band.
    when(() => flow.state)
        .thenReturn(const KioskFlowState(view: KioskView.signup));
    signup = _MockKioskSignupCubit();
  });

  Future<void> pumpWelcome(
    WidgetTester tester, {
    required bool afterPartial,
  }) async {
    when(() => signup.state).thenReturn(
      KioskSignupState(
        step: KioskSignupStep.welcome,
        welcomeCountdown: kKioskSignupWelcomeHold.inSeconds,
        welcomeAfterPartial: afterPartial,
        persons: const [
          KioskSignupPerson(
            memberId: 'mem-1',
            firstName: 'Marcus',
            lastName: 'Bell',
            email: 'marcus.bell@gmail.com',
            isPayer: true,
          ),
        ],
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        // The kiosk SURFACE's scale, mounted the way `KioskSignupScreen`
        // does: the shared flow components carry no size of their own.
        builder: (context, child) => MembershipFlowTheme(
          scale: const MembershipFlowScale.kiosk(),
          copy: const KioskFlowCopy(),
          child: child!,
        ),
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<KioskSignupCubit>.value(value: signup),
              BlocProvider<KioskFlowCubit>.value(value: flow),
            ],
            child: const KioskWelcomeScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('arriving from a PARTIAL names the front desk under the greeting',
      (tester) async {
    await pumpWelcome(tester, afterPartial: true);

    // The welcome still welcomes them — they are a member of this gym.
    expect(find.text('Welcome to Iron Den, Marcus!'), findsOneWidget);
    // And the one thing the greeting cannot say on its own.
    expect(find.byType(FlowInlineNotice), findsOneWidget);
    expect(
      find.text('Some memberships didn\'t go through — ask the front desk to '
          'finish them.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an all-created welcome carries no notice at all',
      (tester) async {
    await pumpWelcome(tester, afterPartial: false);

    expect(find.text('Welcome to Iron Den, Marcus!'), findsOneWidget);
    expect(find.byType(FlowInlineNotice), findsNothing);
    expect(find.textContaining('front desk'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
