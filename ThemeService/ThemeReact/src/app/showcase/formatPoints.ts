// The thousands separator every points surface in this island prints through.
//
// FOUR DART COPIES, ONE FUNCTION HERE. `points_showcase.dart:318`
// (`_formatThousands`), `rewards_card_showcase.dart:522` (`_formatPoints`),
// `rewards/points_headline.dart:22` (`_formatPoints`) and
// `rewards/reward_card.dart:183` (`formatRewardPoints`) are four byte-identical
// bodies — Dart's file-private `_` naming is what made each file carry its own.
// Nothing forces that here, so the port keeps one and every call site reads it
// (../../../CLAUDE.md: never reproduce an existing duplication to stay
// "consistent" with the code being ported).
//
// `Intl.NumberFormat` is NOT what this is. The Dart walks the digits itself and
// therefore always groups in threes with a comma, in every locale — a
// locale-aware formatter would print `3.400` for a German browser and silently
// diverge from the phone it is mirroring.

/**
 * Ports `_formatThousands` — `3400` → `'3,400'`. Anything under 1000 (negatives
 * included, exactly as the Dart's `n < 1000` guard has it) prints unchanged.
 */
export function formatThousands(value: number): string {
  if (value < 1000) return String(value);
  const digits = String(value);
  let out = '';
  for (let i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) out += ',';
    out += digits.charAt(i);
  }
  return out;
}
