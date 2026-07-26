import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/login/bloc/login_bloc.dart';
import 'package:mobile_app/features/login/bloc/login_event.dart';
import 'package:mobile_app/features/login/bloc/login_state.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';
import 'package:mobile_app/features/member_select/presentation/widgets/identity_sheet.dart';
import 'package:mobile_app/features/member_select/presentation/widgets/member_row.dart';
import 'package:mobile_app/shared/widgets/dialogs/sign_out_dialog.dart';
import 'package:mobile_app/shared/widgets/topbar/topbar_identity_avatar.dart';

class _MockLoginBloc extends MockBloc<LoginEvent, LoginState>
    implements LoginBloc {}

const MemberIdentity _current = MemberIdentity(
  memberId: 'm1',
  gymId: 'g1',
  gymName: 'Iron Fist MMA',
  firstName: 'Jesse',
  lastName: 'Musa',
);

const MemberIdentity _other = MemberIdentity(
  memberId: 'm2',
  gymId: 'g2',
  gymName: 'Southside BJJ',
  firstName: 'Riley',
  lastName: 'Chen',
);

Widget _host({required LoginBloc bloc, MembersLoader? loadMembers}) {
  return MaterialApp(
    home: BlocProvider<LoginBloc>.value(
      value: bloc,
      child: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              onTap: () =>
                  IdentitySheet.show(context, loadMembers: loadMembers),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late _MockLoginBloc bloc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    bloc = _MockLoginBloc();
    whenListen(
      bloc,
      const Stream<LoginState>.empty(),
      initialState: const LoginUnauthenticated(),
    );
    await selectedMember.select(
      memberId: _current.memberId,
      gymId: _current.gymId,
      gymName: _current.gymName,
      firstName: _current.firstName,
      lastName: _current.lastName,
    );
  });

  tearDown(() async {
    await selectedMember.reset();
  });

  group('IdentitySheet', () {
    testWidgets('opens instantly on the cached identity while the list loads',
        (tester) async {
      final pending = Completer<List<MemberIdentity>>();
      await tester.pumpWidget(
        _host(bloc: bloc, loadMembers: () => pending.future),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Identity and sign-out are up immediately — no spinner over identity.
      expect(find.text('Jesse Musa'), findsOneWidget);
      expect(find.text('Iron Fist MMA'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      // Only the list area is still loading, as placeholder blocks.
      expect(find.byType(MemberRow), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      pending.complete(const [_current]);
      await tester.pumpAndSettle();
    });

    testWidgets('a single profile shows no switch section', (tester) async {
      await tester.pumpWidget(
        _host(bloc: bloc, loadMembers: () async => const [_current]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Switch profile'), findsNothing);
      expect(find.byType(MemberRow), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('2+ profiles list the OTHERS, excluding the current one',
        (tester) async {
      await tester.pumpWidget(
        _host(bloc: bloc, loadMembers: () async => const [_current, _other]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Switch profile'), findsOneWidget);
      expect(find.byType(MemberRow), findsOneWidget);
      expect(find.text('Riley Chen'), findsOneWidget);
      // The current member appears once — in the header, not as a switch row.
      expect(find.text('Jesse Musa'), findsOneWidget);
    });

    testWidgets('a failed list keeps sign-out usable and offers a retry',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _host(
          bloc: bloc,
          loadMembers: () async {
            calls++;
            throw Exception('offline');
          },
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text("Can't load your other profiles."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Jesse Musa'), findsOneWidget);
      expect(calls, 1);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2);

      // Sign-out still works on the failed sheet — non-negotiable offline.
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.byType(SignOutDialog), findsOneWidget);
      expect(find.byType(IdentitySheet), findsNothing);
    });

    testWidgets('sign out dismisses the sheet, then confirms', (tester) async {
      await tester.pumpWidget(
        _host(bloc: bloc, loadMembers: () async => const [_current]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      // The sheet is gone BEFORE the confirmation opens.
      expect(find.byType(IdentitySheet), findsNothing);
      expect(find.byType(SignOutDialog), findsOneWidget);

      // Backing out dispatches nothing.
      await tester.tap(find.text('Stay signed in'));
      await tester.pumpAndSettle();
      verifyNever(() => bloc.add(const LoginSignOutRequested()));

      // Confirming does.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      verify(() => bloc.add(const LoginSignOutRequested())).called(1);
    });

    testWidgets('the topbar avatar opens the sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<LoginBloc>.value(
            value: bloc,
            child: const Scaffold(
              body: Center(
                child: TopbarIdentityAvatar(
                  gymName: 'Iron Fist MMA',
                  memberName: 'Jesse Musa',
                  firstName: 'Jesse',
                  lastName: 'Musa',
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TopbarIdentityAvatar));
      await tester.pumpAndSettle();

      expect(find.byType(IdentitySheet), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });
  });
}
