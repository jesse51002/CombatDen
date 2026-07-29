import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/features/stats/data/promotion_watermark.dart';

void main() {
  const watermark = PromotionWatermark();

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('lastSeen is null when no watermark has been stored', () async {
    expect(await watermark.lastSeen('m1'), isNull);
  });

  test('mark then lastSeen round-trips the activity id', () async {
    await watermark.mark('m1', 'a1b2c3');
    expect(await watermark.lastSeen('m1'), 'a1b2c3');
  });

  test('watermarks are isolated per member', () async {
    await watermark.mark('memberA', 'activity-a');
    await watermark.mark('memberB', 'activity-b');

    expect(await watermark.lastSeen('memberA'), 'activity-a');
    expect(await watermark.lastSeen('memberB'), 'activity-b');
    // A write for A does not satisfy B, and a never-seen member reads null
    // even when others have watermarks — one email legitimately maps to
    // several profiles, so a family must not consume each other's belts.
    expect(await watermark.lastSeen('memberC'), isNull);
  });

  test('mark advances an existing watermark', () async {
    await watermark.mark('m1', 'first');
    await watermark.mark('m1', 'second');
    expect(await watermark.lastSeen('m1'), 'second');
  });

  test('an empty stored value reads as null, not as a seen id', () async {
    // A corrupt / half-written preference must degrade to "never seen", which
    // seeds silently, rather than to an id nothing can ever equal.
    SharedPreferences.setMockInitialValues({
      PromotionWatermark.keyFor('m1'): '',
    });
    expect(await watermark.lastSeen('m1'), isNull);
  });

  test('keyFor is scoped per member, and distinct from the celebration one',
      () {
    expect(PromotionWatermark.keyFor('abc'), 'promotion_watermark_abc');
  });
}
