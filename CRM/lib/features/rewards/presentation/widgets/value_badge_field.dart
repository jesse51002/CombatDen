import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/filter_pills.dart';

/// The badge values a gym reaches for most of the time. Tapping one fills
/// the field; the field itself stays open for anything else.
const List<String> kValueBadgePresets = <String>[
  'Free',
  '10% off',
  '25% off',
  '50% off',
];

/// Hard cap on a badge. It renders inside a small pill on the member's
/// reward card, so anything longer than this is a description in disguise
/// — which is exactly the mistake this field exists to prevent.
const int kValueBadgeMaxLength = 16;

/// Index of the preset [text] matches (trimmed, case-insensitive), or `-1`
/// when the badge is custom or empty. [FilterPills] renders nothing as
/// selected for `-1`, so a custom badge simply lights no chip.
int valueBadgePresetIndex(String text) {
  final normalized = text.trim().toLowerCase();
  if (normalized.isEmpty) return -1;
  return kValueBadgePresets.indexWhere(
    (preset) => preset.toLowerCase() == normalized,
  );
}

/// The reward's value badge — `gym_rewards.price_label`, the short pill a
/// member reads on the reward card. **Not** a description: the seed once
/// wrote subtitle copy here ("Post-workout recovery") and it rendered
/// crammed into that pill, so this field guides toward a real badge instead
/// of offering a bare free-text box.
///
/// Quick-pick chips fill the field in one tap. The field stays freely
/// editable for the values a chip can't cover (`1 week`, `BOGO`), capped at
/// [kValueBadgeMaxLength] characters by [_BadgeLengthFormatter] — which caps
/// what is TYPED without ever trimming a longer badge the gym already saved.
/// The chips only ever *reflect* the field — whichever preset the current text
/// matches is lit, and nothing is lit while the text is custom or empty.
class ValueBadgeField extends StatelessWidget {
  final TextEditingController controller;

  const ValueBadgeField({super.key, required this.controller});

  void _pick(String badge) {
    controller.value = TextEditingValue(
      text: badge,
      selection: TextSelection.collapsed(offset: badge.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          Text(
            'Value badge',
            style: DesignConstants.h2.copyWith(color: DesignConstants.text),
          ),
          FilterPills(
            labels: kValueBadgePresets,
            selectedIndex: valueBadgePresetIndex(value.text),
            onSelected: (index) => _pick(kValueBadgePresets[index]),
          ),
          CustomTextField(
            controller: controller,
            hintText: 'e.g. Free',
            helperText: 'e.g. Free, 25% off. '
                'Max $kValueBadgeMaxLength characters.',
            inputFormatters: const [
              _BadgeLengthFormatter(kValueBadgeMaxLength),
            ],
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'A value badge is required.'
                : null,
          ),
        ],
      ),
    );
  }
}

/// Caps typing at [maxLength] **without ever silently trimming the value the
/// field was handed.**
///
/// A plain [LengthLimitingTextInputFormatter] truncates on the first edit
/// event, so a `price_label` written before this cap existed was destroyed the
/// moment staff put a caret in the field: characters vanished with no keystroke
/// that removed them, and the next tap on Save persisted the shortened badge.
/// Formatters never see the INITIAL value, only edits — which is exactly why
/// that damage was invisible.
///
/// So the cap governs GROWTH rather than length:
/// * **within the cap** — the standard limiter, unchanged (a long paste
///   truncates, but visibly, in front of the person who pasted it);
/// * **already over the cap** — an edit that does not make the text longer
///   passes through verbatim, so a legacy badge is shortened one character at a
///   time with every step on screen; an edit that would grow it is refused
///   whole (the old value stands) rather than truncated to [maxLength], which
///   would again drop characters nobody deleted.
///
/// Lengths are compared in code units while the truncation itself delegates to
/// [LengthLimitingTextInputFormatter] (grapheme-correct). The two diverge only
/// on a badge holding astral characters, and there the worst case is one
/// refused keystroke — never a lost character.
class _BadgeLengthFormatter extends TextInputFormatter {
  const _BadgeLengthFormatter(this.maxLength);

  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text.length <= maxLength) {
      return LengthLimitingTextInputFormatter(maxLength)
          .formatEditUpdate(oldValue, newValue);
    }
    return newValue.text.length <= oldValue.text.length ? newValue : oldValue;
  }
}
