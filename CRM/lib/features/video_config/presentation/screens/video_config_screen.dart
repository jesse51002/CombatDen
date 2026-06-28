import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/data/video_config_repository.dart';
import 'package:crm/features/video_config/bloc/video_config_bloc.dart';
import 'package:crm/features/video_config/bloc/video_config_event.dart';
import 'package:crm/features/video_config/bloc/video_config_state.dart';
import 'package:crm/features/video_config/presentation/widgets/video_config_chat_list.dart';
import 'package:crm/features/video_config/presentation/widgets/video_config_current_panel.dart';
import 'package:crm/features/video_config/presentation/widgets/video_config_draft_panel.dart';
import 'package:crm/features/video_config/presentation/widgets/video_config_input_bar.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Full-screen conversational surface for authoring the gym's video feed
/// configuration. The owner chats with an LLM agent to produce criteria +
/// YouTube search queries; the agent proposes a draft the owner can review,
/// confirm, and save.
///
/// Entry: navigated to from the Settings screen's Video Config section.
/// Backed by [VideoConfigBloc] (full FastApiBackend path).
class VideoConfigScreen extends StatelessWidget {
  const VideoConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gymId = selectedGym.gymId ?? '';
    return RepositoryProvider<VideoConfigRepository>(
      create: (_) => VideoConfigRepository(ApiClient()),
      child: BlocProvider<VideoConfigBloc>(
        create: (ctx) => VideoConfigBloc(
          repository: ctx.read<VideoConfigRepository>(),
        )..add(VideoConfigScreenOpened(gymId)),
        child: AppShell(
          activeRoute: AppRoutes.settings,
          child: _VideoConfigBody(gymId: gymId),
        ),
      ),
    );
  }
}

class _VideoConfigBody extends StatelessWidget {
  final String gymId;

  const _VideoConfigBody({required this.gymId});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VideoConfigBloc, VideoConfigState>(
      // Show the success SnackBar once save completes.
      listenWhen: (prev, curr) =>
          prev.saveStatus != VideoConfigSaveStatus.saved &&
          curr.saveStatus == VideoConfigSaveStatus.saved,
      listener: (ctx, _) {
        ScaffoldMessenger.of(ctx)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Video config saved.'),
            ),
          );
      },
      builder: (ctx, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopBar(loadStatus: state.loadStatus),
          Expanded(child: _Content(state: state)),
        ],
      ),
    );
  }
}

/// Fixed top bar: back button, title, and a brief "Improving…" hint when
/// refining is in progress.
class _TopBar extends StatelessWidget {
  final VideoConfigLoadStatus loadStatus;

  const _TopBar({required this.loadStatus});

  @override
  Widget build(BuildContext context) {
    final isRefining = loadStatus == VideoConfigLoadStatus.refining;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignConstants.paddingBig,
        DesignConstants.paddingBig,
        DesignConstants.paddingBig,
        0,
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          IconButton(
            icon: Icon(
              Symbols.arrow_back_sharp,
              size: DesignConstants.iconSizeMedium,
              weight: DesignConstants.iconWeight,
            ),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back to Settings',
          ),
          Expanded(
            child: Text(
              'Video feed config',
              style: DesignConstants.h1,
            ),
          ),
          if (isRefining) ...[
            const AppSpinner(),
            Text(
              'Improving from your recent edits…',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The main scrollable + fixed content area below the top bar.
class _Content extends StatelessWidget {
  final VideoConfigState state;

  const _Content({required this.state});

  @override
  Widget build(BuildContext context) {
    switch (state.loadStatus) {
      case VideoConfigLoadStatus.initial:
      case VideoConfigLoadStatus.refining:
      case VideoConfigLoadStatus.loading:
        return const Center(child: AppSpinner());

      case VideoConfigLoadStatus.error:
        return Padding(
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingMedium,
              children: [
                ErrorMessage(
                  message: state.error ?? 'Failed to load config.',
                ),
                TextButton(
                  onPressed: () => context.read<VideoConfigBloc>().add(
                    VideoConfigScreenOpened(selectedGym.gymId ?? ''),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );

      case VideoConfigLoadStatus.empty:
      case VideoConfigLoadStatus.loaded:
        return _ChatLayout(state: state);
    }
  }
}

/// The loaded layout: optional current-config panel + chat column.
class _ChatLayout extends StatelessWidget {
  final VideoConfigState state;

  const _ChatLayout({required this.state});

  @override
  Widget build(BuildContext context) {
    final hasConfig = state.savedConfig != null;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          if (hasConfig)
            Padding(
              padding: const EdgeInsets.only(
                top: DesignConstants.spacingLarge,
              ),
              child: VideoConfigCurrentPanel(config: state.savedConfig!),
            ),
          Expanded(
            child: _ChatColumn(state: state),
          ),
        ],
      ),
    );
  }
}

/// The chat column: message list + optional draft panel + input bar.
class _ChatColumn extends StatelessWidget {
  final VideoConfigState state;

  const _ChatColumn({required this.state});

  @override
  Widget build(BuildContext context) {
    final isInputEnabled =
        state.chatStatus == VideoConfigChatStatus.idle &&
        state.saveStatus != VideoConfigSaveStatus.saving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: VideoConfigChatList(
            messages: state.messages,
            chatStatus: state.chatStatus,
          ),
        ),
        if (state.pendingDraft != null)
          Padding(
            padding: const EdgeInsets.only(
              top: DesignConstants.spacingMedium,
            ),
            child: VideoConfigDraftPanel(
              draft: state.pendingDraft!,
              saveStatus: state.saveStatus,
              error: state.saveStatus == VideoConfigSaveStatus.error
                  ? state.error
                  : null,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(
            top: DesignConstants.spacingMedium,
            bottom: DesignConstants.spacingLarge,
          ),
          child: VideoConfigInputBar(
            enabled: isInputEnabled,
            onSend: (text) => context.read<VideoConfigBloc>().add(
              VideoConfigMessageSent(text),
            ),
          ),
        ),
      ],
    );
  }
}
