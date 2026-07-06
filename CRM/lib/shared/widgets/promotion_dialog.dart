import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/promotion_choice.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';

/// Bloc-agnostic rank-change picker. Returns a [PromotionChoice] (or
/// null on cancel) via `Navigator.pop`; the caller maps the result onto
/// its own bloc event, so the SAME dialog serves member-detail,
/// rank-detail, and the ready-to-promote board.
///
/// Three ways out:
///  - **Next sub-rank** — advance one leaf within the current belt
///    ([PromoteNextSub]). Offered only when the current belt has a
///    higher stripe/division left to earn.
///  - **Next major rank** — skip to the base of the next belt
///    ([PromoteNextMajor]). Offered while a higher belt exists (and,
///    for an unranked member, this assigns the lowest belt).
///  - **Choose a rank** — drill into a belt picker, then a sub-position
///    picker, landing on an explicit [PromoteExplicit] (correct, demote,
///    assign, or unassign).
class PromotionDialog extends StatefulWidget {
  final List<MainRank> ladder;
  final RankSubType subRankType;

  /// The member's current MAIN rank id, or null when unranked.
  final String? currentMainRankId;

  /// The member's current leaf within that rank, or null when the rank
  /// has no sub-ranks (or when unranked).
  final int? currentSubIndex;

  const PromotionDialog({
    super.key,
    required this.ladder,
    required this.subRankType,
    required this.currentMainRankId,
    required this.currentSubIndex,
  });

  static Future<PromotionChoice?> show({
    required BuildContext context,
    required List<MainRank> ladder,
    required RankSubType subRankType,
    required String? currentMainRankId,
    required int? currentSubIndex,
  }) {
    return showDialog<PromotionChoice>(
      context: context,
      builder: (_) => PromotionDialog(
        ladder: ladder,
        subRankType: subRankType,
        currentMainRankId: currentMainRankId,
        currentSubIndex: currentSubIndex,
      ),
    );
  }

  @override
  State<PromotionDialog> createState() => _PromotionDialogState();
}

enum _Step { menu, pickMain, pickSub }

class _PromotionDialogState extends State<PromotionDialog> {
  _Step _step = _Step.menu;

  /// The belt chosen in the pick-main step, awaiting a sub-position.
  MainRank? _pickedMain;

  bool get _isAssign => widget.currentMainRankId == null;

  MainRank? get _currentMain {
    for (final r in widget.ladder) {
      if (r.rankId == widget.currentMainRankId) return r;
    }
    return null;
  }

  /// The next belt above the current one, or null at the top. Mirrors
  /// `RanksRepository.applyPromotion`'s own resolution so the enabled
  /// state matches what the backend will actually do.
  MainRank? get _nextMajor {
    if (widget.ladder.isEmpty) return null;
    if (widget.currentMainRankId == null) return widget.ladder.first;
    final index = widget.ladder
        .indexWhere((r) => r.rankId == widget.currentMainRankId);
    if (index < 0) return widget.ladder.first;
    if (index >= widget.ladder.length - 1) return null;
    return widget.ladder[index + 1];
  }

  bool get _nextSubEnabled {
    final main = _currentMain;
    final sub = widget.currentSubIndex;
    return main != null &&
        main.subRankCount > 0 &&
        sub != null &&
        sub < main.subRankCount - 1;
  }

  /// "Blue" or "Blue · 2 Stripes" for leaf [index] of [rank].
  String _leafLabel(MainRank rank, int? index) {
    if (index == null) return rank.name;
    final label = widget.subRankType.subLabel(index);
    return label.isEmpty ? rank.name : '${rank.name} · $label';
  }

  void _pop(PromotionChoice choice) => Navigator.of(context).pop(choice);

  void _onMainPicked(MainRank rank) {
    if (rank.subRankCount > 0) {
      setState(() {
        _pickedMain = rank;
        _step = _Step.pickSub;
      });
    } else {
      _pop(PromoteExplicit(mainRankId: rank.rankId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: switch (_step) {
        _Step.menu => _isAssign ? 'Assign rank' : 'Promote member',
        _Step.pickMain => 'Choose a rank',
        _Step.pickSub => _pickedMain?.name ?? 'Choose a position',
      },
      body: switch (_step) {
        _Step.menu => _menu(),
        _Step.pickMain => _pickMain(),
        _Step.pickSub => _pickSub(),
      },
      actions: _actions(),
    );
  }

  // ----- Menu -----

  Widget _menu() {
    final next = _nextMajor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (!_isAssign)
          _OptionTile(
            imageUrl: _nextSubEnabled
                ? _currentMain!.imageForSub(widget.currentSubIndex! + 1)
                : null,
            title: 'Next sub-rank',
            subtitle: _nextSubEnabled
                ? _leafLabel(_currentMain!, widget.currentSubIndex! + 1)
                : 'No more stripes on this belt',
            enabled: _nextSubEnabled,
            onTap: () => _pop(const PromoteNextSub()),
          ),
        _OptionTile(
          imageUrl: next?.imageForSub(0),
          title: _isAssign ? 'Assign lowest rank' : 'Next major rank',
          subtitle: next == null
              ? 'Already at the top belt'
              : _isAssign
                  ? _leafLabel(next, next.subRankCount > 0 ? 0 : null)
                  : 'Skip to ${_leafLabel(next, next.subRankCount > 0 ? 0 : null)}',
          enabled: next != null,
          onTap: () => _pop(const PromoteNextMajor()),
        ),
        _OptionTile(
          icon: Symbols.tune_sharp,
          title: 'Choose a rank',
          subtitle: 'Assign, correct, or demote to any belt',
          enabled: widget.ladder.isNotEmpty,
          onTap: () => setState(() => _step = _Step.pickMain),
        ),
      ],
    );
  }

  // ----- Pick a belt -----

  Widget _pickMain() {
    return _PickerList(
      children: [
        if (!_isAssign)
          _PickRow(
            icon: Symbols.block_sharp,
            label: 'No rank',
            caption: 'Remove this member from the ladder',
            onTap: () => _pop(const PromoteExplicit()),
          ),
        for (final rank in widget.ladder)
          _PickRow(
            imageUrl: rank.imageForSub(0),
            label: rank.name,
            caption: _beltCaption(rank),
            selected: rank.rankId == widget.currentMainRankId,
            trailing: rank.subRankCount > 0
                ? Icon(
                    Symbols.chevron_right_sharp,
                    size: DesignConstants.iconSizeMedium,
                    color: DesignConstants.text3rd,
                    weight: DesignConstants.iconWeight,
                  )
                : null,
            onTap: () => _onMainPicked(rank),
          ),
      ],
    );
  }

  String _beltCaption(MainRank rank) {
    if (rank.subRankCount == 0) return 'No sub-ranks';
    final unit = widget.subRankType == RankSubType.div
        ? (rank.subRankCount == 1 ? 'division' : 'divisions')
        : (rank.subRankCount == 1 ? 'position' : 'positions');
    return '${rank.subRankCount} $unit';
  }

  // ----- Pick a sub-position -----

  Widget _pickSub() {
    final rank = _pickedMain!;
    return _PickerList(
      children: [
        for (var i = 0; i < rank.subRankCount; i++)
          _PickRow(
            imageUrl: rank.imageForSub(i),
            label: _subRowLabel(rank, i),
            selected: rank.rankId == widget.currentMainRankId &&
                i == widget.currentSubIndex,
            onTap: () =>
                _pop(PromoteExplicit(mainRankId: rank.rankId, subIndex: i)),
          ),
      ],
    );
  }

  String _subRowLabel(MainRank rank, int index) {
    final label = widget.subRankType.subLabel(index);
    return label.isEmpty ? '${rank.name} (base)' : label;
  }

  // ----- Footer -----

  Widget _actions() {
    return Row(
      children: [
        if (_step != _Step.menu)
          AppOutlineButton(
            text: 'Back',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: () => setState(() {
              _step = _step == _Step.pickSub ? _Step.pickMain : _Step.menu;
            }),
          ),
        const Spacer(),
        AppOutlineButton(
          text: 'Cancel',
          borderRadius: DesignConstants.radiusSmall,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// One of the three menu choices — a belt (or glyph) + title + caption,
/// tappable when [enabled].
class _OptionTile extends StatelessWidget {
  final String? imageUrl;
  final IconData? icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.imageUrl,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final leading = icon != null
        ? Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: DesignConstants.backgroundAlt,
              borderRadius:
                  BorderRadius.circular(DesignConstants.radiusSmall),
              border: Border.all(color: DesignConstants.line),
            ),
            child: Icon(
              icon,
              size: DesignConstants.iconSizeMedium,
              color: DesignConstants.text2nd,
              weight: DesignConstants.iconWeight,
            ),
          )
        : RankBeltImage(imageUrl: imageUrl, size: 44);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          child: Padding(
            padding: const EdgeInsets.all(DesignConstants.spacingMedium),
            child: Row(
              spacing: DesignConstants.spacingMedium,
              children: [
                leading,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: DesignConstants.spacingTiny,
                    children: [
                      Text(title, style: DesignConstants.pSemibold),
                      Text(
                        subtitle,
                        style: DesignConstants.pSmall.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                      ),
                    ],
                  ),
                ),
                if (enabled && icon == null)
                  Icon(
                    Symbols.arrow_forward_sharp,
                    size: DesignConstants.iconSizeSmall,
                    color: DesignConstants.text3rd,
                    weight: DesignConstants.iconWeight,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A height-bounded, scrolling column for the belt / sub-position
/// pickers, so a long ladder never grows the dialog unbounded.
class _PickerList extends StatelessWidget {
  final List<Widget> children;

  const _PickerList({required this.children});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingTiny,
          children: children,
        ),
      ),
    );
  }
}

/// One row in a picker: belt art (or glyph) + label + optional caption,
/// with a check when it is the member's current position.
class _PickRow extends StatelessWidget {
  final String? imageUrl;
  final IconData? icon;
  final String label;
  final String? caption;
  final bool selected;
  final Widget? trailing;
  final VoidCallback onTap;

  const _PickRow({
    required this.label,
    required this.onTap,
    this.imageUrl,
    this.icon,
    this.caption,
    this.selected = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final leading = icon != null
        ? Icon(
            icon,
            size: DesignConstants.iconSizeLarge,
            color: DesignConstants.text3rd,
            weight: DesignConstants.iconWeight,
          )
        : RankBeltImage(imageUrl: imageUrl, size: 36);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.spacingMedium),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            SizedBox(width: 36, child: Center(child: leading)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(label, style: DesignConstants.p),
                  if (caption != null)
                    Text(
                      caption!,
                      style: DesignConstants.pSmall.copyWith(
                        color: DesignConstants.text3rd,
                      ),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Symbols.check_circle_sharp,
                size: DesignConstants.iconSizeMedium,
                color: DesignConstants.primaryColor,
                weight: DesignConstants.iconWeight,
              )
            else
              ?trailing,
          ],
        ),
      ),
    );
  }
}
