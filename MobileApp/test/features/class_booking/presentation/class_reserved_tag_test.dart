import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/features/class_booking/presentation/widgets/class_meta_section.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_list_item.dart';
import 'package:mobile_app/shared/widgets/class_reserved_tag.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

ClassOccurrence _occ() => const ClassOccurrence(
      classId: 'c1',
      gymId: 'g1',
      className: 'Muay Thai',
      classDate: '2026-07-23',
      originalDate: '2026-07-23',
      originalTime: '18:00:00',
      occurredAt: '2026-07-23T18:00:00Z',
      resolvedClassTime: '18:00:00',
      resolvedDurationMinutes: 55,
      imageUrl: 'https://x/i.png',
      pointsWorth: 50,
      isCancelled: false,
      hasInstanceException: false,
      hasRangeException: false,
      signupCount: 5,
    );

void main() {
  group('the class detail says outright that you hold the class', () {
    testWidgets('a held reservation shows the reserved tag', (tester) async {
      await tester.pumpWidget(_host(
        ClassMetaSection(
          occurrence: _occ(),
          gymName: 'Titan Dojo',
          reserved: true,
        ),
      ));

      expect(find.byType(ClassReservedTag), findsOneWidget);
      expect(find.text('You\'re reserved'), findsOneWidget);
    });

    testWidgets('no reservation shows no tag at all', (tester) async {
      await tester.pumpWidget(_host(
        ClassMetaSection(
          occurrence: _occ(),
          gymName: 'Titan Dojo',
          reserved: false,
        ),
      ));

      expect(find.byType(ClassReservedTag), findsNothing);
      expect(find.text('You\'re reserved'), findsNothing);
    });

    testWidgets('the tag sits between the class title and its specifics',
        (tester) async {
      // Identity, then where the member stands with it, then the facts — the
      // status must never be buried below the details.
      await tester.pumpWidget(_host(
        ClassMetaSection(
          occurrence: _occ(),
          gymName: 'Titan Dojo',
          reserved: true,
        ),
      ));

      final title = tester.getTopLeft(find.text('Muay Thai')).dy;
      final tag = tester.getTopLeft(find.byType(ClassReservedTag)).dy;
      final gym = tester.getTopLeft(find.text('Titan Dojo')).dy;
      expect(tag, greaterThan(title));
      expect(tag, lessThan(gym));
    });
  });

  group('the schedule board marks reserved occurrences with the SAME tag', () {
    testWidgets('a reserved row carries it', (tester) async {
      await tester.pumpWidget(_host(
        ClassListItem(occurrence: _occ(), booked: true),
      ));

      expect(find.byType(ClassReservedTag), findsOneWidget);
    });

    testWidgets('an unreserved row does not', (tester) async {
      await tester.pumpWidget(_host(
        ClassListItem(occurrence: _occ(), booked: false),
      ));

      expect(find.byType(ClassReservedTag), findsNothing);
    });
  });
}
