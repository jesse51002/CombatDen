import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_freeze_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_mark_paid_cash_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_unfreeze_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_add_discounts_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_remove_discounts_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_update_price_request.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/models/members_management_link_check_response.dart';
import 'package:crm/features/member_details/data/models/members_management_link_request.dart';
import 'package:crm/features/member_details/data/models/members_management_response.dart';
import 'package:crm/features/member_details/data/models/members_management_update_card_request.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_response.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_response.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';

/// Repository for member detail data access.
///
/// Every call goes through the FastAPI backend via
/// [ApiClient]; paths and shapes match the merged
/// `Database/openapi.json` contract (member-id keyed).
class MemberRepository {
  final ApiClient _apiClient;

  MemberRepository({
    required ApiClient apiClient,
  }) : _apiClient = apiClient;

  // ----- Member detail + sidebar -----

  /// `GET /api/v1/members/{member_id}/billing` — the
  /// billing-rich member detail (memberships, charges,
  /// card, linked accounts, retention).
  Future<MemberDetailResponse> getMemberDetail(
    String memberId,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/members/$memberId/billing',
    );
    return MemberDetailResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Lightweight roster for the right sidebar member
  /// picker.
  ///
  /// Re-keyed to `POST /api/v1/members/list` (the merged
  /// contract has no direct `user_gym_profiles` read);
  /// maps each [MemberRow] to a [MemberSummary]. Pages
  /// through the full list for the gym.
  Future<List<MemberSummary>> getAllMembers(
    String gymId, {
    int pageSize = 200,
  }) async {
    final summaries = <MemberSummary>[];
    var startIndex = 0;
    while (true) {
      final response = await _apiClient.post(
        '/api/v1/members/list',
        data: CrmMembersListRequest(
          gymId: gymId,
          prevView: MembersListView.all,
          requestedView: MembersListView.all,
          count: pageSize,
          startIndex: startIndex,
        ).toJson(),
      );
      final page = CrmMembersListResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
      summaries.addAll(page.data.map(_rowToSummary));
      startIndex += page.data.length;
      if (page.data.isEmpty ||
          page.data.length < pageSize) {
        break;
      }
    }
    return summaries;
  }

  MemberSummary _rowToSummary(MemberRow row) {
    // AllViewRow has a pre-formatted `name` field;
    // other view rows also carry `name`.
    final parts = row.name.split(' ');
    final first = parts.isNotEmpty ? parts.first : '';
    final last =
        parts.length > 1 ? parts.sublist(1).join(' ') : '';
    return MemberSummary(
      memberId: row.memberId,
      firstName: first,
      lastName: last,
      photoUrl: row.avatarUrl,
    );
  }

  // ----- Member profile / billing management -----

  /// `PUT /api/v1/members/{member_id}` — update member
  /// identity + lifecycle fields (the request already
  /// wraps its body in the merged `{data: {...}}`
  /// envelope).
  Future<MembersManagementResponse> updateMember(
    String memberId,
    MembersManagementUpdateRequest req,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/members/$memberId',
      data: req.toJson(),
    );
    return MembersManagementResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `PUT /api/v1/members/{member_id}/card`.
  Future<MembersManagementResponse> updateMemberCard(
    String memberId,
    String paymentMethodId,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/members/$memberId/card',
      data: MembersManagementUpdateCardRequest(
        paymentMethodId: paymentMethodId,
      ).toJson(),
    );
    return MembersManagementResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `DELETE /api/v1/members/{member_id}/payment`.
  Future<MembersManagementResponse> unlinkMemberPayment(
    String memberId,
  ) async {
    final response = await _apiClient.delete(
      '/api/v1/members/$memberId/payment',
    );
    return MembersManagementResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `PUT /api/v1/members/{member_id}/link` — link the
  /// member to a paying parent account. A pure DB change
  /// (the member has no active recurring memberships, so
  /// nothing is re-billed); the endpoint returns no body,
  /// so callers refetch member detail afterward.
  Future<void> linkMemberAccount(
    String memberId,
    String parentMemberId,
  ) async {
    await _apiClient.put(
      '/api/v1/members/$memberId/link',
      data: MembersManagementLinkRequest(
        parentMemberId: parentMemberId,
      ).toJson(),
    );
  }

  /// `POST /api/v1/members/{member_id}/link/check`.
  Future<MembersManagementLinkCheckResponse>
      checkLinkMemberAccount(
    String memberId,
    String parentMemberId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/members/$memberId/link/check',
      data: MembersManagementLinkRequest(
        parentMemberId: parentMemberId,
      ).toJson(),
    );
    return MembersManagementLinkCheckResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `DELETE /api/v1/members/{member_id}/link` — unlink the
  /// member from their paying parent account. A pure DB
  /// change; the endpoint returns no body, so callers
  /// refetch member detail afterward.
  Future<void> unlinkMemberAccount(
    String memberId,
  ) async {
    await _apiClient.delete(
      '/api/v1/members/$memberId/link',
    );
  }

  /// `GET /api/v1/members/{member_id}/invoices`.
  Future<List<PaymentsInvoiceResponse>>
      listMemberInvoices(
    String memberId, {
    int limit = 100,
    String? startingAfter,
  }) async {
    final response = await _apiClient.get(
      '/api/v1/members/$memberId/invoices',
      queryParameters: {
        'limit': limit,
        'starting_after': ?startingAfter,
      },
    );
    return (response.data as List<dynamic>)
        .map(
          (e) => PaymentsInvoiceResponse.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  /// `GET /api/v1/members/{member_id}/payments` — one page of the
  /// member's payment history: the charges that paid for any membership
  /// this member has held, plus their own direct charges, newest first.
  Future<List<PaymentRecord>> getPayments(
    String memberId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _apiClient.get(
      '/api/v1/members/$memberId/payments',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return (response.data as List<dynamic>)
        .map(
          (e) =>
              PaymentRecord.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  /// `GET /api/v1/members/{member_id}/upcoming-invoice`.
  ///
  /// Returns null when the member's account has no recurring
  /// subscription (the endpoint responds with a null body).
  Future<PreviewInvoice?> getUpcomingInvoice(
    String memberId,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/members/$memberId/upcoming-invoice',
    );
    if (response.data == null) return null;
    return PreviewInvoice.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  // ----- Member memberships -----

  /// `POST /api/v1/member_memberships/` — start a payer's
  /// family memberships in one request. Returns the
  /// per-membership created/failed breakdown (a 201 is NOT
  /// success/fail — inspect each result).
  Future<MemberMembershipsStartResponse> startMemberships(
    MemberMembershipsStartRequest req,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/member_memberships/',
      data: req.toJson(),
    );
    return MemberMembershipsStartResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `POST /api/v1/member_memberships/preview` — stage the
  /// same start request (discounts included) and return the
  /// three-way one-time / due-now / recurring split without
  /// committing anything.
  Future<MemberMembershipsStartPreview>
      previewStartMemberships(
    MemberMembershipsStartRequest req,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/member_memberships/preview',
      data: req.toJson(),
    );
    return MemberMembershipsStartPreview.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `DELETE /api/v1/member_memberships/` — cancel a
  /// membership item. The merged contract takes
  /// `item_id`, `member_id`, and `idempotency_key` as
  /// query params.
  Future<void> cancelMembership({
    required String itemId,
    required String memberId,
    required String idempotencyKey,
  }) async {
    try {
      await _apiClient.delete(
        '/api/v1/member_memberships/'
        '?item_id=$itemId'
        '&member_id=$memberId'
        '&idempotency_key=$idempotencyKey',
      );
    } on ServerException catch (e) {
      if (e.statusCode == 409) {
        throw MembershipInTaskException(
          e.detail ??
              'This membership is part of an in-progress upgrade task.',
        );
      }
      rethrow;
    }
  }

  /// `POST /api/v1/member_memberships/cancel/preview`.
  Future<DueNowVsRecurringPreview?>
      previewCancelMembership(
    String itemId,
    String memberId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/member_memberships/cancel/preview'
      '?item_id=$itemId&member_id=$memberId',
    );
    if (response.data == null) return null;
    return DueNowVsRecurringPreview.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `PUT /api/v1/member_memberships/price`.
  Future<void> updateMembershipPrice(
    MemberMembershipsUpdatePriceRequest req,
  ) async {
    try {
      await _apiClient.put(
        '/api/v1/member_memberships/price',
        data: req.toJson(),
      );
    } on ServerException catch (e) {
      if (e.statusCode == 409) {
        throw MembershipInTaskException(
          e.detail ??
              'This membership is part of an in-progress upgrade task.',
        );
      }
      rethrow;
    }
  }

  /// `POST /api/v1/member_memberships/price/preview`.
  Future<DueNowVsRecurringPreview?>
      previewUpdateMembershipPrice(
    MemberMembershipsUpdatePriceRequest req,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/member_memberships/price/preview',
      data: req.toJson(),
    );
    if (response.data == null) return null;
    return DueNowVsRecurringPreview.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `POST /api/v1/member_memberships/freeze`.
  Future<void> freezeAccount(
    MemberMembershipsFreezeRequest req,
  ) async {
    try {
      await _apiClient.post(
        '/api/v1/member_memberships/freeze',
        data: req.toJson(),
      );
    } on ServerException catch (e) {
      if (e.statusCode == 409) {
        throw MembershipInTaskException(
          e.detail ??
              'This membership is part of an in-progress upgrade task.',
        );
      }
      rethrow;
    }
  }

  /// `POST /api/v1/member_memberships/unfreeze`.
  Future<void> unfreezeAccount(
    MemberMembershipsUnfreezeRequest req,
  ) async {
    try {
      await _apiClient.post(
        '/api/v1/member_memberships/unfreeze',
        data: req.toJson(),
      );
    } on ServerException catch (e) {
      if (e.statusCode == 409) {
        throw MembershipInTaskException(
          e.detail ??
              'This membership is part of an in-progress upgrade task.',
        );
      }
      rethrow;
    }
  }

  /// `POST /api/v1/member_memberships/mark-paid-cash`.
  Future<void> markMembershipPaidCash(
    MemberMembershipsMarkPaidCashRequest req,
  ) async {
    await _apiClient.post(
      '/api/v1/member_memberships/mark-paid-cash',
      data: req.toJson(),
    );
  }

  // ----- Membership plans -----

  /// `GET /api/v1/membership_plans/?gym_id=…`.
  Future<List<MembershipPlanResponse>>
      listMembershipPlans(String gymId) async {
    final response = await _apiClient.get(
      '/api/v1/membership_plans/',
      queryParameters: {'gym_id': gymId},
    );
    return (response.data as List<dynamic>)
        .map(
          (e) => MembershipPlanResponse.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  // ----- Discounts -----

  /// `GET /api/v1/discounts/?gym_id=…`.
  Future<List<DiscountResponse>> listGymDiscounts(
    String gymId,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/discounts/',
      queryParameters: {'gym_id': gymId},
    );
    return (response.data as List<dynamic>)
        .map(
          (e) => DiscountResponse.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  /// `POST /api/v1/member_memberships/discounts/add` — adds the
  /// named preset applied-discount rows. With `req.preview` true it returns the
  /// resulting [DueNowVsRecurringPreview] (nothing committed); else it
  /// commits, re-syncs, and returns null.
  Future<DueNowVsRecurringPreview?> addMembershipDiscounts(
    MemberMembershipsAddDiscountsRequest req,
  ) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/member_memberships/discounts/add',
        data: req.toJson(),
      );
      if (response.data == null) return null;
      return DueNowVsRecurringPreview.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on ServerException catch (e) {
      if (e.statusCode == 409) {
        throw MembershipInTaskException(
          e.detail ??
              'This membership is part of an in-progress upgrade task.',
        );
      }
      rethrow;
    }
  }

  /// `POST /api/v1/member_memberships/discounts/remove` — removes the
  /// named applied-discount rows. With `req.preview` true it returns
  /// the resulting [DueNowVsRecurringPreview] (nothing committed); else it
  /// commits, re-syncs, and returns null.
  Future<DueNowVsRecurringPreview?> removeMembershipDiscounts(
    MemberMembershipsRemoveDiscountsRequest req,
  ) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/member_memberships/discounts/remove',
        data: req.toJson(),
      );
      if (response.data == null) return null;
      return DueNowVsRecurringPreview.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on ServerException catch (e) {
      if (e.statusCode == 409) {
        throw MembershipInTaskException(
          e.detail ??
              'This membership is part of an in-progress upgrade task.',
        );
      }
      rethrow;
    }
  }

  /// `POST /api/v1/member_memberships/discounts/preview` —
  /// previews the subscription for the membership's CURRENT
  /// applied-discount rows (item-id keyed query params,
  /// no body; apply itself writes the applied-discount rows first).
  Future<DueNowVsRecurringPreview?>
      previewMembershipDiscounts({
    required String itemId,
    required String memberId,
  }) async {
    final response = await _apiClient.post(
      '/api/v1/member_memberships/discounts/preview'
      '?item_id=$itemId&member_id=$memberId',
    );
    if (response.data == null) return null;
    return DueNowVsRecurringPreview.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  // ----- Charges / refunds -----

  /// One-time charge against a member's card.
  ///
  /// `POST /api/v1/member_memberships/charge-card` —
  /// creates a one-off Stripe invoice for [amount] minor
  /// units with [reason] as the invoice description /
  /// line-item name. When [paidCash] is true the invoice
  /// is marked paid out of band instead of charging the
  /// saved card. [idempotencyKey] dedupes retries.
  Future<void> chargeCard({
    required String memberId,
    required String paidByMemberId,
    required String gymId,
    required int amount,
    required String reason,
    required String idempotencyKey,
    bool paidCash = false,
  }) async {
    await _apiClient.post(
      '/api/v1/member_memberships/charge-card',
      data: {
        'member_id': memberId,
        'paid_by_member_id': paidByMemberId,
        'gym_id': gymId,
        'amount_cents': amount,
        'reason': reason,
        'paid_cash': paidCash,
        'idempotency_key': idempotencyKey,
      },
    );
  }

  /// Issues a refund for a prior charge — full or partial.
  ///
  /// `POST /api/v1/member_memberships/refund` — refunds the
  /// [chargeId] charge for [amount] minor units (full remaining
  /// balance when [amount] is null). A card charge is reversed
  /// through Stripe; a cash charge is recorded as a cash refund.
  /// [memberId] is the beneficiary whose history the refund was
  /// launched from (auth + gym scope); [idempotencyKey] dedupes a
  /// retried submission's Stripe refund. Mirrors `chargeCard`.
  Future<void> refundCharge({
    required String memberId,
    required String chargeId,
    required String idempotencyKey,
    int? amount,
  }) async {
    await _apiClient.post(
      '/api/v1/member_memberships/refund',
      data: {
        'member_id': memberId,
        'charge_id': chargeId,
        'amount': ?amount,
        'idempotency_key': idempotencyKey,
      },
    );
  }
}
