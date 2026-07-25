/// Request body for `POST /api/v1/gyms/`.
class GymCreateRequest {
  final String gymName;

  /// Optional street address typed on the onboarding wizard's name step.
  /// Null when the owner left it blank — `gyms.address` is nullable, so
  /// the gym simply has no address until Settings sets one.
  final String? address;
  final String ownerFirstName;
  final String ownerLastName;

  const GymCreateRequest({
    required this.gymName,
    this.address,
    required this.ownerFirstName,
    required this.ownerLastName,
  });

  Map<String, dynamic> toJson() => {
        'gym_name': gymName,
        // Explicit null, never '' — the backend stores it verbatim.
        'address': address,
        'owner_first_name': ownerFirstName,
        'owner_last_name': ownerLastName,
      };
}
