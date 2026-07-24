import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_field_box.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_payer_waiver_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_waiver_step.dart';
import 'package:crm/features/member_details/data/models/authorized_payer_waiver.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_payment_method_status.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/data/models/members_management_response.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/membership_plan_price_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/models/waiver_signature_response.dart';
import 'package:crm/features/memberships/data/models/waiver_type.dart';
import 'package:crm/features/memberships/data/models/waiver_version_response.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

class _MockMemberRepository extends Mock implements MemberRepository {}

class _MockMembershipsRepository extends Mock
    implements MembershipsRepository {}

class _MockMembersListRepository extends Mock
    implements MembersListRepository {}

class _MockKioskSessionCubit extends Mock implements KioskSessionCubit {}

class _MockManagementResponse extends Mock
    implements MembersManagementResponse {}

class _MockSignatureResponse extends Mock implements WaiverSignatureResponse {}

/// **A signature must be a fresh, deliberate act — the name field CLEARS on
/// every new waiver.** (Founder ruling; legal-integrity invariant.)
///
/// The signer-name field carrying text from a previous waiver — the same
/// person's last document, a republished version, or (worst, on a shared
/// front-desk iPad) a *different* person's — would let someone "sign" a waiver
/// they never actually typed their name on. So every time a new waiver body
/// loads, the typed legal name (and the consent tick) is wiped.
///
/// These tests hold that invariant across the real transitions the group flow
/// makes: the same person's next waiver, the next person's first waiver, and
/// the payer signing consecutive payer-auth agreements.
void main() {
  late KioskSignupCubit cubit;
  late _MockMemberRepository member;
  late _MockMembershipsRepository memberships;
  late int createSeq;

  setUpAll(() {
    registerFallbackValue(
      const MembersManagementCreateRequest(
        gymId: 'gym-1',
        firstName: 'a',
        lastName: 'b',
      ),
    );
    registerFallbackValue(const MembersManagementUpdateRequest());
    registerFallbackValue(
      const MemberMembershipsStartRequest(
        payerMemberId: 'm',
        gymId: 'gym-1',
        idempotencyKey: 'k',
        memberships: [],
      ),
    );
  });

  setUp(() {
    selectedGym.setActiveGym(
      gymId: 'gym-1',
      displayName: 'Iron Den',
      role: EmployeeRole.owner,
      timezone: 'America/Chicago',
      logoUrl: null,
      stripeAccountId: 'acct_iron',
    );
    createSeq = 0;
    memberships = _MockMembershipsRepository();
    // Each waiver read returns a distinct document for the id asked for, so a
    // move between two waivers is a real `state.waiver` change.
    when(() => memberships.getWaiver(any(), any())).thenAnswer(
      (inv) async => _waiver(inv.positionalArguments[0] as String),
    );
    when(
      () => memberships.recordWaiverSignature(
        waiverId: any(named: 'waiverId'),
        gymId: any(named: 'gymId'),
        memberId: any(named: 'memberId'),
        waiverVersionId: any(named: 'waiverVersionId'),
        signerName: any(named: 'signerName'),
      ),
    ).thenAnswer((_) async => _MockSignatureResponse());
    member = _MockMemberRepository();
    when(() => member.createMember(any()))
        .thenAnswer((_) async => 'mem-${++createSeq}');
    when(() => member.updateMember(any(), any()))
        .thenAnswer((_) async => _MockManagementResponse());
    when(() => member.getPaymentMethodStatus(any())).thenAnswer(
      (_) async => const MemberPaymentMethodStatus(hasPaymentMethod: false),
    );
    when(() => member.getAuthorizedPayerWaiver(any())).thenAnswer(
      (_) async => const AuthorizedPayerWaiver(
        waiverId: 'payer-waiver-1',
        versionId: 'payer-ver-1',
        name: 'Authorized Payer Agreement',
        body: 'I authorise myself to pay for {{payee_name}}.',
      ),
    );
    when(
      () => member.linkMemberAccount(
        any(),
        payerMemberId: any(named: 'payerMemberId'),
        waiverVersionId: any(named: 'waiverVersionId'),
        signerName: any(named: 'signerName'),
        consentAcknowledged: any(named: 'consentAcknowledged'),
      ),
    ).thenAnswer((_) async {});
  });

  /// Built inside the test body, never `setUp`: the constructor warms the plan
  /// catalogue, and a future started in the enclosing zone is not drained by
  /// the widget test's fake clock.
  KioskSignupCubit newCubit() => KioskSignupCubit(
        memberRepository: member,
        membershipsRepository: memberships,
        membersListRepository: _MockMembersListRepository(),
        session: _MockKioskSessionCubit(),
        gymId: 'gym-1',
      );

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<KioskSignupCubit>.value(
            value: cubit,
            child: child,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> createPayer() async {
    cubit = newCubit();
    cubit.submitDetails(
      firstName: 'Marcus',
      lastName: 'Bell',
      email: 'marcus.bell@gmail.com',
    );
    await cubit.submitExtraDetails();
  }

  Future<void> addPerson(String first, String last) async {
    await cubit.addPerson(
      firstName: first,
      lastName: last,
      email: '${first.toLowerCase()}.${last.toLowerCase()}@gmail.com',
    );
    cubit.skipPersonDetails();
  }

  /// The signer-name field's current text — the field's controller IS the
  /// step's `_signerName`, so this is exactly what a member would see typed.
  String signerText(WidgetTester tester) =>
      tester.widget<KioskFieldBox>(find.byType(KioskFieldBox)).controller.text;

  Finder signerField() => find.descendant(
        of: find.byType(KioskFieldBox),
        matching: find.byType(TextField),
      );

  testWidgets(
      'the SECOND waiver for the SAME person loads with an EMPTY name field',
      (tester) async {
    // One plan, two liability waivers — the same person signs twice.
    when(() => memberships.listPlans(any()))
        .thenAnswer((_) async => [_plan(const ['waiver-1', 'waiver-2'])]);

    await createPayer(); // solo
    cubit.continueToPlans();
    cubit.selectPlan('plan-1');
    cubit.continueFromPlans(); // enters the waiver run, loads waiver-1

    await pump(tester, const KioskWaiverStep());
    await tester.pump();
    expect(cubit.state.currentWaiverId, 'waiver-1');
    expect(find.byType(KioskFieldBox), findsOneWidget);

    // The member types their legal name and signs.
    await tester.enterText(signerField(), 'Marcus Bell');
    await tester.pump();
    expect(signerText(tester), 'Marcus Bell');

    await cubit.signWaiver(signerName: 'Marcus Bell'); // → waiver-2 loads
    await tester.pump();
    await tester.pump();
    expect(cubit.state.currentWaiverId, 'waiver-2');

    // THE INVARIANT: the second document opens with nothing pre-typed.
    expect(find.byType(KioskFieldBox), findsOneWidget);
    expect(signerText(tester), isEmpty);
    await cubit.close();
  });

  testWidgets(
      'the NEXT person\'s waiver loads with an EMPTY name field',
      (tester) async {
    // A group: a payee's liability waiver is followed by the payer's own, both
    // rendered by the SAME KioskWaiverStep instance — the cross-person leak.
    when(() => memberships.listPlans(any()))
        .thenAnswer((_) async => [_plan(const ['waiver-1'])]);

    await createPayer(); // Marcus, the payer
    await addPerson('Ella', 'Bell'); // a payee
    cubit.continueToPlans();
    cubit.selectPlan('plan-1');
    cubit.continueFromPlans();
    cubit.selectPlan('plan-1');
    cubit.continueFromPlans(); // waiver run → Ella's payer-auth first

    await pump(tester, const KioskWaiverStep());
    await tester.pump();
    // Sign Ella's payer-auth link so her OWN liability waiver loads.
    await cubit.signPayerAuth(signerName: 'Marcus Bell');
    await tester.pump();
    await tester.pump();
    expect(cubit.state.payerAuthPending, isFalse);
    expect(cubit.state.activePersonIndex, 1); // Ella
    expect(find.byType(KioskFieldBox), findsOneWidget);

    // A name is typed on Ella's waiver.
    await tester.enterText(signerField(), 'Marcus Bell');
    await tester.pump();
    expect(signerText(tester), 'Marcus Bell');

    // Sign it → the PAYER's own liability waiver loads in the same widget.
    await cubit.signWaiver(signerName: 'Marcus Bell');
    await tester.pump();
    await tester.pump();
    expect(cubit.state.activePersonIndex, 0); // Marcus now

    // THE INVARIANT: a different person's typed name never carries over.
    expect(find.byType(KioskFieldBox), findsOneWidget);
    expect(signerText(tester), isEmpty);
    await cubit.close();
  });

  testWidgets(
      'the payer-auth agreement for the NEXT payee loads with an EMPTY '
      'name field',
      (tester) async {
    // Two payees on a plan with NO liability waivers, so the payer signs two
    // payer-auth agreements back to back in the SAME KioskPayerWaiverStep.
    when(() => memberships.listPlans(any()))
        .thenAnswer((_) async => [_plan(const <String>[])]);

    await createPayer(); // Marcus, the payer
    await addPerson('Ella', 'Bell'); // payee 1
    await addPerson('Theo', 'Bell'); // payee 2
    cubit.continueToPlans();
    cubit.selectPlan('plan-1');
    cubit.continueFromPlans();
    cubit.selectPlan('plan-1');
    cubit.continueFromPlans();
    cubit.selectPlan('plan-1');
    cubit.continueFromPlans(); // waiver run → Ella's payer-auth first

    await pump(tester, const KioskPayerWaiverStep());
    await tester.pump();
    expect(cubit.state.payerAuthPending, isTrue);
    expect(cubit.state.activePersonIndex, 1); // Ella
    expect(find.byType(KioskFieldBox), findsOneWidget);

    // The payer types their name to authorise Ella.
    await tester.enterText(signerField(), 'Marcus Bell');
    await tester.pump();
    expect(signerText(tester), 'Marcus Bell');

    // Authorise Ella → the payer-auth agreement for Theo loads next.
    await cubit.signPayerAuth(signerName: 'Marcus Bell');
    await tester.pump();
    await tester.pump();
    expect(cubit.state.payerAuthPending, isTrue);
    expect(cubit.state.activePersonIndex, 2); // Theo now

    // THE INVARIANT: even the same payer's second authorisation opens empty.
    expect(find.byType(KioskFieldBox), findsOneWidget);
    expect(signerText(tester), isEmpty);
    await cubit.close();
  });
}

MembershipPlanResponse _plan(List<String> waiverIds) => MembershipPlanResponse(
      planId: 'plan-1',
      gymId: 'gym-1',
      planName: 'Unlimited',
      imageUrl: '',
      planType: PlanType.recurring,
      durationAmount: 1,
      isPublic: true,
      createdAt: DateTime.utc(2026),
      waiverIds: waiverIds,
      activePrice: MembershipPlanPriceResponse(
        priceId: 'price-1',
        planId: 'plan-1',
        gymId: 'gym-1',
        stripePriceId: 'price_stripe_1',
        price: 14900,
        isActive: true,
        createdAt: DateTime.utc(2026),
      ),
    );

/// A distinct waiver per id, so a move between two of them is a real change.
WaiverResponse _waiver(String id) => WaiverResponse(
      waiverId: id,
      gymId: 'gym-1',
      name: 'Liability Waiver ($id)',
      waiverType: WaiverType.custom,
      currentVersionId: '$id-ver-1',
      currentVersionNumber: 1,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      currentVersion: WaiverVersionResponse(
        versionId: '$id-ver-1',
        waiverId: id,
        gymId: 'gym-1',
        versionNumber: 1,
        body: 'I agree, {{signer_name}}.',
        contentHash: 'hash-$id',
        createdAt: DateTime.utc(2026),
      ),
    );
