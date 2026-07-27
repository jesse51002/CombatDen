import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_location_helpers.dart';
import 'package:mobile_app/shared/widgets/buttons/app_outline_button.dart';
import 'package:mobile_app/shared/widgets/subtitle_section.dart';

/// "Location" header + the gym the class runs at: its name, its street address
/// when the gym has one, and a deep link into the phone's native map app.
/// (The member board carries no per-class address, so this is the gym's.)
class ClassLocationSection extends StatelessWidget {
  const ClassLocationSection({
    super.key,
    required this.gymName,
    this.address,
  });

  final String gymName;

  /// The gym's street address. Null/blank when the gym hasn't set one — the
  /// section then falls back to the name alone.
  final String? address;

  @override
  Widget build(BuildContext context) {
    final line = address?.trim();
    if (line == null || line.isEmpty) {
      return SubtitleSection(
        title: 'Location',
        spacing: DesignConstants.spacingMedium,
        child: Text(
          gymName,
          style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
        ),
      );
    }

    return SubtitleSection(
      title: 'Location',
      spacing: DesignConstants.spacingMedium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(gymName, style: DesignConstants.pBig),
              Text(
                line,
                style: DesignConstants.pBig.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
          _OpenInMapsButton(address: line),
        ],
      ),
    );
  }
}

class _OpenInMapsButton extends StatelessWidget {
  const _OpenInMapsButton({required this.address});

  final String address;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchMapsFor(address);
    if (opened) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text("Couldn't open Maps", style: DesignConstants.p),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open $address in Maps',
      child: AppOutlineButton(
        text: 'Open in Maps',
        borderColor: DesignConstants.primaryColor,
        textColor: DesignConstants.primaryColor,
        textStyle: DesignConstants.h3,
        icon: Icon(
          Symbols.directions_sharp,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeSm,
          color: DesignConstants.primaryColor,
        ),
        onPressed: () => _open(context),
      ),
    );
  }
}
