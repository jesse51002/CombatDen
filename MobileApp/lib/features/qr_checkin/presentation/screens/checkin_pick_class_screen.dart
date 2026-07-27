import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/home/data/repositories/member_classes_repository.dart';
import 'package:mobile_app/features/qr_checkin/bloc/checkin_pick_class_bloc.dart';
import 'package:mobile_app/features/qr_checkin/bloc/checkin_pick_class_event.dart';
import 'package:mobile_app/features/qr_checkin/presentation/widgets/pick_class/pick_class_body.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Step 2 of the QR check-in flow: pick which of today's classes you're
/// checking into. Provides the [CheckinPickClassBloc] (reusing the home
/// board read) and dispatches the initial load.
class CheckinPickClassScreen extends StatelessWidget {
  const CheckinPickClassScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CheckinPickClassBloc>(
      create: (_) => CheckinPickClassBloc(
        classesRepository: MemberClassesRepository(apiClient: ApiClient()),
      )..add(const CheckinPickClassLoadRequested()),
      child: const AppScreenScaffold(
        horizontalPadding: AppScreenHorizontalPadding.none,
        child: PickClassBody(),
      ),
    );
  }
}
