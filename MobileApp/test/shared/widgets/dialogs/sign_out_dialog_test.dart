import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/shared/widgets/dialogs/sign_out_dialog.dart';

/// Opens the dialog from a button and records what it resolved to.
Future<List<bool?>> _open(WidgetTester tester) async {
  final results = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(await SignOutDialog.show(
              context,
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  group('SignOutDialog', () {
    testWidgets('renders the copy and both actions', (tester) async {
      await _open(tester);

      expect(find.text('Sign out?'), findsOneWidget);
      expect(find.text('Stay signed in'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(
        find.textContaining('Your streak, points and rank stay'),
        findsOneWidget,
      );
    });

    testWidgets('confirming resolves true', (tester) async {
      final results = await _open(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(results, [true]);
    });

    testWidgets('staying signed in resolves false', (tester) async {
      final results = await _open(tester);

      await tester.tap(find.text('Stay signed in'));
      await tester.pumpAndSettle();

      expect(results, [false]);
    });

    testWidgets('a rank-OFF gym does not promise a rank back', (tester) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await selectedMember.select(
        memberId: 'm1',
        gymId: 'g1',
        gymName: 'Global MMA',
        firstName: 'Jane',
        lastName: 'Doe',
        gymRankEnabled: false,
      );
      addTearDown(selectedMember.reset);

      await _open(tester);

      expect(
        find.textContaining('Your streak and points stay'),
        findsOneWidget,
      );
      expect(find.textContaining('rank'), findsNothing);
    });
  });
}
