import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/shared/widgets/form/image_upload_picker_field.dart';

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

  testWidgets('picking another chip moves the single selection',
      (tester) async {
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
}
