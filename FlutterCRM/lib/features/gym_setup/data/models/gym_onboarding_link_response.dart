/// Response body from `POST /api/v1/gyms/me/onboarding/link`.
class GymOnboardingLinkResponse {
  final String gymId;
  final String onboardingUrl;
  final DateTime onboardingUrlExpiresAt;

  const GymOnboardingLinkResponse({
    required this.gymId,
    required this.onboardingUrl,
    required this.onboardingUrlExpiresAt,
  });

  factory GymOnboardingLinkResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return GymOnboardingLinkResponse(
      gymId: json['gym_id'] as String,
      onboardingUrl: json['onboarding_url'] as String,
      onboardingUrlExpiresAt: DateTime.parse(
        json['onboarding_url_expires_at'] as String,
      ),
    );
  }
}
