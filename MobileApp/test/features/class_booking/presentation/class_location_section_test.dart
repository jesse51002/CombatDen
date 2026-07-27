import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/features/class_booking/presentation/widgets/class_location_section.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('ClassLocationSection', () {
    testWidgets('renders the address + the maps action when set',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const ClassLocationSection(
            gymName: 'Iron Fist MMA',
            address: '742 Evergreen Terrace, Springfield, IL',
          ),
        ),
      );

      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Iron Fist MMA'), findsOneWidget);
      expect(
        find.text('742 Evergreen Terrace, Springfield, IL'),
        findsOneWidget,
      );
      expect(find.text('Open in Maps'), findsOneWidget);
    });

    testWidgets('falls back to the gym name alone when the address is absent',
        (tester) async {
      await tester.pumpWidget(
        _host(const ClassLocationSection(gymName: 'Iron Fist MMA')),
      );

      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Iron Fist MMA'), findsOneWidget);
      expect(find.text('Open in Maps'), findsNothing);
    });

    testWidgets('treats a blank address as absent', (tester) async {
      await tester.pumpWidget(
        _host(
          const ClassLocationSection(gymName: 'Iron Fist MMA', address: '   '),
        ),
      );

      expect(find.text('Open in Maps'), findsNothing);
    });

    testWidgets('does not truncate a long address', (tester) async {
      const long = '1234 Northwest Industrial Parkway Suite 1100, '
          'Some Very Long City Name, State 000000';
      await tester.pumpWidget(
        _host(const ClassLocationSection(gymName: 'Gym', address: long)),
      );

      final text = tester.widget<Text>(find.text(long));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);
    });
  });
}
