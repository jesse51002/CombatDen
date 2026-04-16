/// Request body for `POST /api/v1/gyms/`.
class GymCreateRequest {
  final String gymName;
  final String ownerFirstName;
  final String ownerLastName;

  const GymCreateRequest({
    required this.gymName,
    required this.ownerFirstName,
    required this.ownerLastName,
  });

  Map<String, dynamic> toJson() => {
        'gym_name': gymName,
        'owner_first_name': ownerFirstName,
        'owner_last_name': ownerLastName,
      };
}
