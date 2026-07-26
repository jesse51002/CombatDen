import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/members_management_create_request.dart';

/// `send_invite` is REQUIRED by the backend with no default — a body that
/// omits it is a 422 on every member create, including the kiosk's self-serve
/// signup. It must also survive the duplicate round-trip: `copyWith` is how a
/// blocked create is re-sent with `allow_duplicate: true`, and dropping the
/// invite answer there would silently stop inviting exactly the people who
/// hit the duplicate gate.
void main() {
  MembersManagementCreateRequest request({required bool sendInvite}) =>
      MembersManagementCreateRequest(
        gymId: 'gym-1',
        firstName: 'Jo',
        lastName: 'Doe',
        email: 'jo@example.com',
        sendInvite: sendInvite,
      );

  test('the wire body always carries send_invite', () {
    expect(request(sendInvite: true).toJson()['send_invite'], isTrue);
    expect(request(sendInvite: false).toJson()['send_invite'], isFalse);
  });

  test('copyWith to confirm a duplicate keeps the invite answer', () {
    final confirmed =
        request(sendInvite: true).copyWith(allowDuplicate: true).toJson();
    expect(confirmed['allow_duplicate'], isTrue);
    expect(confirmed['send_invite'], isTrue);

    final quiet =
        request(sendInvite: false).copyWith(allowDuplicate: true).toJson();
    expect(quiet['allow_duplicate'], isTrue);
    expect(quiet['send_invite'], isFalse);
  });

  test('optional fields stay omitted rather than sent as null', () {
    final body = request(sendInvite: true).toJson();
    expect(body.containsKey('phone'), isFalse);
    expect(body.containsKey('payment_method_id'), isFalse);
    expect(body['gym_id'], 'gym-1');
  });
}
