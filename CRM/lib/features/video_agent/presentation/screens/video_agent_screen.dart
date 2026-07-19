import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/navigation/nav_pop.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/data/video_agent_repository.dart';
import 'package:crm/features/video_agent/bloc/video_agent_bloc.dart';
import 'package:crm/features/video_agent/bloc/video_agent_event.dart';
import 'package:crm/features/video_agent/bloc/video_agent_state.dart';
import 'package:crm/features/video_agent/presentation/widgets/video_agent_chat_list.dart';
import 'package:crm/features/video_agent/presentation/widgets/video_agent_input_bar.dart';
import 'package:crm/features/video_agent/presentation/widgets/video_agent_question_chips.dart';
import 'package:crm/features/video_agent/presentation/widgets/video_agent_spec_panel.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Page-scoped uniform text enlargement for the video-agent surface. Linear
/// scaling preserves every DesignConstants type ratio (hierarchy unchanged);
/// only the absolute floor moves (11px labels -> ~14px). One tunable number.
const double _kVideoAgentTextScale = 1.3;

/// Composes the page zoom ON TOP of the viewer's own accessibility text
/// scaling (multiply, not replace) so anyone who bumped OS/browser text size
/// keeps that gain.
class _ComposedTextScaler extends TextScaler {
  const _ComposedTextScaler(this._parent, this._factor);
  final TextScaler _parent;
  final double _factor;

  @override
  double scale(double fontSize) => _parent.scale(fontSize) * _factor;

  // Deprecated linear multiplier the SDK still requires a concrete override for;
  // real rendering goes through scale(). Compose the parent's factor like the
  // framework's own wrapping scalers do.
  @override
  double get textScaleFactor =>
      _parent.textScaleFactor * _factor; // ignore: deprecated_member_use

  @override
  bool operator ==(Object other) =>
      other is _ComposedTextScaler &&
      other._parent == _parent &&
      other._factor == _factor;

  @override
  int get hashCode => Object.hash(_parent, _factor);
}

/// Full-screen conversational surface for authoring the gym's video feed
/// spec. The owner chats with an LLM agent to produce criteria +
/// YouTube search queries; the agent proposes a draft the owner can review,
/// confirm, and save.
///
/// Entry: navigated to from the member-app preview's Videos tab (the Edit &
/// Focus card's "Start editing"). Backed by [VideoAgentBloc] (full
/// FastApiBackend path).
class VideoAgentScreen extends StatelessWidget {
  const VideoAgentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gymId = selectedGym.gymId ?? '';
    return RepositoryProvider<VideoAgentRepository>(
      create: (_) => VideoAgentRepository(ApiClient()),
      child: BlocProvider<VideoAgentBloc>(
        create: (ctx) => VideoAgentBloc(
          repository: ctx.read<VideoAgentRepository>(),
        )..add(VideoAgentScreenOpened(gymId)),
        child: AppShell(
          activeRoute: AppRoutes.memberAppPreview,
          child: _VideoAgentBody(gymId: gymId),
        ),
      ),
    );
  }
}

class _VideoAgentBody extends StatelessWidget {
  final String gymId;

  const _VideoAgentBody({required this.gymId});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler:
            _ComposedTextScaler(media.textScaler, _kVideoAgentTextScale),
      ),
      child: BlocBuilder<VideoAgentBloc, VideoAgentState>(
        builder: (ctx, state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(loadStatus: state.loadStatus),
            Expanded(child: _Content(state: state)),
          ],
        ),
      ),
    );
  }
}

/// Fixed top bar: back button, title, and a brief "Improving…" hint when
/// refining is in progress.
class _TopBar extends StatelessWidget {
  final VideoAgentLoadStatus loadStatus;

  const _TopBar({required this.loadStatus});

  @override
  Widget build(BuildContext context) {
    final isRefining = loadStatus == VideoAgentLoadStatus.refining;
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
            onPressed: () =>
                popOrGoTo(context, AppRoutes.memberAppPreviewVideos),
            tooltip: 'Back',
          ),
          Expanded(
            child: Text(
              'Video feed spec',
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
  final VideoAgentState state;

  const _Content({required this.state});

  @override
  Widget build(BuildContext context) {
    switch (state.loadStatus) {
      case VideoAgentLoadStatus.initial:
      case VideoAgentLoadStatus.refining:
      case VideoAgentLoadStatus.loading:
        return const Center(child: AppSpinner());

      case VideoAgentLoadStatus.error:
        return Padding(
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingMedium,
              children: [
                ErrorMessage(
                  message: state.error ?? 'Failed to load spec.',
                ),
                TextButton(
                  onPressed: () => context.read<VideoAgentBloc>().add(
                    VideoAgentScreenOpened(selectedGym.gymId ?? ''),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );

      case VideoAgentLoadStatus.empty:
      case VideoAgentLoadStatus.loaded:
        return _ChatLayout(state: state);
    }
  }
}

/// The loaded layout: chat column on the left + the spec panel on the right
/// (the pending proposal, highlighted, when there is one — otherwise the
/// current saved spec).
class _ChatLayout extends StatelessWidget {
  final VideoAgentState state;

  const _ChatLayout({required this.state});

  @override
  Widget build(BuildContext context) {
    final hasDraft = state.pendingDraft != null;
    final hasConfig = state.savedConfig != null;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: SelectionArea(child: _ChatColumn(state: state))),
          // Right column: a pending proposal takes the slot (highlighted),
          // otherwise the current saved spec — same panel, two modes.
          if (hasDraft || hasConfig) ...[
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.spacingLarge,
              ),
              child: Hairline(vertical: true),
            ),
            // Its own SelectionArea (separate from the chat's) so a drag in the
            // spec pane can't extend into the chat and vice-versa.
            Expanded(
              child: SelectionArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: DesignConstants.spacingLarge,
                  ),
                  child: hasDraft
                      ? VideoAgentSpecPanel(
                          disciplines: state.pendingDraft!.disciplines,
                          videosDesc: state.pendingDraft!.videosDesc,
                          avoidDesc: state.pendingDraft!.avoidDesc,
                          mode: VideoSpecPanelMode.proposed,
                          footer: _ProposedActions(
                            saveStatus: state.saveStatus,
                          ),
                        )
                      : VideoAgentSpecPanel(
                          disciplines: state.savedConfig!.disciplines,
                          videosDesc: state.savedConfig!.videosDesc,
                          avoidDesc: state.savedConfig!.avoidDesc,
                          // Green success glow right after an Accept, held until
                          // the owner's next message resets the save status.
                          mode:
                              state.saveStatus == VideoAgentSaveStatus.saved
                              ? VideoSpecPanelMode.saved
                              : VideoSpecPanelMode.current,
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The chat column: message list + optional question chips + input bar.
/// (A proposed draft renders in the right-hand spec panel, not here.)
class _ChatColumn extends StatelessWidget {
  final VideoAgentState state;

  const _ChatColumn({required this.state});

  @override
  Widget build(BuildContext context) {
    final isInputEnabled =
        state.chatStatus == VideoAgentChatStatus.idle &&
        state.saveStatus != VideoAgentSaveStatus.saving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: VideoAgentChatList(
            messages: state.messages,
            chatStatus: state.chatStatus,
          ),
        ),
        if (state.pendingQuestion != null)
          Padding(
            padding: const EdgeInsets.only(
              top: DesignConstants.spacingMedium,
            ),
            child: VideoAgentQuestionChips(
              question: state.pendingQuestion!,
            ),
          ),
        // Outcomes (saved / dismissed / error) are recorded in the chat as
        // outcome cards — no out-of-chat banners here.
        Padding(
          padding: const EdgeInsets.only(
            top: DesignConstants.spacingMedium,
            bottom: DesignConstants.spacingLarge,
          ),
          child: VideoAgentInputBar(
            enabled: isInputEnabled,
            onSend: (text) => context.read<VideoAgentBloc>().add(
              VideoAgentMessageSent(text),
            ),
          ),
        ),
      ],
    );
  }
}

/// Footer of the highlighted proposed panel. **Accept** saves the draft;
/// **Tell us what to change** dismisses it so the owner can keep refining in
/// the chat (the agent re-proposes a revised draft on the next turn).
class _ProposedActions extends StatelessWidget {
  final VideoAgentSaveStatus saveStatus;

  const _ProposedActions({required this.saveStatus});

  @override
  Widget build(BuildContext context) {
    final isSaving = saveStatus == VideoAgentSaveStatus.saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingSmall,
      children: [
        AppPrimaryButton(
          text: 'Accept',
          fullWidth: true,
          isLoading: isSaving,
          onPressed: isSaving
              ? null
              : () => context
                    .read<VideoAgentBloc>()
                    .add(const VideoAgentDraftConfirmed()),
        ),
        AppOutlineButton(
          text: 'Tell us what to change',
          fullWidth: true,
          onPressed: isSaving
              ? null
              : () => context
                    .read<VideoAgentBloc>()
                    .add(const VideoAgentDraftDismissed()),
        ),
      ],
    );
  }
}
