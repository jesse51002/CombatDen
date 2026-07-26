import 'package:mocktail/mocktail.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_price_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/models/waiver_type.dart';
import 'package:crm/features/memberships/data/models/waiver_version_response.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

/// Fixtures for the staff membership-wizard suite. Nothing here hits a live
/// backend — every repository is a mock and every model is built by hand.
class MockMemberRepository extends Mock implements MemberRepository {}

class MockMembershipsRepository extends Mock
    implements MembershipsRepository {}

const kGymId = 'gym-1';

/// A gym plan. Defaults to a priced, public recurring plan — the shape the
/// catalogue policy actually offers.
MembershipPlanResponse plan({
  String planId = 'plan-1',
  String priceId = 'price-1',
  String name = 'Unlimited',
  PlanType type = PlanType.recurring,
  int price = 10000,
  bool isPublic = true,
  bool priced = true,
  List<String> waiverIds = const [],
  int? classCount,
}) =>
    MembershipPlanResponse(
      planId: planId,
      gymId: kGymId,
      planName: name,
      imageUrl: 'https://cdn.example/plan.png',
      planType: type,
      classCount: classCount,
      durationAmount: 1,
      isPublic: isPublic,
      createdAt: DateTime.utc(2026),
      waiverIds: waiverIds,
      activePrice: priced
          ? MembershipPlanPriceResponse(
              priceId: priceId,
              planId: planId,
              gymId: kGymId,
              stripePriceId: 'stripe_$priceId',
              price: price,
              isActive: true,
              createdAt: DateTime.utc(2026),
            )
          : null,
    );

/// One membership a person already holds — the input the plan gates read.
MembershipInfo held({
  String planId = 'plan-1',
  String planType = 'recurring',
  MembershipStatus status = MembershipStatus.active,
  String memberId = 'm-payer',
}) =>
    MembershipInfo(
      planId: planId,
      planName: 'Held',
      planType: planType,
      status: status,
      itemId: 'item-$planId',
      paidByMemberId: memberId,
      baseCost: 10000,
      durationAmount: 1,
      durationUnit: 'month',
      totalPrice: 10000,
      startDate: DateTime.utc(2026),
    );

MemberDetailResponse detail({
  String memberId = 'm-payer',
  String firstName = 'Marcus',
  String lastName = 'Bell',
  List<LinkedAccount> authorizedToPayFor = const [],
  List<LinkedAccount> authorizedPayers = const [],
  List<MembershipInfo> memberships = const [],
  CardOnFile? card,
}) =>
    MemberDetailResponse(
      memberId: memberId,
      gymId: kGymId,
      firstName: firstName,
      lastName: lastName,
      membershipOverview: 'Active',
      totalMonthlyRecurringPrice: 0,
      totalMembershipCount: memberships.length,
      personalInfo: PersonalInfo(email: '$firstName@bell.family'),
      authorizedPayers: authorizedPayers,
      authorizedToPayFor: authorizedToPayFor,
      memberships: memberships,
      retention: const Retention(
        classStreakWeeks: 0,
        pointsBalance: 0,
        videosWatched: 0,
      ),
      cardOnFile: card,
    );

LinkedAccount linked({
  required String memberId,
  String firstName = 'Ella',
  String lastName = 'Bell',
}) =>
    LinkedAccount(
      memberId: memberId,
      firstName: firstName,
      lastName: lastName,
    );

const CardOnFile savedCard = CardOnFile(
  brand: 'visa',
  lastFour: '4242',
  expMonth: 1,
  expYear: 2030,
);

MemberMembershipsStartResultItem resultItem({
  required String memberId,
  required String planId,
  MemberMembershipsStartStatus status = MemberMembershipsStartStatus.created,
  PlanType planType = PlanType.recurring,
}) =>
    MemberMembershipsStartResultItem(
      memberId: memberId,
      planId: planId,
      planType: planType,
      status: status,
      itemId: status == MemberMembershipsStartStatus.created ? 'item-1' : null,
      error: status == MemberMembershipsStartStatus.failed
          ? 'card declined: The card could not be charged.'
          : null,
    );

MemberMembershipsStartResponse startResponse(
  List<MemberMembershipsStartResultItem> results, {
  int chargeCount = 1,
  bool multipleCharges = false,
}) =>
    MemberMembershipsStartResponse(
      results: results,
      chargeCount: chargeCount,
      multipleCharges: multipleCharges,
    );

PreviewInvoice invoice({
  int total = 10000,
  bool proration = false,
  int? nextPaymentDate,
}) =>
    PreviewInvoice(
      amountDue: total,
      subtotal: total,
      total: total,
      currency: 'usd',
      nextPaymentDate: nextPaymentDate,
      lines: [
        PreviewInvoiceLine(
          amount: total,
          discountedAmount: total,
          isProration: proration,
        ),
      ],
    );

MemberMembershipsStartPreview startPreview({
  PreviewInvoice? oneTime,
  PreviewInvoice? dueNow,
  PreviewInvoice? recurring,
}) =>
    MemberMembershipsStartPreview(
      oneTime: oneTime,
      dueNow: dueNow,
      recurring: recurring,
    );

WaiverResponse waiver({
  String waiverId = 'waiver-1',
  String versionId = 'version-1',
  String name = 'Liability release',
}) =>
    WaiverResponse(
      waiverId: waiverId,
      gymId: kGymId,
      name: name,
      waiverType: WaiverType.custom,
      currentVersionId: versionId,
      currentVersionNumber: 1,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      currentVersion: WaiverVersionResponse(
        versionId: versionId,
        waiverId: waiverId,
        gymId: kGymId,
        versionNumber: 1,
        body: 'Body',
        contentHash: 'hash-$versionId',
        requiresResign: false,
        createdAt: DateTime.utc(2026),
      ),
    );

/// The mocktail fallbacks the suite's `any()` matchers need.
void registerWizardFallbacks() {
  registerFallbackValue(
    const MemberMembershipsStartRequest(
      payerMemberId: 'm',
      gymId: kGymId,
      idempotencyKey: 'k',
      memberships: [],
    ),
  );
}

/// A cubit wired to [member] / [memberships], with a key source that makes
/// "a NEW key" a real assertion rather than an artefact of a constant stub.
MembershipWizardCubit buildWizard({
  required MockMemberRepository member,
  required MockMembershipsRepository memberships,
  required MemberDetailResponse launchMember,
  Set<String>? initialTrainingMemberIds,
  int keySeed = 0,
}) {
  var seq = keySeed;
  return MembershipWizardCubit(
    memberRepository: member,
    membershipsRepository: memberships,
    launchMember: launchMember,
    initialTrainingMemberIds: initialTrainingMemberIds,
    uuid: () => 'key-${++seq}',
  );
}
