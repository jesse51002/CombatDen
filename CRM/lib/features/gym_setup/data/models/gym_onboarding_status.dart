/// Canonical Stripe onboarding status for a gym.
///
/// Mirrors the backend enum. `unknown` is a safe
/// fallback for forward-compatibility when the
/// backend introduces a new value.
enum GymOnboardingStatus {
  pending('pending'),
  complete('complete'),
  disabled('disabled'),
  unknown('unknown');

  final String value;
  const GymOnboardingStatus(this.value);

  static GymOnboardingStatus fromJson(String value) {
    return GymOnboardingStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => GymOnboardingStatus.unknown,
    );
  }
}
