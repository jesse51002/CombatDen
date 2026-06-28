import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/constants/design_constants.dart';

void main() {
  group('DesignConstants.onFill', () {
    // A label on a colored fill must contrast with THAT fill, regardless of
    // theme. okYellow flips brightness between themes (a dark amber in light
    // mode, a bright gold in dark mode), which is exactly why a single fixed
    // token can't stay legible on both — onFill picks the ink by luminance.
    test('light fill -> dark ink', () {
      // bright gold == okYellow in dark mode
      expect(
        DesignConstants.onFill(const Color(0xFFDBA13F)).computeLuminance(),
        lessThan(0.1),
      );
    });

    test('dark fill -> near-white ink', () {
      // saturated sapphire, and the dark-amber okYellow of light mode
      expect(
        DesignConstants.onFill(const Color(0xFF1B3A8A)).computeLuminance(),
        greaterThan(0.5),
      );
      expect(
        DesignConstants.onFill(const Color(0xFF915C08)).computeLuminance(),
        greaterThan(0.5),
      );
    });
  });
}
