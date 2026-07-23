import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_type.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/memberships/bloc/discounts/discounts_bloc.dart';
import 'package:crm/features/memberships/bloc/discounts/discounts_event.dart';
import 'package:crm/features/memberships/bloc/discounts/discounts_state.dart';
import 'package:crm/features/memberships/presentation/tabs/discounts_tab.dart';

class _MockDiscountsBloc extends MockBloc<DiscountsEvent, DiscountsState>
    implements DiscountsBloc {}

/// Role-affordance gating for a catalog tab: front desk gets a READ-ONLY
/// Gym catalog, so the write affordances (the "Add New …" row and the
/// per-row "Edit" button) disappear while the table stays fully viewable.
/// Owner keeps both. Exercises the real [DiscountsTab] over a mocked bloc.
void main() {
  final discount = DiscountResponse(
    discountId: 'disc-1',
    gymId: 'gym-1',
    discountName: 'Family plan',
    discountType: DiscountType.preset,
    valueId: 'val-1',
    value: const DiscountValue(percentageOff: 20),
    createdAt: DateTime(2026, 1, 1),
  );

  late _MockDiscountsBloc bloc;

  setUp(() {
    bloc = _MockDiscountsBloc();
    whenListen(
      bloc,
      const Stream<DiscountsState>.empty(),
      initialState: DiscountsLoaded(gymId: 'gym-1', discounts: [discount]),
    );
  });

  tearDown(() => selectedGym.reset());

  void activate(EmployeeRole role) {
    selectedGym.setActiveGym(
      gymId: 'gym-1',
      displayName: 'Test Gym',
      role: role,
      timezone: 'America/Chicago',
      logoUrl: null,
    );
  }

  Widget harness() {
    return MaterialApp(
      // The M3 ink splash shader fails to decode in this test SDK; disable it.
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: BlocProvider<DiscountsBloc>.value(
          value: bloc,
          child: const DiscountsTab(),
        ),
      ),
    );
  }

  testWidgets(
    'front desk: the Add row and the per-row Edit button are hidden; the '
    'discount itself still renders',
    (tester) async {
      activate(EmployeeRole.frontDesk);
      await tester.pumpWidget(harness());

      expect(find.text('Add New Discount +'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      // The catalog stays viewable — the row's data is still on screen.
      expect(find.text('Family plan'), findsOneWidget);
    },
  );

  testWidgets(
    'owner: the Add row and the per-row Edit button are both shown',
    (tester) async {
      activate(EmployeeRole.owner);
      await tester.pumpWidget(harness());

      expect(find.text('Add New Discount +'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Family plan'), findsOneWidget);
    },
  );
}
