import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';

/// The earliest birth date the wheel offers. A hard floor is needed anyway
/// (an unbounded wheel scrolls forever); 1900 clears any living member.
final DateTime kKioskDobMinDate = DateTime(1900);

/// Date of birth, entered on a WHEEL — never as free text (ruling 6).
///
/// Typing eight digits behind an iPadOS keyboard that eats half the screen is
/// the worst input in the flow, and free text would need strict parsing and a
/// sane year range regardless. The wheel gives both for free, and the field
/// cannot hold an invalid value at all.
///
/// The range is [kKioskDobMinDate] → today: a birth date in the future is not
/// a thing, and the upper bound removes the only mistake the control could
/// otherwise make. **There is deliberately no under-13 handling** — an age
/// gate is a policy the gym owns at the desk, not a rule a kiosk invents.
///
/// Optional like everything else on its step: no value is a legitimate answer,
/// so the sheet carries a "Clear" alongside its Done.
///
/// **Done stays inert until the wheel actually reports a date.** An empty field
/// has to open the wheel somewhere and that somewhere is today, which is nobody
/// alive's birth date — so a Done that committed the opening position would
/// write today into the member's record on a tap that chose nothing. "No date"
/// is said with Clear, deliberately, never by leaving the wheel alone.
class KioskDobField extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String label;

  const KioskDobField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Date of birth',
  });

  /// The member-facing form of a chosen date. `MM / DD / YYYY` mirrors the
  /// placeholder the mockup draws, so the box reads the same empty or full.
  static String display(DateTime date) =>
      DateFormat('MM / dd / yyyy').format(date);

  @override
  Widget build(BuildContext context) {
    final chosen = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(label, style: DesignConstants.kioskLabel),
        InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          child: Container(
            // The same box the typed kiosk fields wear, so a wheel-backed
            // field never reads as a different KIND of control from the ones
            // above and below it.
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.paddingSmall,
              vertical: DesignConstants.spacingMedium,
            ),
            decoration: BoxDecoration(
              color: DesignConstants.card,
              borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
              border: Border.all(color: DesignConstants.text),
              boxShadow: DesignConstants.controlShadow,
            ),
            child: Row(
              spacing: DesignConstants.spacingMedium,
              children: [
                Icon(
                  Symbols.calendar_month_sharp,
                  size: DesignConstants.iconSizeLarge,
                  weight: DesignConstants.iconWeight,
                  color: DesignConstants.text2nd,
                ),
                Expanded(
                  child: Text(
                    chosen == null ? 'MM / DD / YYYY' : display(chosen),
                    style: DesignConstants.kioskFieldText.copyWith(
                      fontWeight:
                          chosen == null ? FontWeight.w400 : FontWeight.w500,
                      color: chosen == null
                          ? DesignConstants.text2nd
                          : DesignConstants.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context) async {
    final today = DateTime.now();
    final maximum = DateTime(today.year, today.month, today.day);
    // The date already held (clamped, in case the day rolled over since it was
    // picked) and the position the wheel opens on are TWO different things, and
    // they are passed separately: with nothing held the wheel still has to open
    // somewhere, but that position is not an answer.
    final current = value;
    final held = current == null || current.isAfter(maximum) ? null : current;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: DesignConstants.popup,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DesignConstants.radiusCard),
        ),
      ),
      builder: (sheetContext) => _DobSheet(
        held: held,
        seed: held ?? maximum,
        maximum: maximum,
        onDone: (picked) {
          onChanged(picked);
          Navigator.of(sheetContext).pop();
        },
        onClear: () {
          onChanged(null);
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }
}

/// The sheet body: the wheel, then its two actions.
class _DobSheet extends StatefulWidget {
  /// The date the field already holds, or null when it holds none — what Done
  /// starts out able to commit.
  final DateTime? held;

  /// Where the wheel opens. With nothing held that is today: a starting
  /// position, never an answer.
  final DateTime seed;

  final DateTime maximum;
  final ValueChanged<DateTime> onDone;
  final VoidCallback onClear;

  const _DobSheet({
    required this.held,
    required this.seed,
    required this.maximum,
    required this.onDone,
    required this.onClear,
  });

  @override
  State<_DobSheet> createState() => _DobSheetState();
}

class _DobSheetState extends State<_DobSheet> {
  /// What Done would commit — null until a date actually exists to commit.
  ///
  /// **This is the guard against a silently wrong birth date.** The wheel opens
  /// on today when the field is empty, so a `_picked` seeded from that opening
  /// position would let a member who taps Done without turning the wheel record
  /// TODAY as their date of birth — a wrong value nothing on screen states, so
  /// nobody would think to correct it. An untouched wheel has nothing to commit
  /// and Done is inert; Clear is how "no date" is said.
  late DateTime? _picked = widget.held;

  /// The FIRST turn of the wheel is the one that changes what the sheet can do
  /// (it releases Done), so only that one rebuilds — later ticks just move the
  /// value the live button already carries.
  void _pick(DateTime date) {
    if (_picked == null) {
      setState(() => _picked = date);
    } else {
      _picked = date;
    }
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            Text(
              'Date of birth',
              style: DesignConstants.kioskPanelTitle,
              textAlign: TextAlign.center,
            ),
            _Wheel(
              initial: widget.seed,
              maximum: widget.maximum,
              onChanged: _pick,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: DesignConstants.spacingLarge,
              children: [
                KioskOutlineButton(text: 'Clear', onPressed: widget.onClear),
                KioskPrimaryButton(
                  text: 'Done',
                  onPressed:
                      picked == null ? null : () => widget.onDone(picked),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The iOS-style date wheel, bounded to [kKioskDobMinDate] → [maximum].
class _Wheel extends StatelessWidget {
  final DateTime initial;
  final DateTime maximum;
  final ValueChanged<DateTime> onChanged;

  const _Wheel({
    required this.initial,
    required this.maximum,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesignConstants.kioskWheelHeight,
      child: CupertinoTheme(
        // The wheel draws its own text; hand it the kiosk value type so the
        // digits on the wheel match the digits in the box it fills.
        data: CupertinoThemeData(
          brightness:
              themeController.isDark ? Brightness.dark : Brightness.light,
          textTheme: CupertinoTextThemeData(
            dateTimePickerTextStyle: DesignConstants.kioskFieldText,
          ),
        ),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: initial,
          minimumDate: kKioskDobMinDate,
          maximumDate: maximum,
          onDateTimeChanged: (date) =>
              onChanged(DateTime(date.year, date.month, date.day)),
        ),
      ),
    );
  }
}
