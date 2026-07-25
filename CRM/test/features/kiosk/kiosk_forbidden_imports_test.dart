import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The fresh-card law, executable: the kiosk never charges a PRE-EXISTING
/// card. Every card it charges is one entered during the current signup, and
/// it becomes that payer's default — which is why an existing member may
/// self-serve here at all.
///
/// This is the law's STRUCTURAL half. No kiosk file may import the CRM's
/// saved-card or payer-selection modules, or any module that reduces a price:
/// they offer a card the kiosk did not take and a price it may not set. An
/// import ban rather than a `showDiscounts: false` flag, which is one wrong
/// default away from a member discounting their own membership. The kiosk's
/// own payer picker is fine — it only names WHO pays, and whoever it names
/// still types a fresh card (`kiosk_signup_payer_test.dart` is that
/// behavioural half). A FRONTEND guard, accepted given the supervised iPad +
/// Guided Access.
///
/// Each banned name is asserted below to still exist, so a rename can never
/// leave the ban silently stale — rename the entry, never delete it.
void main() {
  /// Import-path fragments no file under `lib/features/kiosk/` may reference.
  /// Fragments, not full paths, so a moved file stays banned.
  const banned = <String>[
    // Saved / existing card surfaces — the kiosk enters a fresh card, always.
    'saved_card_section',
    'one_time_card_dialog',
    'update_card_dialog',
    // Discounts, in every shape. `grep -ri discount lib/features/kiosk/`
    // must stay empty.
    'discount_picker_dialog',
    'draft_discounts_card',
    'added_discount_chip',
    'custom_discount_',
    'live_discounted_price',
    // The CRM's own DESK payer-selection surfaces — they offer payers whose
    // saved card would then be chargeable. The kiosk's own picker doesn't:
    // it carries no eligibility gate, and whoever it names types a fresh card.
    'start_payer_step',
    'choose_payer_view',
    'payer_radio_tile',
  ];

  /// The files each banned fragment stands for. If a path here stops
  /// existing the ban above has gone stale and the guard is theatre.
  const guardedFiles = <String>[
    'lib/features/member_details/presentation/dialogs/start_memberships/saved_card_section.dart',
    'lib/features/member_details/presentation/dialogs/start_memberships/one_time_card_dialog.dart',
    'lib/features/member_details/presentation/dialogs/update_card_dialog.dart',
    'lib/features/member_details/presentation/dialogs/start_memberships/discount_picker_dialog.dart',
    'lib/features/member_details/presentation/dialogs/start_memberships/draft_discounts_card.dart',
    'lib/features/member_details/presentation/dialogs/start_memberships/added_discount_chip.dart',
    'lib/features/member_details/presentation/dialogs/start_memberships/custom_discount_value_form.dart',
    'lib/features/member_details/presentation/dialogs/start_memberships/live_discounted_price.dart',
    'lib/features/member_details/presentation/dialogs/start_memberships/start_payer_step.dart',
    'lib/features/member_details/presentation/dialogs/add_member/choose_payer_view.dart',
    'lib/features/member_details/presentation/dialogs/add_member/payer_radio_tile.dart',
  ];

  List<File> kioskFiles() {
    final root = Directory('lib/features/kiosk');
    expect(root.existsSync(), isTrue,
        reason: 'run this suite from the CRM package root');
    return root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  test('every guarded module still exists (the ban is not stale)', () {
    for (final path in guardedFiles) {
      expect(File(path).existsSync(), isTrue,
          reason: 'guarded file $path is gone — the matching entry in '
              '`banned` no longer protects anything. Update BOTH lists.');
    }
  });

  test('the kiosk feature tree is non-empty', () {
    expect(kioskFiles(), isNotEmpty);
  });

  test('no kiosk file imports a saved-card, payer-picker or discount module',
      () {
    final offences = <String>[];
    for (final file in kioskFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.startsWith('import ') && !line.startsWith('export ')) {
          continue;
        }
        for (final fragment in banned) {
          if (line.contains(fragment)) {
            offences.add('${file.path}:${i + 1} → $fragment');
          }
        }
      }
    }
    expect(
      offences,
      isEmpty,
      reason: 'The kiosk must never import the CRM\'s saved-card, '
          'payer-selection or discount modules — that is the fresh-card law, '
          'and it is structural rather than a flag. A kiosk-native payer '
          'picker is fine: it only names WHO pays, and whoever it names types '
          'a fresh card that replaces the one on their profile — every payer, '
          'no eligibility gate. Offending imports:\n'
          '${offences.join('\n')}',
    );
  });

  test('the word "discount" appears nowhere in the kiosk feature', () {
    final offences = <String>[];
    for (final file in kioskFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].toLowerCase().contains('discount')) {
          offences.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(
      offences,
      isEmpty,
      reason: 'No discount reaches the kiosk in any form — not staff-applied, '
          'not a member-entered promo code, not a disabled parameter, not a '
          'comment that invites one. Offending lines:\n'
          '${offences.join('\n')}',
    );
  });
}
