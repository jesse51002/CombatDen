import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_freeze_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_mark_paid_cash_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_unfreeze_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_update_discounts_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_update_price_request.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/models/members_management_link_check_response.dart';
import 'package:crm/features/member_details/data/models/members_management_link_request.dart';
import 'package:crm/features/member_details/data/models/members_management_response.dart';
import 'package:crm/features/member_details/data/models/members_management_update_card_request.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_response.dart';

/// Repository for member data access.
///
/// Uses [ApiClient] for backend API calls and
/// [SupabaseClient] for direct database queries.
class MemberRepository {
  final ApiClient _apiClient;
  final SupabaseClient _supabase;

  MemberRepository({
    required ApiClient apiClient,
    required SupabaseClient supabase,
  })  : _apiClient = apiClient,
        _supabase = supabase;

  // ----- Member detail + sidebar -----

  Future<MemberDetailResponse> getMemberDetail(
    String crmUserId,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/members/member_details',
      queryParameters: {'crm_user_id': crmUserId},
    );
    return MemberDetailResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<List<MemberSummary>> getAllMembers() async {
    final response = await _supabase
        .from('user_gym_profiles')
        .select(
          'crm_user_id, first_name, last_name, photo_url',
        )
        .order('first_name');

    return (response as List<dynamic>)
        .map(
          (e) => MemberSummary.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  // ----- Members management -----

  Future<MembersManagementResponse> updateMember(
    String crmUserId,
    MembersManagementUpdateRequest req,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/members/$crmUserId',
      data: req.toJson(),
    );
    return MembersManagementResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<MembersManagementResponse> updateMemberCard(
    String crmUserId,
    String paymentMethodId,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/members/$crmUserId/card',
      data: MembersManagementUpdateCardRequest(
        paymentMethodId: paymentMethodId,
      ).toJson(),
    );
    return MembersManagementResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<MembersManagementResponse> unlinkMemberPayment(
    String crmUserId,
  ) async {
    final response = await _apiClient.delete(
      '/api/v1/members/$crmUserId/payment',
    );
    return MembersManagementResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<MembersManagementResponse> linkMemberAccount(
    String crmUserId,
    String parentCrmUserId,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/members/$crmUserId/link',
      data: MembersManagementLinkRequest(
        parentCrmUserId: parentCrmUserId,
      ).toJson(),
    );
    return MembersManagementResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<MembersManagementLinkCheckResponse>
      checkLinkMemberAccount(
    String crmUserId,
    String parentCrmUserId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/members/$crmUserId/link/check',
      data: MembersManagementLinkRequest(
        parentCrmUserId: parentCrmUserId,
      ).toJson(),
    );
    return MembersManagementLinkCheckResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<PaymentsInvoicePreviewResponse?>
      previewLinkMemberAccount(
    String crmUserId,
    String parentCrmUserId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/members/$crmUserId/link/preview',
      data: MembersManagementLinkRequest(
        parentCrmUserId: parentCrmUserId,
      ).toJson(),
    );
    if (response.data == null) return null;
    return PaymentsInvoicePreviewResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<MembersManagementResponse> unlinkMemberAccount(
    String crmUserId,
  ) async {
    final response = await _apiClient.delete(
      '/api/v1/members/$crmUserId/link',
    );
    return MembersManagementResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<PaymentsInvoicePreviewResponse?>
      previewUnlinkMemberAccount(
    String crmUserId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/members/$crmUserId/unlink/preview',
    );
    if (response.data == null) return null;
    return PaymentsInvoicePreviewResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<List<PaymentsInvoiceResponse>>
      listMemberInvoices(
    String crmUserId, {
    int limit = 100,
    String? startingAfter,
  }) async {
    final response = await _apiClient.get(
      '/api/v1/members/$crmUserId/invoices',
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

  // ----- Member memberships -----

  Future<void> startMembership(
    MemberMembershipsStartRequest req,
  ) async {
    await _apiClient.post(
      '/api/v1/member_memberships/',
      data: req.toJson(),
    );
  }

  Future<PaymentsInvoicePreviewResponse?>
      previewStartMembership(
    MemberMembershipsStartRequest req,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/member_memberships/preview',
      data: req.toJson(),
    );
    if (response.data == null) return null;
    return PaymentsInvoicePreviewResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<void> cancelMembership({
    required String itemId,
    required String crmUserId,
    required String idempotencyKey,
  }) async {
    await _apiClient.delete(
      '/api/v1/member_memberships/'
      '?item_id=$itemId'
      '&crm_user_id=$crmUserId'
      '&idempotency_key=$idempotencyKey',
    );
  }

  Future<PaymentsInvoicePreviewResponse?>
      previewCancelMembership(
    String itemId,
    String crmUserId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/member_memberships/cancel/preview'
      '?item_id=$itemId&crm_user_id=$crmUserId',
    );
    if (response.data == null) return null;
    return PaymentsInvoicePreviewResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<void> updateMembershipPrice(
    MemberMembershipsUpdatePriceRequest req,
  ) async {
    await _apiClient.put(
      '/api/v1/member_memberships/price',
      data: req.toJson(),
    );
  }

  Future<PaymentsInvoicePreviewResponse?>
      previewUpdateMembershipPrice(
    MemberMembershipsUpdatePriceRequest req,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/member_memberships/price/preview',
      data: req.toJson(),
    );
    if (response.data == null) return null;
    return PaymentsInvoicePreviewResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<void> freezeAccount(
    MemberMembershipsFreezeRequest req,
  ) async {
    await _apiClient.post(
      '/api/v1/member_memberships/freeze',
      data: req.toJson(),
    );
  }

  Future<void> unfreezeAccount(
    MemberMembershipsUnfreezeRequest req,
  ) async {
    await _apiClient.post(
      '/api/v1/member_memberships/unfreeze',
      data: req.toJson(),
    );
  }

  Future<void> markMembershipPaidCash(
    MemberMembershipsMarkPaidCashRequest req,
  ) async {
    await _apiClient.post(
      '/api/v1/member_memberships/mark-paid-cash',
      data: req.toJson(),
    );
  }

  // ----- Membership plans -----

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

  /// Replaces the full discount set on an existing
  /// membership. `PUT /api/v1/member_memberships/discounts`.
  Future<void> updateMembershipDiscounts(
    MemberMembershipsUpdateDiscountsRequest req,
  ) async {
    await _apiClient.put(
      '/api/v1/member_memberships/discounts',
      data: req.toJson(),
    );
  }

  /// Previews the cost impact of replacing the discount
  /// set on a membership.
  Future<PaymentsInvoicePreviewResponse?>
      previewUpdateMembershipDiscounts(
    MemberMembershipsUpdateDiscountsRequest req,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/member_memberships/discounts/preview',
      data: req.toJson(),
    );
    if (response.data == null) return null;
    return PaymentsInvoicePreviewResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  // ----- Charges / refunds (pending backend) -----

  /// One-time charge against a member's card.
  ///
  /// `POST /api/v1/member_memberships/charge-card` — creates
  /// a one-off Stripe invoice for [amount] minor units with
  /// [reason] as both the invoice description and line-item
  /// name. When [paidCash] is true, the invoice is marked
  /// paid out of band instead of charging the saved card.
  /// [idempotencyKey] is a caller-generated UUID that the
  /// backend uses to deduplicate retried requests.
  Future<void> chargeCard({
    required String crmUserId,
    required String gymId,
    required int amount,
    required String reason,
    required String idempotencyKey,
    bool paidCash = false,
  }) async {
    await _apiClient.post(
      '/api/v1/member_memberships/charge-card',
      data: {
        'crm_user_id': crmUserId,
        'gym_id': gymId,
        'amount_cents': amount,
        'reason': reason,
        'paid_cash': paidCash,
        'idempotency_key': idempotencyKey,
      },
    );
  }

  /// Issues a refund for a prior charge.
  ///
  /// Pending backend — assumed contract:
  /// `POST /api/v1/members/{crm_user_id}/refund`
  /// body `{ charge_id, amount? }`.
  Future<void> refundCharge({
    required String crmUserId,
    required String chargeId,
    int? amount,
  }) async {
    await _apiClient.post(
      '/api/v1/members/$crmUserId/refund',
      data: {
        'charge_id': chargeId,
        'amount': ?amount,
      },
    );
  }
}
