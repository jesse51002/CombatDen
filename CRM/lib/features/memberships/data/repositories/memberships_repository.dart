import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_price_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/memberships/data/models/discount_create_request.dart';
import 'package:crm/features/memberships/data/models/discount_update_request.dart';
import 'package:crm/features/memberships/data/models/member_waiver_status.dart';
import 'package:crm/features/memberships/data/models/membership_plan_create_request.dart';
import 'package:crm/features/memberships/data/models/membership_plan_migrate_all_request.dart';
import 'package:crm/features/memberships/data/models/membership_plan_price_request.dart';
import 'package:crm/features/memberships/data/models/membership_plan_price_with_count.dart';
import 'package:crm/features/memberships/data/models/membership_plan_update_request.dart';
import 'package:crm/features/memberships/data/models/waiver_create_request.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
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

  /// `POST /api/v1/membership_plans/migrate-all` — queues a background
  /// sync moving every member on an older price onto the current price.
  Future<void> migrateAllToCurrentPrice(
    String planId,
    String gymId,
  ) async {
    await _apiClient.post(
      '/api/v1/membership_plans/migrate-all',
      data: MembershipPlanMigrateAllRequest(
        planId: planId,
        gymId: gymId,
      ).toJson(),
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
}
