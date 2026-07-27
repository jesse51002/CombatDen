import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';

Map<String, dynamic> _payload(Map<String, dynamic> extra) => {
      'member_id': 'm1',
      'gym_id': 'g1',
      'gym_name': 'Global MMA',
      'first_name': 'Jane',
      'last_name': 'Doe',
      ...extra,
    };

void main() {
  group('MemberIdentity gym capability flags', () {
    test('reads all three off the identity payload', () {
      final identity = MemberIdentity.fromJson(_payload({
        'gym_rank_enabled': false,
        'gym_has_rewards': true,
        'gym_has_videos': false,
      }));

      expect(identity.gymRankEnabled, isFalse);
      expect(identity.gymHasRewards, isTrue);
      expect(identity.gymHasVideos, isFalse);
    });

    test('an OLDER payload without them defaults to showing everything', () {
      final identity = MemberIdentity.fromJson(_payload(const {}));

      // Hiding a real feature is worse than showing an empty one.
      expect(identity.gymRankEnabled, isTrue);
      expect(identity.gymHasRewards, isTrue);
      expect(identity.gymHasVideos, isTrue);
    });

    test('an explicit null also defaults to true', () {
      final identity = MemberIdentity.fromJson(_payload({
        'gym_rank_enabled': null,
        'gym_has_rewards': null,
        'gym_has_videos': null,
      }));

      expect(identity.gymRankEnabled, isTrue);
      expect(identity.gymHasRewards, isTrue);
      expect(identity.gymHasVideos, isTrue);
    });
  });

  group('SelectedMember carries the flags across a restart', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() => selectedMember.reset());

    test('select records them and restoreFromCache reads them back', () async {
      await selectedMember.select(
        memberId: 'm1',
        gymId: 'g1',
        gymName: 'Global MMA',
        firstName: 'Jane',
        lastName: 'Doe',
        gymRankEnabled: false,
        gymHasRewards: true,
        gymHasVideos: false,
      );

      expect(selectedMember.gymRankEnabled, isFalse);
      expect(selectedMember.gymHasRewards, isTrue);
      expect(selectedMember.gymHasVideos, isFalse);

      // Wipe the in-memory copy, then boot offline off the disk cache.
      await selectedMember.reset();
      SharedPreferences.setMockInitialValues({
        'selected_member_id': 'm1',
        'selected_member_identity':
            '{"member_id":"m1","gym_id":"g1","gym_name":"Global MMA",'
                '"first_name":"Jane","last_name":"Doe",'
                '"gym_rank_enabled":false,"gym_has_rewards":true,'
                '"gym_has_videos":false}',
      });

      expect(await selectedMember.restoreFromCache(), isTrue);
      expect(selectedMember.gymRankEnabled, isFalse);
      expect(selectedMember.gymHasRewards, isTrue);
      expect(selectedMember.gymHasVideos, isFalse);
    });

    test('a cache written by an OLDER build restores as all-true', () async {
      SharedPreferences.setMockInitialValues({
        'selected_member_id': 'm1',
        'selected_member_identity':
            '{"member_id":"m1","gym_id":"g1","gym_name":"Global MMA",'
                '"first_name":"Jane","last_name":"Doe"}',
      });

      expect(await selectedMember.restoreFromCache(), isTrue);
      expect(selectedMember.gymRankEnabled, isTrue);
      expect(selectedMember.gymHasRewards, isTrue);
      expect(selectedMember.gymHasVideos, isTrue);
    });

    test('reset clears back to the show-everything default', () async {
      await selectedMember.select(
        memberId: 'm1',
        gymId: 'g1',
        gymName: 'Global MMA',
        firstName: 'Jane',
        lastName: 'Doe',
        gymRankEnabled: false,
        gymHasRewards: false,
        gymHasVideos: false,
      );
      await selectedMember.reset();

      // A signed-out app must not carry the last gym's shape into the next
      // member's boot.
      expect(selectedMember.gymRankEnabled, isTrue);
      expect(selectedMember.gymHasRewards, isTrue);
      expect(selectedMember.gymHasVideos, isTrue);
    });
  });
}
