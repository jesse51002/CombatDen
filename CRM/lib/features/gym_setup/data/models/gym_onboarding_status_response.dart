import 'package:crm/features/gym_setup/data/models/gym_onboarding_status.dart';

/// Response body from `GET /api/v1/gyms/me/onboarding`.
///
/// `onboardingUrl` and `onboardingUrlExpiresAt` are
/// non-null only when `stripeOnboardingStatus` is
/// `pending`. `disabledReason` is non-null only when
/// status is `disabled`.
class GymOnboardingStatusResponse {
  final String gymId;
  final GymOnboardingStatus stripeOnboardingStatus;
  final String? onboardingUrl;
  final DateTime? onboardingUrlExpiresAt;
  final bool detailsSubmitted;
  final bool chargesEnabled;
  final bool payoutsEnabled;
  final String? disabledReason;
  final List<String> requirementsCurrentlyDue;

  const GymOnboardingStatusResponse({
    required this.gymId,
    required this.stripeOnboardingStatus,
    required this.onboardingUrl,
    required this.onboardingUrlExpiresAt,
    required this.detailsSubmitted,
    required this.chargesEnabled,
    required this.payoutsEnabled,
    required this.disabledReason,
    required this.requirementsCurrentlyDue,
  });

  factory GymOnboardingStatusResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final expiresAtRaw =
        json['onboarding_url_expires_at'] as String?;
    final requirementsRaw =
        json['requirements_currently_due'] as List<dynamic>?;
    return GymOnboardingStatusResponse(
      gymId: json['gym_id'] as String,
      stripeOnboardingStatus: GymOnboardingStatus.fromJson(
        json['stripe_onboarding_status'] as String,
      ),
      onboardingUrl: json['onboarding_url'] as String?,
      onboardingUrlExpiresAt: expiresAtRaw == null
          ? null
          : DateTime.parse(expiresAtRaw),
      detailsSubmitted:
          (json['details_submitted'] as bool?) ?? false,
      chargesEnabled:
          (json['charges_enabled'] as bool?) ?? false,
      payoutsEnabled:
          (json['payouts_enabled'] as bool?) ?? false,
      disabledReason: json['disabled_reason'] as String?,
      requirementsCurrentlyDue: requirementsRaw == null
          ? const <String>[]
          : requirementsRaw
              .map((e) => e as String)
              .toList(growable: false),
    );
  }
}
