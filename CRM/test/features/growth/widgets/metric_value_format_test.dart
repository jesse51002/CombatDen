import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/format/chart_scale.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/format/metric_value_format.dart';

void main() {
  group('formatMetricValue', () {
    test('count is a grouped number, keeping a fractional average', () {
      expect(formatMetricValue(1284, MetricUnit.count), '1,284');
      expect(formatMetricValue(3.2, MetricUnit.count), '3.2');
    });

    test('cents go through the money helper (integer minor units)', () {
      expect(formatMetricValue(914000, MetricUnit.cents), r'$9,140');
      expect(formatMetricValue(-1234, MetricUnit.cents), r'-$12');
    });

    test('percent arrives 0-100', () {
      expect(formatMetricValue(41, MetricUnit.percent), '41%');
      expect(formatMetricValue(12.44, MetricUnit.percent), '12.4%');
    });

    test('a non-finite value never prints as a number', () {
      expect(formatMetricValue(double.nan, MetricUnit.count), '—');
    });
  });

  group('formatAxisTick', () {
    test('counts stay exact below 10k, then compact', () {
      expect(formatAxisTick(9999, MetricUnit.count), '9,999');
      expect(formatAxisTick(12400, MetricUnit.count), '12.4k');
      expect(formatAxisTick(1200000, MetricUnit.count), '1.2M');
    });

    test('money stays exact below \$1,000, then compacts', () {
      expect(formatAxisTick(50000, MetricUnit.cents), r'$500');
      expect(formatAxisTick(910000, MetricUnit.cents), r'$9.1k');
    });
  });

  test('deltas carry their sign', () {
    expect(formatDeltaPct(11), '+11%');
    expect(formatDeltaPct(-20.5), '-20.5%');
    expect(formatDeltaAbs(14, MetricUnit.count), '+14');
  });

  group('niceCeiling', () {
    test('rounds up to 1 / 2 / 2.5 / 5 x 10^k', () {
      expect(niceCeiling(137), 200);
      expect(niceCeiling(41), 50);
      expect(niceCeiling(1.4), 2);
      expect(niceCeiling(0), 1);
    });
  });

  group('visibleLabelIndices', () {
    test('always keeps the first and last bucket', () {
      final indices = visibleLabelIndices(24, 200);
      expect(indices.contains(0), isTrue);
      expect(indices.contains(23), isTrue);
      expect(indices.length, lessThan(24));
    });

    test('keeps every label when they all fit', () {
      expect(visibleLabelIndices(3, 600).length, 3);
    });
  });
}
