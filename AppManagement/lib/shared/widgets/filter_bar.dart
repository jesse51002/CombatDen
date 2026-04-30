import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/shared/widgets/active_filter_chip.dart';

/// A filter description displayed as a chip in the
/// filter bar.
class ActiveFilter {
  final String label;
  final String type;
  final dynamic value;

  const ActiveFilter({
    required this.label,
    required this.type,
    this.value,
  });
}

/// A bar with an "Add Filter +" button and active
/// filter chips.
///
/// Wraps to multiple lines when many filters are active.
class FilterBar extends StatelessWidget {
  final List<ActiveFilter> filters;
  final VoidCallback onAddFilter;
  final void Function(int index) onRemoveFilter;

  const FilterBar({
    super.key,
    required this.filters,
    required this.onAddFilter,
    required this.onRemoveFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.spacingMedium,
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: DesignConstants.spacingMedium,
        runSpacing: DesignConstants.spacingMedium,
        children: [
          Semantics(
            label: 'Add filter',
            button: true,
            child: InkWell(
              onTap: onAddFilter,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusBig,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal:
                      DesignConstants.paddingSmall,
                  vertical:
                      DesignConstants.spacingMedium,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    DesignConstants.radiusBig,
                  ),
                  border: Border.all(
                    color:
                        DesignConstants.text,
                    width: DesignConstants.buttonBorderSize
                  ),
                ),
                child: Text(
                  'Add Filter +',
                  style:
                      DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ),
            ),
          ),
          ...List.generate(filters.length, (index) {
            return ActiveFilterChip(
              label: filters[index].label,
              onRemoved: () => onRemoveFilter(index),
            );
          }),
        ],
      ),
    );
  }
}
