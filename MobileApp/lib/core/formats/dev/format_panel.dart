import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/formats/format_catalog.dart';
import 'package:mobile_app/core/formats/format_resolver.dart';
import 'package:mobile_app/core/formats/format_store.dart';

/// Marks the chip a row is currently showing as live, so a test can read
/// back what the panel displays rather than infer it from a decoration.
Key selectedChipKey(String slot) => Key('format-selected-$slot');

/// The in-app DEV picker for layout and motion formats.
///
/// Opens as a drawer from the left edge of any screen, so a format can
/// be switched and judged in place. Debug builds only — see
/// [AppScreenScaffold], which is the only thing that attaches it.
class FormatPanel extends StatelessWidget {
  const FormatPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: DesignConstants.popup,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: FormatStore.instance,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _PanelHeader(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(
                    bottom: DesignConstants.spacingBig,
                  ),
                  children: [
                    const _GroupLabel('Layout'),
                    for (final entry in kLayoutFormats)
                      _FormatRow(entry: entry),
                    const _GroupLabel('Motion'),
                    for (final entry in kMotionFormats)
                      _FormatRow(entry: entry),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context) {
    final pinned = FormatStore.instance.active.length;
    return Padding(
      padding: EdgeInsets.all(DesignConstants.screenHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingSmall,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Formats', style: DesignConstants.h1),
              ),
              if (pinned > 0)
                TextButton(
                  onPressed: FormatStore.instance.reset,
                  child: Text('Reset', style: DesignConstants.h3),
                ),
            ],
          ),
          Text(
            pinned == 0
                ? 'Live values, resolved exactly as the app resolves '
                      'them. Each row says where its value came from.'
                : '$pinned pinned. A pin wins until the next theme '
                      'load, which releases all of them, and never '
                      'reaches a real tenant.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        DesignConstants.screenHorizontalPadding,
        DesignConstants.spacingLarge,
        DesignConstants.screenHorizontalPadding,
        DesignConstants.spacingMedium,
      ),
      child: Text(
        text.toUpperCase(),
        style: DesignConstants.h3.copyWith(color: DesignConstants.text3rd),
      ),
    );
  }
}

/// One format: its name, and a chip per value.
class _FormatRow extends StatelessWidget {
  const _FormatRow({required this.entry});

  final FormatEntry entry;

  @override
  Widget build(BuildContext context) {
    // Asked of the resolver, never re-derived here: this row used to
    // walk its own copy of the chain, and the copy was missing the
    // tenant step, so a themed slot drew the shipped value as selected.
    final source = FormatResolver.sourceOf(entry.slot);
    final effective = FormatResolver.resolve(entry.slot, entry.shipped);
    final pinned = source == FormatSource.pinned;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        DesignConstants.screenHorizontalPadding,
        DesignConstants.spacingSmall,
        DesignConstants.screenHorizontalPadding,
        DesignConstants.spacingMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingSmall,
        children: [
          Row(
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(entry.label, style: DesignConstants.h2),
              Text(
                source.label,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text3rd,
                ),
              ),
              if (!entry.implemented)
                Text(
                  'not wired yet',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text3rd,
                  ),
                ),
            ],
          ),
          Wrap(
            spacing: DesignConstants.spacingSmall,
            runSpacing: DesignConstants.spacingSmall,
            children: [
              for (final value in entry.values)
                _ValueChip(
                  // Keyed so a test can read back which value this row
                  // is actually showing as live, without inferring it
                  // from a decoration.
                  key: value == effective ? selectedChipKey(entry.slot) : null,
                  label: value,
                  selected: value == effective,
                  pinned: pinned && value == effective,
                  onTap: () => FormatStore.instance.set(
                    entry.slot,
                    value == effective && pinned ? null : value,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({
    super.key,
    required this.label,
    required this.selected,
    required this.pinned,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? DesignConstants.primaryButtonText
        : DesignConstants.text2nd;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingSmall,
        ),
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.primaryColor
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          border: Border.all(
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.divider,
            width: DesignConstants.dividerThickness,
          ),
        ),
        child: Text(
          pinned ? '$label  •' : label,
          style: DesignConstants.pSmall.copyWith(color: fg),
        ),
      ),
    );
  }
}
