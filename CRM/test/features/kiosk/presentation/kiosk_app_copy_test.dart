import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/kiosk/presentation/kiosk_app_copy.dart';

/// The member app is WHITE-LABELLED: a member downloads THEIR GYM's app, so
/// every kiosk line that names it carries the gym's name and never the
/// platform's (founder ruling).
///
/// The gym name comes from `selectedGym.gymName`, which is nullable and can be
/// blank, so the load-bearing half of these is the fallback: a member-facing
/// kiosk must never print an empty word, a doubled space, or a stand-in gym.
void main() {
  const gym = 'Iron Den';

  group('with a gym name', () {
    test('every line names the gym', () {
      expect(kioskGetAppTitle(gym), 'Get the Iron Den App');
      expect(kioskAppStoreLine(gym), 'Get the Iron Den app in the App Store.');
      expect(kioskRedeemInAppLine(gym), 'Redeem rewards in the Iron Den app');
      expect(kioskBookInAppLine(gym), 'Get the Iron Den app to book classes');
    });

    test('a padded name is trimmed, not printed with its whitespace', () {
      expect(
        kioskGetAppTitle('  Ocean Pilates  '),
        'Get the Ocean Pilates App',
      );
    });

    test('no line ever says CombatDen', () {
      for (final line in [
        kioskGetAppTitle(gym),
        kioskAppStoreLine(gym),
        kioskRedeemInAppLine(gym),
        kioskBookInAppLine(gym),
      ]) {
        expect(line, isNot(contains('CombatDen')));
      }
    });
  });

  group('with no usable gym name', () {
    for (final absent in <String?>[null, '', '   ']) {
      test('${absent == null ? 'null' : '"$absent"'} falls back to naming the '
          'app generically', () {
        expect(kioskGymName(absent), isNull);
        expect(kioskGetAppTitle(absent), 'Get the App');
        expect(kioskAppStoreLine(absent), 'Get the app in the App Store.');
        expect(kioskRedeemInAppLine(absent), 'Redeem rewards in the app');
        expect(kioskBookInAppLine(absent), 'Get the app to book classes');
      });

      test('${absent == null ? 'null' : '"$absent"'} leaves no hole in the '
          'sentence', () {
        for (final line in [
          kioskGetAppTitle(absent),
          kioskAppStoreLine(absent),
          kioskRedeemInAppLine(absent),
          kioskBookInAppLine(absent),
        ]) {
          expect(line.trim(), line);
          expect(line, isNot(contains('  ')));
          expect(line, isNot(contains('the  ')));
        }
      });
    }
  });
}
