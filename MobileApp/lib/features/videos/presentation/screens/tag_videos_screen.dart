import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/videos/bloc/videos_bloc.dart';
import 'package:mobile_app/features/videos/bloc/videos_event.dart';
import 'package:mobile_app/features/videos/bloc/videos_state.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';
import 'package:mobile_app/features/videos/data/repositories/member_videos_repository.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/creator_avatar.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_card.dart';

/// The "view all" destination for a genre carousel: a scrollable vertical list
/// of every video for one [VideoGenre], loaded from the portal via a
/// single-genre [VideosBloc]. Reached via `AppRoutes.videoTagList` with the
/// [VideoGenre] as the route argument.
class TagVideosScreen extends StatelessWidget {
  const TagVideosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final arg = ModalRoute.of(context)?.settings.arguments;
    final genre = arg is VideoGenre
        ? arg
        : (arg is String ? videoGenreOrNullFromJson(arg) : null);

    return AppScreenScaffold(
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.videos),
      child: genre == null || genre == VideoGenre.unknown
          ? const _Missing()
          : BlocProvider<VideosBloc>(
              create: (_) => VideosBloc(
                repository: MemberVideosRepository(apiClient: ApiClient()),
              )..add(VideosCategorySelected(genre)),
              child: _TagBody(genre: genre),
            ),
    );
  }
}

class _TagBody extends StatelessWidget {
  const _TagBody({required this.genre});

  final VideoGenre genre;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        _Header(title: genre.label),
        Expanded(
          child: BlocBuilder<VideosBloc, VideosState>(
            builder: (context, state) {
              switch (state.status) {
                case VideosStatus.initial:
                case VideosStatus.loading:
                  return const Center(child: CircularProgressIndicator());
                case VideosStatus.error:
                  return _Message(
                    text: state.errorMessage ??
                        'Couldn\'t load videos right now.',
                    onRetry: () => context
                        .read<VideosBloc>()
                        .add(VideosCategorySelected(genre)),
                  );
                case VideosStatus.loaded:
                  if (state.videos.isEmpty) {
                    return const _Message(text: 'No videos here yet.');
                  }
                  return SingleChildScrollView(
                    padding:
                        EdgeInsets.only(bottom: DesignConstants.spacingBig),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: DesignConstants.spacingBig,
                      children: [
                        for (final card in state.videos)
                          VideoReccCard(
                            title: card.title,
                            metaLabel: card.metaLabel,
                            thumbnail:
                                CachedNetworkImageProvider(card.thumbnailUrl),
                            creatorPfp:
                                creatorAvatarProvider(card.channelAvatarUrl),
                            // Real playback is a follow-up; no-op for now.
                            onTap: () => debugPrint('TODO: play ${card.url}'),
                          ),
                      ],
                    ),
                  );
              }
            },
          ),
        ),
      ],
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        const _Header(title: 'Videos'),
        const Expanded(child: _Message(text: 'No videos here yet.')),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text('Retry', style: DesignConstants.p),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Icon(
            Symbols.chevron_left_sharp,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text,
            size: DesignConstants.iconSize2xl,
          ),
        ),
        Expanded(child: Text(title, style: DesignConstants.h1)),
      ],
    );
  }
}
