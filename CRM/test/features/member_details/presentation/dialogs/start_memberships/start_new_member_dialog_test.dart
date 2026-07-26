import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/bloc/member_create_bloc.dart';
import 'package:crm/features/member_details/bloc/member_create_event.dart';
import 'package:crm/features/member_details/bloc/member_create_state.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/duplicate_member_panel.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/authorize_direction.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_new_member_dialog.dart';

class _MockMemberCreateBloc
    extends MockBloc<MemberCreateEvent, MemberCreateState>
    implements MemberCreateBloc {}

class _MockMemberDetailBloc
    extends MockBloc<MemberDetailEvent, MemberDetailState>
    implements MemberDetailBloc {}

void main() {
  const match = DuplicateMemberMatch(
    memberId: 'existing-1',
    firstName: 'Jo',
    lastName: 'Doe',
    email: 'jo@example.com',
  );

  final duplicate = MemberCreateDuplicate(
    matches: const [match],
    pendingRequest: const MembersManagementCreateRequest(
      sendInvite: true,
      gymId: 'gym-1',
      firstName: 'Jo',
      lastName: 'Doe',
      email: 'jo@example.com',
    ),
  );

  late _MockMemberCreateBloc createBloc;
  late _MockMemberDetailBloc detailBloc;

  setUpAll(() {
    // The dialog builds an ApiClient in its state initializer, which reads
    // API_BASE_URL from dotenv.
    dotenv.loadFromString(
      envString: 'API_BASE_URL=http://localhost:8000',
    );
  });

  setUp(() {
    createBloc = _MockMemberCreateBloc();
    detailBloc = _MockMemberDetailBloc();
    // The create bloc lands on the duplicate gate right after the dialog opens.
    whenListen(
      createBloc,
      Stream<MemberCreateState>.value(duplicate),
      initialState: const MemberCreateIdle(),
    );
    whenListen(
      detailBloc,
      const Stream<MemberDetailState>.empty(),
      initialState: const MemberDetailLoading(),
    );
  });

  /// Opens the payer-direction dialog (anchor = launch member, the payee)
  /// over a launcher button, capturing what it pops with.
  Future<void> openDialog(
    WidgetTester t, {
    required Set<String> relatedIds,
    required void Function(StartNewMemberResult?) onResult,
  }) async {
    // Room for the wide (1100) dialog surface.
    await t.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              onResult(await showDialog<StartNewMemberResult>(
                context: context,
                builder: (_) => MultiBlocProvider(
                  providers: [
                    BlocProvider<MemberCreateBloc>.value(value: createBloc),
                    BlocProvider<MemberDetailBloc>.value(value: detailBloc),
                  ],
                  child: StartNewMemberDialog(
                    direction: AuthorizeDirection.addPayer,
                    anchorMemberId: 'launch',
                    anchorName: 'Pat Payee',
                    gymId: 'gym-1',
                    relatedIds: relatedIds,
                  ),
                ),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  // The founder's spec-4 branch, end to end in the payer direction: the SAME
  // duplicate warning as every create path renders inside the payer-flavored
  // dialog, and "Use existing member" for a match that is ALREADY a payer
  // resolves to a direct select (committedLink: false) — the wizard then
  // just selects them as the run's payer, no new authorization.
  testWidgets(
      'payer flow: duplicate → use existing (already a payer) selects '
      'directly', (t) async {
    StartNewMemberResult? result;
    await openDialog(
      t,
      // 'existing-1' is already an authorized payer of the launch member.
      relatedIds: const {'launch', 'existing-1'},
      onResult: (r) => result = r,
    );

    // The shared duplicate warning + matched member card render inside this
    // (payer-direction) dialog.
    expect(find.text('Possible duplicate'), findsOneWidget);
    expect(find.byType(DuplicateMemberPanel), findsOneWidget);
    expect(find.text('Jo Doe'), findsOneWidget);

    await t.tap(find.text('Use existing member'));
    await t.pumpAndSettle();

    // Popped with the existing member as a DIRECT select — no new
    // authorization committed.
    expect(result, isNotNull);
    expect(result!.memberId, 'existing-1');
    expect(result!.committedLink, isFalse);
  });

  // The inverse branch: a duplicate match NOT yet authorized routes into the
  // authorize-sign chain (the picked payer signs the launch member's waiver)
  // instead of direct-selecting. The waiver fetch itself fails here (no
  // backend in tests), which surfaces the sign phase's retryable error —
  // proving the routing without mocking the repository.
  testWidgets(
      'payer flow: duplicate → use existing (not yet a payer) enters the '
      'authorize chain', (t) async {
    StartNewMemberResult? result;
    await openDialog(
      t,
      // 'existing-1' is NOT among the launch member's payers.
      relatedIds: const {'launch'},
      onResult: (r) => result = r,
    );

    await t.tap(find.text('Use existing member'));
    await t.pumpAndSettle();

    // Advanced to the authorize/sign phase — the dialog stays open (nothing
    // popped) and shows the sign step (here its waiver-load error, as no
    // backend is reachable in tests). "Authorize payer" appears as both the
    // dialog title and the sign footer's confirm button.
    expect(result, isNull);
    expect(find.text('Authorize payer'), findsWidgets);
    expect(
      find.text("We couldn't load the waiver. Please try again."),
      findsOneWidget,
    );
  });
}
