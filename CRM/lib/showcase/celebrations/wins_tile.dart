import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:crm/showcase/celebrations/showcase_celebration_stats.dart';
import 'package:crm/showcase/showcase_tokens.dart';
import 'package:crm/showcase/support/count_up_text.dart';
import 'package:crm/showcase/support/staggered_reveal.dart';

/// Clone of MobileApp's `WinsTile`: bordered info-tile shown in the Wins grid
/// — icon + value + caption. If [tile.value] parses as a clean integer
/// (e.g. "+50", "+160"), the value rolls in as a count-up; otherwise it
/// renders as static text. The whole tile cascades in via [StaggeredReveal]
/// after [delay].
class WinsTile extends StatelessWidget {
  const WinsTile({
    super.key,
    required this.tile,
    this.delay = Duration.zero,
  });

  final ShowcaseWinTile tile;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final numeric = _parseNumeric(tile.value);

    return StaggeredReveal(
      delay: delay,
      child: Container(
        padding: const EdgeInsets.all(ShowcaseTokens.paddingSmall),
        decoration: BoxDecoration(
          border: Border.all(
            color: ShowcaseTokens.text,
            width: ShowcaseTokens.buttonBorder,
          ),
          borderRadius: BorderRadius.circular(ShowcaseTokens.radiusSmall),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: ShowcaseTokens.spacingMedium,
          children: [
            Icon(
              _iconFor(tile.iconName),
              weight: ShowcaseTokens.iconWeight,
              color: ShowcaseTokens.text,
              size: ShowcaseTokens.iconSizeXl,
            ),
            if (numeric != null)
              CountUpText(
                target: numeric.value,
                delay: delay,
                prefix: numeric.prefix,
                style: ShowcaseTokens.h3,
                textAlign: TextAlign.center,
              )
            else
              Text(
                tile.value,
                textAlign: TextAlign.center,
                style: ShowcaseTokens.h3,
              ),
            Text(
              tile.label,
              textAlign: TextAlign.center,
              style: ShowcaseTokens.p.copyWith(
                color: ShowcaseTokens.text2nd,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String iconName) {
    switch (iconName) {
      case 'star':
        return Symbols.star_sharp;
      case 'award':
        return Symbols.workspace_premium_sharp;
      case 'gift':
        return Symbols.redeem_sharp;
      default:
        return Symbols.help_sharp;
    }
  }
}

class _NumericValue {
  const _NumericValue({required this.prefix, required this.value});

  final String prefix;
  final int value;
}

/// Parses values like `"+50"`, `"160"`, `"-3"` into a (prefix, integer) pair.
/// Returns null for strings the count-up shouldn't touch (`"3 week"`, etc.).
_NumericValue? _parseNumeric(String raw) {
  final match = RegExp(r'^([+-]?)(\d+)$').firstMatch(raw.trim());
  if (match == null) return null;
  final value = int.tryParse(match.group(2)!);
  if (value == null) return null;
  return _NumericValue(prefix: match.group(1) ?? '', value: value);
}
