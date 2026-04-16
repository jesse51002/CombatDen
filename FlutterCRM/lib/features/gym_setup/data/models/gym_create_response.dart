import 'package:crm/features/gym_setup/data/models/gym_onboarding_status.dart';

/// Response body from `POST /api/v1/gyms/` on 201.
class GymCreateResponse {
  final String gymId;
  final String stripeAccountId;
  final GymOnboardingStatus stripeOnboardingStatus;
  final String onboardingUrl;
  final DateTime onboardingUrlExpiresAt;

  const GymCreateResponse({
    required this.gymId,
    required this.stripeAccountId,
    required this.stripeOnboardingStatus,
    required this.onboardingUrl,
    required this.onboardingUrlExpiresAt,
  });

  factory GymCreateResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return GymCreateResponse(
      gymId: json['gym_id'] as String,
      stripeAccountId: json['stripe_account_id'] as String,
      stripeOnboardingStatus: GymOnboardingStatus.fromJson(
        json['stripe_onboarding_status'] as String,
      ),
      onboardingUrl: json['onboarding_url'] as String,
      onboardingUrlExpiresAt: DateTime.parse(
        json['onboarding_url_expires_at'] as String,
      ),
    );
  }
}
