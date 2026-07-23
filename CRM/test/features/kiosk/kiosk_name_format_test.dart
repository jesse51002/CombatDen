import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/kiosk/presentation/kiosk_name_format.dart';

void main() {
  group('kioskDisplayName', () {
    test('renders first name + last initial with a trailing period', () {
      expect(kioskDisplayName('Marcus Brown'), 'Marcus B.');
    });

    test('uses the LAST token for the initial on a multi-part name', () {
      expect(kioskDisplayName('Marcus John Brown'), 'Marcus B.');
    });

    test('uppercases only the last initial, first name passed through', () {
      expect(kioskDisplayName('jose garcia'), 'jose G.');
    });

    test('a single-token name renders as-is', () {
      expect(kioskDisplayName('Cher'), 'Cher');
    });

    test('collapses repeated/surrounding whitespace', () {
      expect(kioskDisplayName('  Marcus   Brown  '), 'Marcus B.');
    });

    test('a trailing space (empty last token) shows just the first name', () {
      expect(kioskDisplayName('Marcus '), 'Marcus');
    });

    test('an empty name yields an empty string', () {
      expect(kioskDisplayName(''), '');
    });

    test('a whitespace-only name yields an empty string', () {
      expect(kioskDisplayName('   '), '');
    });
  });
}
