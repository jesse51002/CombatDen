import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/data/mock_class_detail.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_attending_row.dart';

/// The `specBrief` treatment of the class meta: the title beside an
/// inline photo thumb, then the same facts as a dense label/value
/// table.
///
/// Same data as the stacked block — location, date, time, attending —
/// read as a table instead of a paragraph stack. [leading] is a
/// presentation slot the layout fills with the photo; nothing else is
/// ever passed to it.
class ClassMetaSpecTable extends StatelessWidget {
  const ClassMetaSpecTable({super.key, required this.detail, this.leading});

  final MockClassDetail detail;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final cls = detail.classData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingMedium,
          children: [
            ?leading,
            Expanded(child: Text(cls.name, style: DesignConstants.h1)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingSmall,
          children: [
            _SpecRow(label: 'Location', child: _SpecValue(detail.location)),
            _SpecRow(label: 'Date', child: _SpecValue(detail.dateLabel)),
            _SpecRow(label: 'Time', child: _SpecValue(cls.timeRange)),
            if (cls.attending != null)
              _SpecRow(
                label: 'Attending',
                child: ClassAttendingRow(count: cls.attending!),
              ),
          ],
        ),
      ],
    );
  }
}

/// The label column is fixed so the values line up into a column of
/// their own — that alignment is the whole point of the treatment.
const double _kLabelWidth = 96;

class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        SizedBox(
          width: _kLabelWidth,
          child: Text(
            label,
            style: DesignConstants.p.copyWith(color: DesignConstants.text3rd),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _SpecValue extends StatelessWidget {
  const _SpecValue(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
    );
  }
}
