import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_price_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/memberships/data/models/discount_create_request.dart';
import 'package:crm/features/memberships/data/models/discount_update_request.dart';
import 'package:crm/features/memberships/data/models/member_waiver_status.dart';
import 'package:crm/features/memberships/data/models/membership_plan_create_request.dart';
import 'package:crm/features/memberships/data/models/member_memberships_reprice_all_request.dart';
import 'package:crm/features/memberships/data/models/member_memberships_reprice_all_response.dart';
import 'package:crm/features/memberships/data/models/membership_plan_price_request.dart';
import 'package:crm/features/memberships/data/models/membership_plan_price_with_count.dart';
import 'package:crm/features/memberships/data/models/membership_plan_update_request.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/memberships/data/models/waiver_create_request.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/models/waiver_sign_request.dart';
import 'package:crm/features/memberships/data/models/waiver_signature_response.dart';
import 'package:crm/features/memberships/data/models/waiver_signatory_row.dart';
import 'package:crm/features/memberships/data/models/waiver_update_request.dart';
import 'package:crm/features/memberships/data/models/waiver_version_response.dart';

/// Repository for the Memberships screen — gym-level catalog
/// CRUD over membership plans, discount presets, and waivers
/// (plus read-only waiver signature tracking).
///
/// Every call goes through the FastAPI backend via [ApiClient];
/// paths and shapes match `Database/openapi.json`.
class MembershipsRepository {
  final ApiClient _apiClient;

  MembershipsRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  // ----- Membership plans -----

  /// `GET /api/v1/membership_plans/?gym_id=…` (with enrolled counts).
  Future<List<MembershipPlanResponse>> listPlans(String gymId) async {
    final response = await _apiClient.get(
      '/api/v1/membership_plans/',
      queryParameters: {'gym_id': gymId},
    );
    return (response.data as List<dynamic>)
        .map((e) =>
            MembershipPlanResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `POST /api/v1/membership_plans/`.
  Future<MembershipPlanResponse> createPlan(
    MembershipPlanCreateRequest req,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/membership_plans/',
      data: req.toJson(),
    );
    return MembershipPlanResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `PUT /api/v1/membership_plans/`.
  Future<MembershipPlanResponse> updatePlan(
    MembershipPlanUpdateRequest req,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/membership_plans/',
      data: req.toJson(),
    );
    return MembershipPlanResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `DELETE /api/v1/membership_plans/?plan_id=&gym_id=`.
  Future<void> deletePlan(String planId, String gymId) async {
    await _apiClient.delete(
      '/api/v1/membership_plans/?plan_id=$planId&gym_id=$gymId',
    );
  }

  /// `POST /api/v1/membership_plans/price`.
  Future<MembershipPlanPriceResponse> setPlanPrice(
    MembershipPlanPriceRequest req,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/membership_plans/price',
      data: req.toJson(),
    );
    return MembershipPlanPriceResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `GET /api/v1/membership_plans/{plan_id}/prices?gym_id=…` — every
  /// price version of a plan (active first) with its member count.
  Future<List<MembershipPlanPriceWithCount>> listPlanPrices(
    String planId,
    String gymId,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/membership_plans/$planId/prices',
      queryParameters: {'gym_id': gymId},
    );
    return (response.data as List<dynamic>)
        .map((e) =>
            MembershipPlanPriceWithCount.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `POST /api/v1/member_memberships/reprice-plan` — queues a background
  /// task that upgrades every member on this plan to its current active price.
  /// Returns the task id (nullable — null when nothing needs upgrading) and
  /// the membership count. HTTP 202.
  Future<MemberMembershipsRepriceAllResponse> repriceAllOnPlan(
    String planId,
    String gymId, {
    ProrationBehavior prorationBehavior = ProrationBehavior.noCharge,
  }) async {
    final response = await _apiClient.post(
      '/api/v1/member_memberships/reprice-plan',
      data: MemberMembershipsRepriceAllRequest(
        planId: planId,
        gymId: gymId,
        prorationBehavior: prorationBehavior,
      ).toJson(),
    );
    return MemberMembershipsRepriceAllResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  // ----- Discounts -----

  /// `GET /api/v1/discounts/?gym_id=…`.
  Future<List<DiscountResponse>> listDiscounts(String gymId) async {
    final response = await _apiClient.get(
      '/api/v1/discounts/',
      queryParameters: {'gym_id': gymId},
    );
    return (response.data as List<dynamic>)
        .map((e) => DiscountResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `POST /api/v1/discounts/`.
  Future<DiscountResponse> createDiscount(
    DiscountCreateRequest req,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/discounts/',
      data: req.toJson(),
    );
    return DiscountResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `PUT /api/v1/discounts/`.
  Future<DiscountResponse> updateDiscount(
    DiscountUpdateRequest req,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/discounts/',
      data: req.toJson(),
    );
    return DiscountResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `DELETE /api/v1/discounts/?discount_id=&gym_id=`.
  Future<void> deleteDiscount(String discountId, String gymId) async {
    await _apiClient.delete(
      '/api/v1/discounts/?discount_id=$discountId&gym_id=$gymId',
    );
  }

  // ----- Waivers -----

  /// `GET /api/v1/waivers/?gym_id=…`.
  Future<List<WaiverResponse>> listWaivers(String gymId) async {
    final response = await _apiClient.get(
      '/api/v1/waivers/',
      queryParameters: {'gym_id': gymId},
    );
    return (response.data as List<dynamic>)
        .map((e) => WaiverResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `GET /api/v1/waivers/{waiver_id}?gym_id=…` (with current body).
  Future<WaiverResponse> getWaiver(String waiverId, String gymId) async {
    final response = await _apiClient.get(
      '/api/v1/waivers/$waiverId',
      queryParameters: {'gym_id': gymId},
    );
    return WaiverResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `POST /api/v1/waivers/`.
  Future<WaiverResponse> createWaiver(WaiverCreateRequest req) async {
    final response = await _apiClient.post(
      '/api/v1/waivers/',
      data: req.toJson(),
    );
    return WaiverResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `PUT /api/v1/waivers/`.
  Future<WaiverResponse> updateWaiver(WaiverUpdateRequest req) async {
    final response = await _apiClient.put(
      '/api/v1/waivers/',
      data: req.toJson(),
    );
    return WaiverResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `DELETE /api/v1/waivers/?waiver_id=&gym_id=`.
  Future<void> deleteWaiver(String waiverId, String gymId) async {
    await _apiClient.delete(
      '/api/v1/waivers/?waiver_id=$waiverId&gym_id=$gymId',
    );
  }

  /// `GET /api/v1/waivers/{waiver_id}/versions?gym_id=…`.
  Future<List<WaiverVersionResponse>> listWaiverVersions(
    String waiverId,
    String gymId,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/waivers/$waiverId/versions',
      queryParameters: {'gym_id': gymId},
    );
    return (response.data as List<dynamic>)
        .map((e) =>
            WaiverVersionResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `GET /api/v1/waivers/{waiver_id}/signatures?gym_id=…`.
  Future<List<WaiverSignatoryRow>> listWaiverSignatories(
    String waiverId,
    String gymId,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/waivers/$waiverId/signatures',
      queryParameters: {'gym_id': gymId},
    );
    return (response.data as List<dynamic>)
        .map((e) => WaiverSignatoryRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `GET /api/v1/waivers/signatures/by-member/{member_id}?gym_id=…`.
  Future<List<MemberWaiverStatus>> listMemberWaiverStatus(
    String memberId,
    String gymId,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/waivers/signatures/by-member/$memberId',
      queryParameters: {'gym_id': gymId},
    );
    return (response.data as List<dynamic>)
        .map((e) => MemberWaiverStatus.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `POST /api/v1/waivers/{waiver_id}/signatures` — record one member's
  /// e-signature on the current version of a waiver.
  ///
  /// Throws [WaiverStaleVersionException] on 409 (the gym published a newer
  /// version since the UI loaded the body — caller must prompt re-open).
  Future<WaiverSignatureResponse> recordWaiverSignature({
    required String waiverId,
    required String gymId,
    required String memberId,
    required String waiverVersionId,
    required String signerName,
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/waivers/$waiverId/signatures',
        data: WaiverSignRequest(
          gymId: gymId,
          memberId: memberId,
          waiverVersionId: waiverVersionId,
          signerName: signerName,
        ).toJson(),
      );
      return WaiverSignatureResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on ServerException catch (e) {
      if (e.statusCode == 409) throw const WaiverStaleVersionException();
      rethrow;
    }
  }
}
