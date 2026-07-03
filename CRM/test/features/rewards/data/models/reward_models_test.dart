import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/rewards/data/models/pending_redemption_item.dart';
import 'package:crm/features/rewards/data/models/pending_redemption_list_response.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';

/// Locks the wire shape: the backend emits snake_case, so these models
/// MUST parse snake_case keys. A missing `fieldRename: FieldRename.snake`
/// on the annotation regenerates camelCase lookups and crashes the whole
/// Loyalty catalog + approval queue at runtime — invisible to analyze.
void main() {
  test('RewardResponse parses the backend snake_case payload', () {
    final reward = RewardResponse.fromJson({
      'reward_id': 'r-1',
      'gym_id': 'g-1',
      'title': 'Club t-shirt',
      'point_cost': 1500,
      'image_url': 'https://cdn.combatden.net/reward/x.jpg?v=abc',
      'price_label': 'Free',
      'is_active': true,
      'created_at': '2026-07-01T12:00:00Z',
    });

    expect(reward.rewardId, 'r-1');
    expect(reward.gymId, 'g-1');
    expect(reward.pointCost, 1500);
    expect(reward.priceLabel, 'Free');
    expect(reward.isActive, isTrue);
  });

  test('PendingRedemptionItem parses the backend snake_case payload', () {
    final item = PendingRedemptionItem.fromJson({
      'redemption_id': 'rd-1',
      'member_id': 'm-1',
      'member_name': 'Sam Trainee',
      'reward_title': 'Club t-shirt',
      'reward_image_url': null,
      'point_cost': 1500,
      'requested_at': '2026-07-01T12:00:00Z',
    });

    expect(item.redemptionId, 'rd-1');
    expect(item.memberId, 'm-1');
    expect(item.memberName, 'Sam Trainee');
    expect(item.pointCost, 1500);
    expect(item.requestedAt.isUtc, isTrue);
  });

  test('PendingRedemptionListResponse parses items + total', () {
    final response = PendingRedemptionListResponse.fromJson({
      'items': [
        {
          'redemption_id': 'rd-1',
          'member_id': 'm-1',
          'member_name': 'Sam Trainee',
          'reward_title': 'Club t-shirt',
          'reward_image_url': null,
          'point_cost': 1500,
          'requested_at': '2026-07-01T12:00:00Z',
        },
      ],
      'total': 7,
    });

    expect(response.items, hasLength(1));
    expect(response.items.first.redemptionId, 'rd-1');
    expect(response.total, 7);
  });
}
