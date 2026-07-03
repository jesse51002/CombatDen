import 'package:crm/core/utils/waiver_render.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fills clean tokens; leaves unknown and empty-valued tokens', () {
    final out = renderWaiverPlaceholders(
      'Hi {{member_name}}, {{nope}} and {{signer_name}} stay',
      {'member_name': 'Jane Doe', 'signer_name': ''},
    );
    expect(out, 'Hi Jane Doe, {{nope}} and {{signer_name}} stay');
  });

  test('fills markdown-escaped tokens exactly like the clean form', () {
    // DeltaToMarkdown used to store tokens as \{\{member\_name\}\} — the
    // regression that shipped unrenderable bodies in live testing.
    final out = renderWaiverPlaceholders(
      r'I \{\{member\_name\}\} sign on \{\{date\}\} at \{\{gym\_name\}\}',
      {'member_name': 'Jane Doe', 'date': '2026-07-02', 'gym_name': 'Iron'},
    );
    expect(out, 'I Jane Doe sign on 2026-07-02 at Iron');
  });
}
