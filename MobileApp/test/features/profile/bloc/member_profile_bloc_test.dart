import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_event.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/profile/data/models/billing_personal_info.dart';
import 'package:mobile_app/features/profile/data/models/billing_retention.dart';
import 'package:mobile_app/features/profile/data/models/member_profile.dart';
import 'package:mobile_app/features/profile/data/repositories/member_profile_repository.dart';

class _MockProfileRepo extends Mock implements MemberProfileRepository {}

MemberProfile _profile({int points = 1250, int streak = 3}) => MemberProfile(
      memberId: 'm1',
      gymId: 'g1',
      firstName: 'Jane',
      lastName: 'Doe',
      personalInfo: const BillingPersonalInfo(),
      retention: BillingRetention(
        classStreakWeeks: streak,
        pointsBalance: points,
        videosWatched: 0,
      ),
    );

void main() {
  late _MockProfileRepo repo;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await selectedMember.select(
      memberId: 'm1',
      gymId: 'g1',
      gymName: 'Global MMA',
      firstName: 'Jane',
      lastName: 'Doe',
    );
    repo = _MockProfileRepo();
  });

  void stubProfile(MemberProfile profile) {
    when(() => repo.getProfile(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
        )).thenAnswer((_) async => profile);
  }

  MemberProfileBloc build() => MemberProfileBloc(repository: repo);

  blocTest<MemberProfileBloc, MemberProfileState>(
    'load fetches the selected member profile',
    setUp: () => stubProfile(_profile()),
    build: build,
    act: (b) => b.add(const MemberProfileLoadRequested()),
    expect: () => [
      isA<MemberProfileState>()
          .having((s) => s.status, 'status', MemberProfileStatus.loading),
      isA<MemberProfileState>()
          .having((s) => s.status, 'status', MemberProfileStatus.loaded)
          .having(
            (s) => s.profile?.retention.pointsBalance,
            'points',
            1250,
          ),
    ],
  );

  blocTest<MemberProfileBloc, MemberProfileState>(
    'refresh re-fetches WITHOUT a loading flip and updates the profile',
    setUp: () => stubProfile(_profile(points: 1400, streak: 4)),
    build: build,
    seed: () => MemberProfileState(
      status: MemberProfileStatus.loaded,
      profile: _profile(points: 1250, streak: 3),
    ),
    act: (b) => b.add(const MemberProfileRefreshRequested()),
    expect: () => [
      isA<MemberProfileState>()
          .having((s) => s.status, 'status', MemberProfileStatus.loaded)
          .having((s) => s.profile?.retention.pointsBalance, 'points', 1400)
          .having(
            (s) => s.profile?.retention.classStreakWeeks,
            'streak',
            4,
          ),
    ],
  );
}
