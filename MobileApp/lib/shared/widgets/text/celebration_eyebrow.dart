import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The celebration screens' small-cap eyebrow line — `pSmall` at `w700` in
/// `text2nd`, tracked out to `0.24 × fontSize`, centred.
///
/// One implementation, shared: it is `SparkleHero`'s top/bottom label recipe
/// and the promotion card's headline. Both are the same typographic object (a
/// quiet label above a loud hero), so they must not drift into two.
///
/// The caller supplies the string already upper-cased — this widget sets the
/// tracking that makes caps legible, not the casing itself, so a themed slot
/// value can be rendered verbatim.
class CelebrationEyebrow extends StatelessWidget {
  const CelebrationEyebrow({super.key, required this.text});

  final String text;

  /// The recipe on its own, for a caller that needs the [TextStyle] rather
  /// than the widget.
  static TextStyle get style => DesignConstants.pSmall.copyWith(
        color: DesignConstants.text2nd,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.24 * (DesignConstants.pSmall.fontSize ?? 11),
      );

  @override
  Widget build(BuildContext context) {
    return Text(text, style: style, textAlign: TextAlign.center);
  }
}
