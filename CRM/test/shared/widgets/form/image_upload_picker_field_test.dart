import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/shared/widgets/form/image_upload_picker_field.dart';
import 'package:crm/shared/widgets/horizontal_scroller.dart';

import 'fake_network_images.dart';

const _urlA = 'https://cdn.combatden.net/member/presets/portrait-01.jpg';
const _urlB = 'https://cdn.combatden.net/member/presets/portrait-02.jpg';

Finder get _selectedChips => find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.selected == true,
    );

// A specific pool chip, found by the URL of its network image (order- and
// scroll-independent, unlike `find.byType(Image).at(i)`).
Finder _chip(String url) => find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is NetworkImage &&
          (w.image as NetworkImage).url == url,
    );

Future<void> _pumpField(
  WidgetTester tester, {
  required ValueChanged<String> onImageChosen,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ImageUploadPickerField(
          label: 'Member photo',
          category: 'member',
          poolImages: const [_urlA, _urlB],
          onImageChosen: onImageChosen,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    // The field builds an ApiClient() in initState, which reads API_BASE_URL
    // from dotenv — load a throwaway value so construction doesn't throw.
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
  });

  testWidgets('tapping a pool chip selects it and fires onImageChosen',
      (tester) async {
    await withFakeNetworkImages(() async {
      String? chosen;
      await _pumpField(tester, onImageChosen: (url) => chosen = url);

      // Nothing selected before a pick: no ring/badge, no selected semantics.
      expect(_selectedChips, findsNothing);
      expect(find.byIcon(Symbols.check_sharp), findsNothing);

      await tester.tap(_chip(_urlA));
      await tester.pump();

      expect(chosen, _urlA);
      expect(_selectedChips, findsOneWidget);
      expect(find.byIcon(Symbols.check_sharp), findsOneWidget);
    });
  });

  testWidgets('picking another chip moves the single selection',
      (tester) async {
    await withFakeNetworkImages(() async {
      String? chosen;
      await _pumpField(tester, onImageChosen: (url) => chosen = url);

      await tester.tap(_chip(_urlA));
      await tester.pump();
      await tester.tap(_chip(_urlB));
      await tester.pump();

      // Mutually exclusive: the second pick wins and exactly one chip is lit.
      expect(chosen, _urlB);
      expect(_selectedChips, findsOneWidget);
      expect(find.byIcon(Symbols.check_sharp), findsOneWidget);
    });
  });

  testWidgets('a chip whose image fails to load collapses out of the strip',
      (tester) async {
    // A loads (200), B fails (404). B's chip must drop; A's must survive and
    // the trailing upload tile always stays.
    await withFakeNetworkImages(
      () async {
        await _pumpField(tester, onImageChosen: (_) {});
        await tester.pumpAndSettle();

        expect(_chip(_urlA), findsOneWidget);
        expect(_chip(_urlB), findsNothing);

        // The upload tile (add-photo icon inside the tray) is still present.
        final trayUpload = find.descendant(
          of: find.byType(HorizontalScroller),
          matching: find.byIcon(Symbols.add_photo_alternate_sharp),
        );
        expect(trayUpload, findsOneWidget);
      },
      failUrls: const {_urlB},
    );
  });
}
