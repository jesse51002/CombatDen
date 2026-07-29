import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/features/stats/data/promotion_rules.dart';

void main() {
  test('no promotion on the profile is a skip', () {
    expect(
      decidePromotion(lastSeenActivityId: null, activityId: null),
      PromotionDecision.skip,
    );
    expect(
      decidePromotion(lastSeenActivityId: 'a1', activityId: null),
      PromotionDecision.skip,
    );
  });

  test('a null watermark SEEDS silently rather than replaying history', () {
    // A member promoted in March who reinstalls in July must not be shown a
    // belt they have held for four months. Same rule as the celebration
    // watermark; a second device does the same on its first open.
    expect(
      decidePromotion(lastSeenActivityId: null, activityId: 'march-row'),
      PromotionDecision.seedSilently,
    );
  });

  test('the same activity id is never celebrated twice', () {
    expect(
      decidePromotion(lastSeenActivityId: 'a1', activityId: 'a1'),
      PromotionDecision.skip,
    );
  });

  test('a different activity id fires', () {
    expect(
      decidePromotion(lastSeenActivityId: 'a1', activityId: 'a2'),
      PromotionDecision.fire,
    );
  });

  test('a LEXICALLY SMALLER id still fires — the key is not ordered', () {
    // `activity_id` is opaque and unordered, and the rule compares by
    // EQUALITY on purpose: the server only ever surfaces the newest genuine
    // promotion, so a different id is by construction a newer one. If someone
    // "fixes" this into a comparison, this test is what catches it.
    expect(
      decidePromotion(lastSeenActivityId: 'zzzz', activityId: 'aaaa'),
      PromotionDecision.fire,
    );
    expect(
      decidePromotion(
        lastSeenActivityId: 'ffffffff-0000-0000-0000-000000000000',
        activityId: '00000000-0000-0000-0000-000000000001',
      ),
      PromotionDecision.fire,
    );
  });

  test('the decision reads the id and NOTHING else', () {
    // `promoted_at` is display-and-ordering only; it is not an input here, so
    // a re-recorded timestamp on the same row cannot re-fire the animation.
    // (The end-to-end proof lives in celebration_detector_test.dart.)
    expect(
      decidePromotion(lastSeenActivityId: 'a1', activityId: 'a1'),
      PromotionDecision.skip,
    );
  });
}
