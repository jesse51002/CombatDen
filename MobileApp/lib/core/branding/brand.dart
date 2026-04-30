import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';

enum Brand { combatDen, combatDenBjj }

extension BrandX on Brand {
  String get assetFolder => switch (this) {
    Brand.combatDen => 'assets/images',
    Brand.combatDenBjj => 'assets/images_bjj',
  };

  DesignConstants get constants => switch (this) {
    Brand.combatDen => DesignConstants.combatDen,
    Brand.combatDenBjj => DesignConstants.combatDenBjj,
  };

  String get displayName => switch (this) {
    Brand.combatDen => 'CombatDen',
    Brand.combatDenBjj => 'CombatDen BJJ',
  };

  Brand get toggled => switch (this) {
    Brand.combatDen => Brand.combatDenBjj,
    Brand.combatDenBjj => Brand.combatDen,
  };
}

class BrandScope extends InheritedNotifier<ValueNotifier<Brand>> {
  const BrandScope({
    super.key,
    required ValueNotifier<Brand> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static Brand of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<BrandScope>();
    assert(scope != null, 'No BrandScope found in widget tree');
    return scope!.notifier!.value;
  }

  static void toggle(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<BrandScope>();
    assert(scope != null, 'No BrandScope found in widget tree');
    final notifier = scope!.notifier!;
    notifier.value = notifier.value.toggled;
  }
}
