import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/gym_setup/data/models/gym_create_request.dart';

void main() {
  group('GymCreateRequest.toJson', () {
    test('sends the optional address when the owner typed one', () {
      const request = GymCreateRequest(
        gymName: 'Aztec MMA',
        address: '1200 W 6th St, Austin, TX 78703',
        ownerFirstName: 'Jesse',
        ownerLastName: 'Musa',
      );

      expect(request.toJson(), {
        'gym_name': 'Aztec MMA',
        'address': '1200 W 6th St, Austin, TX 78703',
        'owner_first_name': 'Jesse',
        'owner_last_name': 'Musa',
      });
    });

    test('sends null — never an empty string — when it was skipped', () {
      const request = GymCreateRequest(
        gymName: 'Aztec MMA',
        ownerFirstName: 'Jesse',
        ownerLastName: 'Musa',
      );

      expect(request.toJson()['address'], isNull);
    });
  });
}
