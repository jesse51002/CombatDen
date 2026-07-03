import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_quill/markdown_quill.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A flutter_quill rich-text editor that round-trips **Markdown**. The waiver
/// body is stored as a Markdown string; the gym owner only ever sees formatted
/// text. Used editable for the current version and read-only for old versions.
class WaiverMarkdownEditor extends StatelessWidget {
  final QuillController controller;

  const WaiverMarkdownEditor({super.key, required this.controller});

  /// Build a controller seeded from a Markdown string.
  static QuillController controllerFromMarkdown(
    String markdown, {
    bool readOnly = false,
  }) {
    final delta = MarkdownToDelta(
      markdownDocument: md.Document(encodeHtml: false),
    ).convert(markdown);
    final document =
        delta.isEmpty ? Document() : Document.fromDelta(Delta.from(delta));
    return QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: readOnly,
    );
  }

  /// Export the controller's content as a Markdown string.
  ///
  /// [DeltaToMarkdown] backslash-escapes literal braces/underscores, which
  /// would store a waiver placeholder as `\{\{member\_name\}\}` — it displays
  /// identically in the editor (the parser unescapes), but the backend and
  /// preview renderers match on the plain `{{token}}` form, so the escaped
  /// form silently never fills. Canonicalize tokens on the way out.
  static String markdownFromController(QuillController controller) =>
      _unescapePlaceholders(
        DeltaToMarkdown().convert(controller.document.toDelta()).trim(),
      );

  static final RegExp _escapedToken =
      RegExp(r'\\?\{\\?\{((?:\w|\\_)+)\\?\}\\?\}');

  static String _unescapePlaceholders(String markdown) =>
      markdown.replaceAllMapped(
        _escapedToken,
        (m) => '{{${m.group(1)!.replaceAll(r'\_', '_')}}}',
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!controller.readOnly)
          QuillSimpleToolbar(controller: controller),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: DesignConstants.line),
              borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
            ),
            padding: const EdgeInsets.all(DesignConstants.paddingSmall),
            child: QuillEditor.basic(
              controller: controller,
              config: const QuillEditorConfig(
                placeholder: 'Write the waiver members agree to…',
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
