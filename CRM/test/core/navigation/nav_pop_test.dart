import 'dart:async';

import 'package:crm/core/navigation/nav_pop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The initial/root screen a real in-app pop should land back on.
class _FirstScreen extends StatelessWidget {
  const _FirstScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('First')));
}

/// The deterministic fallback screen [popOrGoTo] replaces onto when the
/// navigator has nothing to pop back to.
class _FallbackScreen extends StatelessWidget {
  const _FallbackScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Fallback')));
}

/// A page whose "Back" button calls [popOrGoTo] — mirrors a real
/// page-level back affordance.
class _PopScreen extends StatelessWidget {
  const _PopScreen({required this.fallbackRoute, this.result});

  final String fallbackRoute;
  final Object? result;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () =>
                popOrGoTo(context, fallbackRoute, result: result),
            child: const Text('Back'),
          ),
        ),
      );
}

void main() {
  group('popOrGoTo', () {
    testWidgets('pops back when the navigator can pop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (_) => const _FirstScreen(),
            '/pop': (_) => const _PopScreen(fallbackRoute: '/fallback'),
            '/fallback': (_) => const _FallbackScreen(),
          },
        ),
      );

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/pop');
      await tester.pumpAndSettle();
      expect(find.text('Back'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      // Popped back to the ORIGINAL route, not replaced onto the fallback
      // — proves the fallback is unused whenever a real pop exists.
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Fallback'), findsNothing);
    });

    testWidgets(
      'replaces with the fallback when there is nothing to pop to',
      (tester) async {
        // A single-route stack — mirrors the auth gate's nested Navigator
        // booting from a hard-reloaded deep URL with no back stack.
        await tester.pumpWidget(
          MaterialApp(
            initialRoute: '/pop',
            routes: {
              '/pop': (_) => const _PopScreen(fallbackRoute: '/fallback'),
              '/fallback': (_) => const _FallbackScreen(),
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Back'), findsOneWidget);

        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();

        // Landed on the fallback screen — never a blank Navigator.
        expect(find.text('Fallback'), findsOneWidget);
        expect(find.text('Back'), findsNothing);
      },
    );

    testWidgets('passes result through on a real pop', (tester) async {
      Object? poppedResult;

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (_) => const _FirstScreen(),
            '/pop': (_) => const _PopScreen(
                  fallbackRoute: '/fallback',
                  result: 'saved',
                ),
            '/fallback': (_) => const _FallbackScreen(),
          },
        ),
      );

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.pushNamed<Object?>('/pop').then((r) => poppedResult = r),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(poppedResult, 'saved');
    });
  });
}
