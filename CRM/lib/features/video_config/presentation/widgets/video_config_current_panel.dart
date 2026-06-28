import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/video_config/data/models/video_config_models.dart';
import 'package:crm/shared/widgets/section_card.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

/// Compact read-only panel showing the current saved video config:
/// discipline tags, a We surface / We avoid markdown switcher, and the
/// YouTube search queries list.
///
/// Shown at the top of the video-config screen when a config exists,
/// giving the owner context while they chat with the agent.
class VideoConfigCurrentPanel extends StatefulWidget {
  final VideoConfigView config;

  const VideoConfigCurrentPanel({super.key, required this.config});

  @override
  State<VideoConfigCurrentPanel> createState() =>
      _VideoConfigCurrentPanelState();
}

class _VideoConfigCurrentPanelState
    extends State<VideoConfigCurrentPanel> {
  // 0 = We surface (videosDesc), 1 = We avoid (avoidDesc).
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          _HeaderRow(config: widget.config),
          ViewSwitcher(
            labels: const ['We surface', 'We avoid'],
            selectedIndex: _index,
            onSelected: (i) => setState(() => _index = i),
          ),
          _DescBody(
            markdown: _index == 0
                ? widget.config.videosDesc
                : widget.config.avoidDesc,
          ),
          if (widget.config.queries.isNotEmpty) ...[
            Text('Search queries', style: DesignConstants.h3),
            _QueriesList(queries: widget.config.queries),
          ],
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final VideoConfigView config;

  const _HeaderRow({required this.config});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text('Current config', style: DesignConstants.h3),
        ),
        if (config.disciplines.isNotEmpty)
          Text(
            config.disciplines.join(', '),
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}

class _DescBody extends StatelessWidget {
  final String markdown;

  const _DescBody({required this.markdown});

  @override
  Widget build(BuildContext context) {
    if (markdown.isEmpty) {
      return Text(
        'No description yet.',
        style: DesignConstants.p.copyWith(
          color: DesignConstants.text2nd,
        ),
      );
    }
    final body = DesignConstants.p.copyWith(
      color: DesignConstants.text2nd,
    );
    return MarkdownBody(
      data: markdown,
      selectable: false,
      styleSheet: MarkdownStyleSheet(
        p: body,
        h3: DesignConstants.h3,
        strong: DesignConstants.pBold.copyWith(
          color: DesignConstants.text2nd,
        ),
        em: body.copyWith(fontStyle: FontStyle.italic),
        listBullet: body,
        blockSpacing: DesignConstants.spacingSmall,
        listIndent: DesignConstants.spacingLarge,
        a: body.copyWith(color: DesignConstants.hyperlink),
      ),
    );
  }
}

class _QueriesList extends StatelessWidget {
  final List<String> queries;

  const _QueriesList({required this.queries});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        for (final q in queries)
          Text(
            '• $q',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}
