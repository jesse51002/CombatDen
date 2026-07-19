import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/check_in/data/models/check_in_request.dart';
import 'package:crm/features/check_in/data/models/check_in_response.dart';
import 'package:crm/features/member_details/data/models/authorized_payer_waiver.dart';
import 'package:crm/features/member_details/data/models/cancel_outcome.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
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
import 'package:crm/features/member_details/data/models/member_memberships_upgrade_request.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/data/models/members_management_link_check_response.dart';
import 'package:crm/features/member_details/data/models/members_management_link_request.dart';
import 'package:crm/features/member_details/data/models/members_management_response.dart';
import 'package:crm/features/member_details/data/models/members_management_update_card_request.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payer_invoice_change.dart';
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
          view: MembersListView.all,
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

  /// `POST /api/v1/members/` — create a member shell (and its Stripe
  /// customer). Returns the new member's id (from the 201
  /// `MembersBillingProfileResponse`).
  ///
  /// Throws [DuplicateMemberException] on a 409 whose
  /// `detail.code == "duplicate_member"` — a same-identity member already
  /// exists and [MembersManagementCreateRequest.allowDuplicate] is false;
  /// nothing was written, so the caller offers create-anyway / use-existing.
  /// A 400 (the gym has no Stripe Connect account) rethrows as a
  /// [ServerException] the caller surfaces.
  Future<String> createMember(
    MembersManagementCreateRequest req,
  ) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/members/',
        data: req.toJson(),
      );
      final data = response.data as Map<String, dynamic>;
      return data['member_id'] as String;
    } on ServerException catch (e) {
      if (e.statusCode == 409) {
        final dup = _parseDuplicateMember(e.data);
        if (dup != null) throw dup;
      }
      rethrow;
    }
  }

  /// Parses `{"detail": {"code": "duplicate_member", "matches": [...]}}` from
  /// a 409 body into a [DuplicateMemberException]. Returns null when the shape
  /// doesn't match (a plain 409 should still propagate as a
  /// [ServerException]). Mirrors [_parseWaiverGate].
  DuplicateMemberException? _parseDuplicateMember(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final detail = data['detail'];
    if (detail is! Map) return null;
    if (detail['code'] != 'duplicate_member') return null;
    final matchesRaw = detail['matches'];
    if (matchesRaw is! List) return null;
    final matches = matchesRaw
        .whereType<Map<String, dynamic>>()
        .map(DuplicateMemberMatch.fromJson)
        .toList();
    return DuplicateMemberException(matches);
  }

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

  /// `GET /api/v1/members/{member_id}/authorized-payer-waiver` — the gym's
  /// default authorized-payer waiver (id + version + body) the payer must sign
  /// to be authorized for this member. The sign dialog renders [body] before
  /// linking.
  Future<AuthorizedPayerWaiver> getAuthorizedPayerWaiver(
    String memberId,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/members/$memberId/authorized-payer-waiver',
    );
    return AuthorizedPayerWaiver.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `PUT /api/v1/members/{member_id}/link` — authorize [payerMemberId] to pay
  /// for the member. The payer signs the gym's default authorized-payer waiver
  /// in the same call; [waiverVersionId] is the version id the UI displayed
  /// (echoed back so the backend can version-lock — 409 if stale), [signerName]
  /// is the typed signature, and [consentAcknowledged] must be true. The
  /// signature + authorization are recorded atomically. A pure DB change;
  /// the endpoint returns no body, so callers refetch member detail afterward.
  Future<void> linkMemberAccount(
    String memberId, {
    required String payerMemberId,
    required String waiverVersionId,
    required String signerName,
    required bool consentAcknowledged,
  }) async {
    await _apiClient.put(
      '/api/v1/members/$memberId/link',
      data: MembersManagementLinkRequest(
        payerMemberId: payerMemberId,
        waiverVersionId: waiverVersionId,
        signerName: signerName,
        consentAcknowledged: consentAcknowledged,
      ).toJson(),
    );
  }

  /// `POST /api/v1/members/{member_id}/link/check` — read-only eligibility for
  /// authorizing [payerMemberId] (no signature). Returns can_link + an error
  /// string when blocked.
  Future<MembersManagementLinkCheckResponse>
      checkLinkMemberAccount(
    String memberId,
    String payerMemberId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/members/$memberId/link/check',
      data: {'payer_member_id': payerMemberId},
    );
    return MembersManagementLinkCheckResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `POST /api/v1/members/{member_id}/link/remove/preview` — cost preview of
  /// removing [payerMemberId] as a payer for [memberId]: the payer's recurring
  /// bill after cancelling the memberships they fund (current → new),
  /// pair-scoped so a one-entry list (empty = no billing change). Read-only;
  /// shown before confirming.
  Future<List<PayerInvoiceChange>> previewRemoveAuthorization(
    String memberId,
    String payerMemberId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/members/$memberId/link/remove/preview',
      data: {'payer_member_id': payerMemberId},
    );
    return (response.data as List<dynamic>)
        .map(
          (e) =>
              PayerInvoiceChange.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  /// `POST /api/v1/members/{member_id}/link/remove` — cancels [memberId]'s live
  /// recurring memberships that [payerMemberId] funds, then de-authorizes the
  /// pair (the signature audit row is kept). [idempotencyKey] is generated once
  /// per user action and reused on retry, so the cascading cancel dedups at
  /// Stripe (the backend derives the payer's sub-key from it).
  ///
  /// Returns a [CancelOutcome] describing which funded memberships were
  /// cancelled (mirrors [cancelMemberships], so the unlink flow can show the
  /// same completion screen):
  /// - HTTP 200: the cancelled item_ids come from the `cancel_dates` keys (the
  ///   map is empty when the relationship funded nothing — a clean de-authorize).
  /// - HTTP 207 partial: the body's `{succeeded_item_ids, failed_item_ids}`
  ///   carries the real split (a 2xx, so it arrives on the success path).
  /// Any other error (total failure 500, transport failure) rethrows — the
  /// caller surfaces it rather than showing an empty completion screen.
  Future<CancelOutcome> removeAuthorization(
    String memberId,
    String payerMemberId,
    String idempotencyKey,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/members/$memberId/link/remove',
      data: {
        'payer_member_id': payerMemberId,
        'idempotency_key': idempotencyKey,
      },
    );
    // HTTP 207 partial: the body carries the succeeded/failed split (a 2xx, so
    // it arrives here on the success path, not as an exception).
    if (response.statusCode == 207) {
      final partial = _parsePartialCancel(
        response.data is Map
            ? (response.data as Map).cast<String, dynamic>()
            : null,
      );
      if (partial != null) return partial;
    }
    // HTTP 200: cancelled item_ids = cancel_dates keys (empty = nothing
    // funded, just a de-authorize).
    final data = response.data;
    final cancelDates = data is Map
        ? data['cancel_dates'] as Map<String, dynamic>?
        : null;
    return CancelOutcome(
      succeededItemIds: cancelDates?.keys.toList() ?? const [],
      failedItemIds: const [],
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
  /// per-membership created/failed breakdown (status is 201 when all
  /// created, 207 when some failed — both 2xx; inspect each result
  /// either way). A total failure (nothing created) throws.
  ///
  /// Throws [WaiverGateException] on 422 when required waiver signatures are
  /// missing — the wizard routes to its sign-waivers step in that case.
  Future<MemberMembershipsStartResponse> startMemberships(
    MemberMembershipsStartRequest req,
  ) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/member_memberships/',
        data: req.toJson(),
      );
      return MemberMembershipsStartResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on ServerException catch (e) {
      if (e.statusCode == 422) {
        final gate = _parseWaiverGate(e.data);
        if (gate != null) throw gate;
      }
      rethrow;
    }
  }

  /// `POST /api/v1/member_memberships/preview` — stage the
  /// same start request (discounts included) and return the
  /// three-way one-time / due-now / recurring split without
  /// committing anything.
  ///
  /// Throws [WaiverGateException] on 422 (same gate as the real start).
  Future<MemberMembershipsStartPreview>
      previewStartMemberships(
    MemberMembershipsStartRequest req,
  ) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/member_memberships/preview',
        data: req.toJson(),
      );
      return MemberMembershipsStartPreview.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on ServerException catch (e) {
      if (e.statusCode == 422) {
        final gate = _parseWaiverGate(e.data);
        if (gate != null) throw gate;
      }
      rethrow;
    }
  }

  /// Parses `{"detail": {"message": "...", "unsigned": [...]}}` from a 422
  /// body. Returns null when the shape doesn't match (a normal 422 validation
  /// error should still propagate as a [ServerException]).
  WaiverGateException? _parseWaiverGate(Map<String, dynamic>? data) {
    if (data == null) return null;
    final detail = data['detail'];
    if (detail is! Map) return null;
    final message = detail['message'];
    final unsignedRaw = detail['unsigned'];
    if (message is! String || unsignedRaw is! List) return null;
    final unsigned = unsignedRaw
        .whereType<Map<String, dynamic>>()
        .map(WaiverGateItem.fromJson)
        .toList();
    return WaiverGateException(message: message, unsigned: unsigned);
  }

  /// `DELETE /api/v1/member_memberships/` — cancel ONE OR MORE
  /// membership items in one call (a single cancel is a one-element
  /// list). The merged contract takes `item_ids`, `member_id`, and
  /// `idempotency_key` in the request body; the backend groups the
  /// items by payer and converges each payer's subscription once.
  ///
  /// Returns a [CancelOutcome] describing which item_ids succeeded
  /// and which failed:
  /// - HTTP 200: all [itemIds] succeeded (from `cancel_dates` keys).
  /// - HTTP 207 partial: the body's `{succeeded_item_ids, failed_item_ids}`
  ///   carries the real split — a 207 is a 2xx, so it arrives on the
  ///   SUCCESS path (no exception); parse it so the completion screen shows
  ///   which items actually cancelled. If the structured shape is missing,
  ///   fall back to all-failed.
  /// - HTTP 409: throws [MembershipInTaskException] (not a cancel
  ///   outcome — the request was blocked entirely).
  /// - Total failure (HTTP 500) / other error: all [itemIds] reported as failed.
  Future<CancelOutcome> cancelMemberships({
    required List<String> itemIds,
    required String memberId,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _apiClient.delete(
        '/api/v1/member_memberships/',
        data: {
          'item_ids': itemIds,
          'member_id': memberId,
          'idempotency_key': idempotencyKey,
        },
      );
      // HTTP 207: partial — the body carries the real succeeded/failed split.
      if (response.statusCode == 207) {
        final partial = _parsePartialCancel(
          response.data is Map
              ? (response.data as Map).cast<String, dynamic>()
              : null,
        );
        if (partial != null) return partial;
      }
      // HTTP 200: parse succeeded item_ids from cancel_dates keys.
      final data = response.data;
      if (data is Map) {
        final cancelDates =
            data['cancel_dates'] as Map<String, dynamic>?;
        final succeeded = cancelDates?.keys.toList() ?? itemIds;
        return CancelOutcome(
          succeededItemIds: succeeded,
          failedItemIds: const [],
        );
      }
      // Unexpected shape — treat all as succeeded (a 2xx was returned).
      return CancelOutcome(
        succeededItemIds: itemIds,
        failedItemIds: const [],
      );
    } on ServerException catch (e) {
      if (e.statusCode == 409) {
        throw MembershipInTaskException(
          e.detail ??
              'This membership is part of an in-progress upgrade task.',
        );
      }
      // Total failure (500) / unstructured server error: all items failed.
      return CancelOutcome(
        succeededItemIds: const [],
        failedItemIds: itemIds,
      );
    } catch (_) {
      return CancelOutcome(
        succeededItemIds: const [],
        failedItemIds: itemIds,
      );
    }
  }

  /// Reads the structured partial-cancel split from a 207 Multi-Status body
  /// (`{"message": ..., "succeeded_item_ids": [...], "failed_item_ids":
  /// [...]}`). The fields are top-level (a 207 is a returned RESULT, not an
  /// HTTPException, so there is no `detail` wrapper). Returns null when the
  /// body has no structured split, so the caller falls back appropriately.
  CancelOutcome? _parsePartialCancel(Map<String, dynamic>? data) {
    if (data == null) return null;
    final succeeded = data['succeeded_item_ids'];
    final failed = data['failed_item_ids'];
    if (succeeded is! List || failed is! List) return null;
    return CancelOutcome(
      succeededItemIds: succeeded.map((e) => e.toString()).toList(),
      failedItemIds: failed.map((e) => e.toString()).toList(),
    );
  }

  /// `POST /api/v1/member_memberships/cancel/preview` — per-payer cost preview
  /// of cancelling [itemIds] (a single cancel is one payer → a one-entry list;
  /// a member's memberships split across payers yield several entries). Sends
  /// `item_ids` + `member_id` in the request body.
  Future<List<PayerInvoiceChange>> previewCancelMemberships(
    List<String> itemIds,
    String memberId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/member_memberships/cancel/preview',
      data: {
        'item_ids': itemIds,
        'member_id': memberId,
      },
    );
    if (response.data == null) return [];
    return (response.data as List<dynamic>)
        .map(
          (e) =>
              PayerInvoiceChange.fromJson(e as Map<String, dynamic>),
        )
        .toList();
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

  /// `POST /api/v1/member_memberships/upgrade` — cross-plan upgrade.
  ///
  /// Moves the membership to the target plan's active price and charges
  /// the prorated difference now. A membership in an in-progress task is
  /// rejected (409 → [MembershipInTaskException], like reprice).
  Future<void> upgradeMembership(
    MemberMembershipsUpgradeRequest req,
  ) async {
    try {
      await _apiClient.post(
        '/api/v1/member_memberships/upgrade',
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

  /// `POST /api/v1/member_memberships/upgrade/preview`.
  Future<DueNowVsRecurringPreview?> upgradePreview(
    MemberMembershipsUpgradeRequest req,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/member_memberships/upgrade/preview',
      data: req.toJson(),
    );
    if (response.data == null) return null;
    return DueNowVsRecurringPreview.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `POST /api/v1/member_memberships/end` — MANUALLY cancel a ONE-TIME /
  /// TRIAL membership early. A human terminating it early sets `cancel_date`
  /// to today → status 'cancelled' (vs an AUTOMATIC duration/depletion end →
  /// 'ended'). Endpoint path + method name kept; the CRM surfaces it as
  /// "Cancel membership". No Stripe action, no money movement (refund is the
  /// separate flow).
  Future<void> cancelOneTimeMembership({
    required String itemId,
    required String memberId,
  }) async {
    await _apiClient.post(
      '/api/v1/member_memberships/cancel-one-time',
      data: {
        'item_id': itemId,
        'member_id': memberId,
      },
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

  // ----- Class check-in -----

  /// `POST /api/v1/checkin` — staff single check-in for [req]'s member into the
  /// occurrence addressed by `class_id` + `occurrence_date` (the occurrence's
  /// IDENTITY date, never its effective/display date). The CRM always
  /// sends `is_member: false`: a clean check-in is recorded — the
  /// [CheckInResponse] is a fresh attendance (points awarded) or an idempotent
  /// repeat (`already_checked_in`), with any gate conditions as non-blocking
  /// `warnings` — but one that hits a warning is NOT recorded
  /// (`requires_confirmation` true, `log_id` null) unless [req] carries
  /// `ignore_warnings: true`.
  Future<CheckInResponse> checkInMember(CheckInRequest req) async {
    final response = await _apiClient.post(
      '/api/v1/checkin',
      data: req.toJson(),
    );
    return CheckInResponse.fromJson(
      response.data as Map<String, dynamic>,
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
  /// saved card. When [paymentMethodId] is set, that one-off
  /// card is billed (attached, charged once, detached)
  /// instead of the payer's saved default. [idempotencyKey]
  /// dedupes retries.
  Future<void> chargeCard({
    required String memberId,
    required String paidByMemberId,
    required String gymId,
    required int amount,
    required String reason,
    required String idempotencyKey,
    bool paidCash = false,
    String? paymentMethodId,
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
        'payment_method_id': ?paymentMethodId,
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

  // ----- Rewards / redemptions -----

  /// `POST /api/v1/rewards/{reward_id}/redeem-for-member` —
  /// staff redeems a reward on behalf of a member.
  ///
  /// When [allowOverride] is false (default), the backend returns a 400
  /// if the member's balance is insufficient — surface that via
  /// [actionError]. When [allowOverride] is true, the balance drains to
  /// zero (a "comp" redemption).
  Future<void> redeemRewardForMember({
    required String rewardId,
    required String memberId,
    bool allowOverride = false,
  }) async {
    await _apiClient.post(
      '/api/v1/rewards/$rewardId/redeem-for-member',
      data: {
        'member_id': memberId,
        'override': allowOverride,
      },
    );
  }

  /// `POST /api/v1/members/{member_id}/points` — manually award
  /// or deduct points. [amount] is signed (positive = award,
  /// negative = deduct). A 400 is returned when deducting would
  /// take the balance below zero.
  Future<void> adjustPoints({
    required String memberId,
    required int amount,
  }) async {
    await _apiClient.post(
      '/api/v1/members/$memberId/points',
      data: {'amount': amount},
    );
  }
}
