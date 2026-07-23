import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/stats/data/celebration_watermark.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const watermark = CelebrationWatermark();

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('lastSeen is null when no watermark has been stored', () async {
    expect(await watermark.lastSeen('m1'), isNull);
  });

  test('mark then lastSeen round-trips the instant', () async {
    final at = DateTime.utc(2026, 7, 23, 18, 30);
    await watermark.mark('m1', at);
    expect(await watermark.lastSeen('m1'), at);
  });

  test('watermarks are isolated per member', () async {
    final atA = DateTime.utc(2026, 7, 23, 18, 0);
    final atB = DateTime.utc(2026, 7, 20, 9, 0);
    await watermark.mark('memberA', atA);
    await watermark.mark('memberB', atB);

    expect(await watermark.lastSeen('memberA'), atA);
    expect(await watermark.lastSeen('memberB'), atB);
    // A never-seen member reads null even when others have watermarks.
    expect(await watermark.lastSeen('memberC'), isNull);
  });

  test('mark advances an existing watermark', () async {
    final first = DateTime.utc(2026, 7, 20, 9, 0);
    final second = DateTime.utc(2026, 7, 23, 18, 0);
    await watermark.mark('m1', first);
    await watermark.mark('m1', second);
    expect(await watermark.lastSeen('m1'), second);
  });

  test('keyFor is scoped per member', () {
    expect(CelebrationWatermark.keyFor('abc'), 'celebration_watermark_abc');
  });
}
