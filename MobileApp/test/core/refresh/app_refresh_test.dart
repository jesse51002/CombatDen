import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/refresh/app_refresh.dart';
import 'package:mobile_app/core/refresh/refresh_signal.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/gym/theme_hydration.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';
import 'package:mobile_app/features/member_select/data/repositories/member_portal_repository.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_event.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/profile/data/models/billing_personal_info.dart';
import 'package:mobile_app/features/profile/data/models/billing_retention.dart';
import 'package:mobile_app/features/profile/data/models/member_profile.dart';
import 'package:mobile_app/features/profile/data/repositories/member_profile_repository.dart';

/// The identity read. [members] is what the server currently answers;
/// [failure] makes the whole leg throw.
class _FakeIdentityRepository implements MemberPortalRepository {
  _FakeIdentityRepository(this.members);

  List<MemberIdentity> members;
  Object? failure;
  int calls = 0;

  @override
  Future<List<MemberIdentity>> getMyMembers() async {
    calls++;
    if (failure != null) throw failure!;
    return members;
  }
}

class _FakeThemeHydration implements GymThemeHydration {
  final List<String> appliedFor = [];

  @override
  Future<void> applyForGym(String gymId) async => appliedFor.add(gymId);
}

class _FakeProfileRepository implements MemberProfileRepository {
  Object? failure;
  int calls = 0;

  @override
  Future<MemberProfile> getProfile({
    required String gymId,
    required String memberId,
  }) async {
    calls++;
    if (failure != null) throw failure!;
    return MemberProfile(
      memberId: memberId,
      gymId: gymId,
      firstName: 'Jane',
      lastName: 'Doe',
      personalInfo: const BillingPersonalInfo(),
      retention: const BillingRetention(
        classStreakWeeks: 3,
        pointsBalance: 120,
        videosWatched: 0,
      ),
    );
  }
}

MemberIdentity _identity({
  String memberId = 'm1',
  String gymId = 'g1',
  String gymName = 'Global MMA',
  String? gymLogoUrl,
  bool rank = true,
  bool rewards = true,
  bool videos = true,
}) =>
    MemberIdentity(
      memberId: memberId,
      gymId: gymId,
      gymName: gymName,
      firstName: 'Jane',
      lastName: 'Doe',
      gymLogoUrl: gymLogoUrl,
      gymRankEnabled: rank,
      gymHasRewards: rewards,
      gymHasVideos: videos,
    );

/// The app as it stands after boot: member `m1` at gym `g1`, everything on.
Future<void> _bootSelection() => selectedMember.select(
      memberId: 'm1',
      gymId: 'g1',
      gymName: 'Global MMA',
      firstName: 'Jane',
      lastName: 'Doe',
      gymRankEnabled: true,
      gymHasRewards: true,
      gymHasVideos: true,
    );

void main() {
  late _FakeIdentityRepository identity;
  late _FakeThemeHydration theme;
  late _FakeProfileRepository profileRepository;
  late MemberProfileBloc profileBloc;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    identity = _FakeIdentityRepository([_identity()]);
    theme = _FakeThemeHydration();
    profileRepository = _FakeProfileRepository();
    profileBloc = MemberProfileBloc(repository: profileRepository);
    await _bootSelection();
  });

  tearDown(() async {
    await profileBloc.close();
    await selectedMember.reset();
  });

  AppRefresh subject() => AppRefresh(
        identityRepository: identity,
        themeHydration: theme,
      );

  group('a pull re-reads everything the identity read carries', () {
    test('every leg runs: identity, theme, profile, and the screen', () async {
      var screenRefreshes = 0;

      await subject().run(
        profileBloc: profileBloc,
        screen: () async => screenRefreshes++,
      );

      expect(identity.calls, 1);
      expect(theme.appliedFor, ['g1']);
      expect(profileRepository.calls, 1);
      expect(screenRefreshes, 1);
    });

    test(
        'a capability flag flipped server-side lands on SelectedMember — the '
        'change that used to need a relaunch', () async {
      expect(selectedMember.gymRankEnabled, isTrue);
      identity.members = [_identity(rank: false)];

      await subject().run(profileBloc: profileBloc);

      expect(selectedMember.gymRankEnabled, isFalse);
      // The other two are untouched by this gym's change.
      expect(selectedMember.gymHasRewards, isTrue);
      expect(selectedMember.gymHasVideos, isTrue);
    });

    test('all three flags and the gym branding refresh together', () async {
      identity.members = [
        _identity(
          gymName: 'Global MMA & Fitness',
          gymLogoUrl: 'https://cdn.example/logo.png',
          rank: false,
          rewards: false,
          videos: false,
        ),
      ];

      await subject().run(profileBloc: profileBloc);

      expect(selectedMember.gymName, 'Global MMA & Fitness');
      expect(selectedMember.gymLogoUrl, 'https://cdn.example/logo.png');
      expect(selectedMember.gymRankEnabled, isFalse);
      expect(selectedMember.gymHasRewards, isFalse);
      expect(selectedMember.gymHasVideos, isFalse);
    });

    test('the refreshed identity is persisted, so the next boot agrees',
        () async {
      identity.members = [_identity(rank: false)];

      await subject().run(profileBloc: profileBloc);
      // Drop the in-memory fields, then restore the way an offline boot would.
      final restored = SelectedMember();
      expect(await restored.restoreFromCache(), isTrue);

      expect(restored.memberId, 'm1');
      expect(restored.gymRankEnabled, isFalse);
    });
  });

  group('a pull NEVER re-runs the selection ladder', () {
    test('the selected member is kept even when it is not the only row',
        () async {
      identity.members = [
        _identity(memberId: 'm2', gymId: 'g2', gymName: 'Other Gym'),
        _identity(),
      ];

      await subject().run(profileBloc: profileBloc);

      expect(selectedMember.memberId, 'm1');
      expect(selectedMember.gymId, 'g1');
      expect(selectedMember.gymName, 'Global MMA');
    });

    test(
        'a member archived server-side leaves the selection standing — the '
        'ladder would have auto-selected the one row that remains', () async {
      identity.members = [
        _identity(memberId: 'm2', gymId: 'g2', gymName: 'Other Gym'),
      ];

      await subject().run(profileBloc: profileBloc);

      // Stale is recoverable; silently acting as another member is not.
      expect(selectedMember.memberId, 'm1');
      expect(selectedMember.gymId, 'g1');
      expect(selectedMember.gymName, 'Global MMA');
    });

    test('an empty list does not clear the selection either', () async {
      identity.members = const [];

      await subject().run(profileBloc: profileBloc);

      expect(selectedMember.hasSelection, isTrue);
      expect(selectedMember.memberId, 'm1');
    });
  });

  group('one failing leg does not sink the others', () {
    test('a dead identity read still refreshes theme, profile and screen',
        () async {
      identity.failure = const NetworkException('offline');
      var screenRefreshes = 0;

      await subject().run(
        profileBloc: profileBloc,
        screen: () async => screenRefreshes++,
      );

      expect(theme.appliedFor, ['g1']);
      expect(profileRepository.calls, 1);
      expect(screenRefreshes, 1);
    });

    test('a throwing screen leg still lets the identity land', () async {
      identity.members = [_identity(rewards: false)];

      await subject().run(
        profileBloc: profileBloc,
        screen: () async => throw const ServerException('boom'),
      );

      expect(selectedMember.gymHasRewards, isFalse);
      expect(profileRepository.calls, 1);
    });

    test('a failing profile fetch keeps the last-good profile and resolves',
        () async {
      profileRepository.failure = const NetworkException('offline');

      await subject().run(profileBloc: profileBloc);

      expect(identity.calls, 1);
      expect(profileBloc.state.status, isNot(MemberProfileStatus.error));
    });
  });

  group('the spinner tracks real completion', () {
    test('run() does not resolve until every leg has', () async {
      final gate = Completer<void>();
      var done = false;

      final pull = subject().run(
        profileBloc: profileBloc,
        screen: () => gate.future,
      ).then((_) => done = true);

      // Let the fast legs settle; the slow screen leg is still open.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);

      gate.complete();
      await pull;
      expect(done, isTrue);
    });

    test('dispatchRefresh awaits the bloc handler, not just the dispatch',
        () async {
      final slow = _SlowProfileRepository();
      final bloc = MemberProfileBloc(repository: slow);
      var settled = false;

      final pull = dispatchRefresh(
        bloc,
        MemberProfileRefreshRequested.new,
      ).then((_) => settled = true);

      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse, reason: 'the handler is still in flight');

      slow.gate.complete();
      await pull;
      expect(settled, isTrue);
      await bloc.close();
    });

    test('dispatchRefresh on a CLOSED bloc resolves instead of hanging',
        () async {
      final bloc = MemberProfileBloc(repository: _FakeProfileRepository());
      await bloc.close();

      await expectLater(
        dispatchRefresh(bloc, MemberProfileRefreshRequested.new),
        completes,
      );
    });
  });
}

/// A profile fetch that only lands when its gate is opened.
class _SlowProfileRepository implements MemberProfileRepository {
  final Completer<void> gate = Completer<void>();

  @override
  Future<MemberProfile> getProfile({
    required String gymId,
    required String memberId,
  }) async {
    await gate.future;
    return MemberProfile(
      memberId: memberId,
      gymId: gymId,
      firstName: 'Jane',
      lastName: 'Doe',
      personalInfo: const BillingPersonalInfo(),
      retention: const BillingRetention(
        classStreakWeeks: 0,
        pointsBalance: 0,
        videosWatched: 0,
      ),
    );
  }
}
