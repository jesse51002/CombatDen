import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/features/member_select/data/models/member_identity.dart';
import 'package:mobile_app/features/member_select/logic/member_selection_resolver.dart';

MemberIdentity _member(String id) => MemberIdentity(
      memberId: id,
      gymId: 'gym-$id',
      gymName: 'Gym $id',
      firstName: 'First',
      lastName: id,
    );

void main() {
  group('resolveMemberSelection (the boot revalidation ladder)', () {
    test('no rows → empty (the no-membership state)', () {
      final decision =
          resolveMemberSelection(persistedId: 'a', members: const []);
      expect(decision.outcome, MemberSelectionOutcome.empty);
      expect(decision.member, isNull);
    });

    test('persisted id present in the fresh list → restore that row', () {
      final members = [_member('a'), _member('b'), _member('c')];
      final decision =
          resolveMemberSelection(persistedId: 'b', members: members);
      expect(decision.outcome, MemberSelectionOutcome.restore);
      expect(decision.member?.memberId, 'b');
    });

    test('stale persisted id + exactly one row → auto-select', () {
      final members = [_member('a')];
      final decision =
          resolveMemberSelection(persistedId: 'gone', members: members);
      expect(decision.outcome, MemberSelectionOutcome.autoSelect);
      expect(decision.member?.memberId, 'a');
    });

    test('stale persisted id + 2+ rows → picker', () {
      final members = [_member('a'), _member('b')];
      final decision =
          resolveMemberSelection(persistedId: 'gone', members: members);
      expect(decision.outcome, MemberSelectionOutcome.picker);
      expect(decision.member, isNull);
    });

    test('no persisted id + one row → auto-select', () {
      final members = [_member('a')];
      final decision =
          resolveMemberSelection(persistedId: null, members: members);
      expect(decision.outcome, MemberSelectionOutcome.autoSelect);
      expect(decision.member?.memberId, 'a');
    });

    test('no persisted id + 2+ rows → picker', () {
      final members = [_member('a'), _member('b')];
      final decision =
          resolveMemberSelection(persistedId: null, members: members);
      expect(decision.outcome, MemberSelectionOutcome.picker);
    });

    test('restore wins over count even with many rows', () {
      final members = [_member('a'), _member('b'), _member('c')];
      final decision =
          resolveMemberSelection(persistedId: 'c', members: members);
      expect(decision.outcome, MemberSelectionOutcome.restore);
      expect(decision.member?.memberId, 'c');
    });
  });
}
