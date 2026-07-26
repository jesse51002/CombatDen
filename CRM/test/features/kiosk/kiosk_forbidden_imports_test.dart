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

  /// Import-path fragments no file in the SHARED component set may reference.
  /// The set renders both surfaces, so anything only one of them may show has
  /// to arrive from outside it — a shared widget that reaches for a
  /// staff-only module is the drift this whole module exists to prevent.
  const bannedShared = <String>[
    // The staff-only discount UI + math. It does not exist yet; the guard is
    // in place FIRST so the surface that adds it lands into a rule rather
    // than being trusted to remember one.
    'membership_flow/discounts/',
  ];

  /// The roots the shared component set lives under. Both are listed even
  /// though one currently nests inside the other: `chrome/` is the set's own
  /// layer and stays guarded wherever it is hoisted to.
  const sharedRoots = <String>[
    'lib/features/membership_flow/presentation',
    'lib/features/membership_flow/chrome',
  ];

  /// Import-path fragments NO file in the membership-flow module may
  /// reference — `domain/`, `config/` and `presentation/` alike.
  ///
  /// The module is what both purchase surfaces DEPEND ON, so it may never
  /// depend on either of them. A component that takes a kiosk state type is
  /// shared in name only: the desk cannot construct one, so it cannot render
  /// the component, and the whole module goes back to being decoration.
  const bannedModule = <String>[
    // The kiosk is a HOST of this module, never a dependency of it — its
    // cubit, its state, its copy and its own widgets all stay on its side of
    // the seam, and reach the shared set as plain data and callbacks.
    'package:crm/features/kiosk/',
    // The CRM member-detail SCREEN layer — the other host's own surface, and
    // the home of the staff tooling OVER the flow (nested dialogs a
    // member-facing kiosk can never open). Its `data/models/` are fine and
    // deliberate: those are the wire contract both surfaces speak.
    'package:crm/features/member_details/presentation/',
  ];

  /// The module's root. One entry, walked recursively, so a new layer added
  /// beside `domain/` is guarded the day it appears rather than the day
  /// somebody remembers to list it.
  const moduleRoots = <String>['lib/features/membership_flow'];

  List<File> dartFilesUnder(Iterable<String> roots) {
    return [
      for (final path in roots)
        if (Directory(path).existsSync())
          ...Directory(path)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
    ];
  }

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

  List<String> importOffences(List<File> files, List<String> fragments) {
    final offences = <String>[];
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.startsWith('import ') && !line.startsWith('export ')) {
          continue;
        }
        for (final fragment in fragments) {
          if (line.contains(fragment)) {
            offences.add('${file.path}:${i + 1} → $fragment');
          }
        }
      }
    }
    return offences;
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

  test('the shared component set is non-empty', () {
    expect(
      dartFilesUnder(sharedRoots),
      isNotEmpty,
      reason: 'the shared membership-flow components moved or were renamed — '
          'point `sharedRoots` at wherever they live now, or the two guards '
          'below silently protect nothing',
    );
  });

  test('no shared flow component imports a staff-only module', () {
    final offences =
        importOffences(dartFilesUnder(sharedRoots), bannedShared);
    expect(
      offences,
      isEmpty,
      reason: 'A component in the shared set renders BOTH surfaces, so it may '
          'never reach for something only one of them has. A staff-only '
          'capability is INJECTED by the host that owns it (the kiosk factory '
          'cannot construct one, which is what keeps the no-discounts rule '
          'structural rather than a `showDiscounts: false` default). Offending '
          'imports:\n${offences.join('\n')}',
    );
  });

  test('the membership-flow module is non-empty', () {
    expect(
      dartFilesUnder(moduleRoots),
      isNotEmpty,
      reason: 'the membership-flow module moved or was renamed — point '
          '`moduleRoots` at wherever it lives now, or the guard below '
          'silently protects nothing',
    );
  });

  test('no membership-flow file imports a SURFACE', () {
    final offences = importOffences(dartFilesUnder(moduleRoots), bannedModule);
    expect(
      offences,
      isEmpty,
      reason: 'The membership-flow module is what both purchase surfaces '
          'depend on, so it may never depend on either of them. A shared '
          'component that takes `KioskSignupState` (or reads '
          '`KioskSignupCubit` off the context) is shared in NAME only — the '
          'desk cannot construct one, so it cannot render the component. '
          'State arrives as a plain view model from '
          '`membership_flow/presentation/models/`, built by each host; '
          'intent leaves as a callback. Offending imports:\n'
          '${offences.join('\n')}',
    );
  });

  test('no shared flow component imports the kiosk\'s banned modules either',
      () {
    // The kiosk renders every one of these, so the fresh-card law reaches
    // through them: a saved-card or payer-selection surface pulled in HERE
    // lands on the kiosk without ever appearing under `lib/features/kiosk/`.
    final offences = importOffences(dartFilesUnder(sharedRoots), banned);
    expect(
      offences,
      isEmpty,
      reason: 'The kiosk renders the shared component set, so its bans apply '
          'to the set as well — otherwise moving a file out of '
          '`lib/features/kiosk/` would be enough to escape them. Offending '
          'imports:\n${offences.join('\n')}',
    );
  });
}
