import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/schedule_generator.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/date_tab.dart';

// Estimated pitch (avg pill width + gap). Only used as a fallback when the
// target pill isn't currently built — once the pill is built we re-center
// exactly via Scrollable.ensureVisible.
const double _kDateTabPitchEstimate = 120;

const int _kDateTabCount = 365;

class DateRow extends StatefulWidget {
  const DateRow({
    super.key,
    required this.currentDayIndex,
    required this.scrollController,
    required this.onDateTap,
  });

  final int currentDayIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onDateTap;

  @override
  State<DateRow> createState() => _DateRowState();
}

class _DateRowState extends State<DateRow> {
  final Map<int, GlobalKey> _pillKeys = {};

  GlobalKey _keyFor(int index) =>
      _pillKeys.putIfAbsent(index, () => GlobalKey());

  @override
  void didUpdateWidget(DateRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentDayIndex != widget.currentDayIndex) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _centerOnSelected(allowRetry: true);
      });
    }
  }

  void _centerOnSelected({required bool allowRetry}) {
    final key = _pillKeys[widget.currentDayIndex];
    final ctx = key?.currentContext;
    if (ctx == null) {
      if (allowRetry) {
        _animateToEstimate();
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _centerOnSelected(allowRetry: false);
        });
      }
      return;
    }
    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    final pillBox = ctx.findRenderObject() as RenderBox?;
    final scrollable = Scrollable.maybeOf(ctx);
    final viewportBox = scrollable?.context.findRenderObject() as RenderBox?;
    if (pillBox == null || viewportBox == null) return;
    final pillLeft = pillBox
        .localToGlobal(Offset.zero, ancestor: viewportBox)
        .dx;
    final pillCenter = pillLeft + pillBox.size.width / 2;
    final delta = pillCenter - position.viewportDimension / 2;
    final target = (position.pixels + delta).clamp(
      0.0,
      position.maxScrollExtent,
    );
    widget.scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _animateToEstimate() {
    if (!widget.scrollController.hasClients) return;
    final viewportWidth = widget.scrollController.position.viewportDimension;
    final pillCenter =
        DesignConstants.paddingBig +
        widget.currentDayIndex * _kDateTabPitchEstimate +
        _kDateTabPitchEstimate / 2;
    final target = (pillCenter - viewportWidth / 2).clamp(
      0.0,
      widget.scrollController.position.maxScrollExtent,
    );
    widget.scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: DesignConstants.text3rd,
            width: DesignConstants.dividerThickness,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        top: DesignConstants.spacingSmall,
        bottom: DesignConstants.spacingTiny,
      ),
      child: ListView.separated(
        controller: widget.scrollController,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(
          left: DesignConstants.paddingBig,
          right: DesignConstants.spacingMedium,
        ),
        itemCount: _kDateTabCount,
        separatorBuilder: (_, _) =>
            SizedBox(width: DesignConstants.spacingBig),
        itemBuilder: (context, index) => DateTab(
          key: _keyFor(index),
          label: formatDayLabel(index),
          isSelected: index == widget.currentDayIndex,
          onTap: () => widget.onDateTap(index),
        ),
      ),
    );
  }
}
