import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'session_markdown_table.dart';

/// Shared message rendering; unchanged messages retain their selection subtree.
class MessageMarkdown extends StatefulWidget {
  const MessageMarkdown(
      {super.key,
      required this.data,
      required this.theme,
      required this.textColor,
      required this.onTapLink,
      this.showImages = true,
      this.adaptiveTables = false});

  final String data;
  final ThemeData theme;
  final Color textColor;
  final ValueChanged<String?> onTapLink;
  final bool showImages, adaptiveTables;

  @override
  State<MessageMarkdown> createState() => _MessageMarkdownState();
}

class _MessageMarkdownState extends State<MessageMarkdown> {
  late Widget _content;

  @override
  void initState() {
    super.initState();
    _content = _buildContent();
  }

  @override
  void didUpdateWidget(covariant MessageMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.theme != widget.theme ||
        oldWidget.textColor != widget.textColor ||
        oldWidget.showImages != widget.showImages ||
        oldWidget.adaptiveTables != widget.adaptiveTables) {
      _content = _buildContent();
    }
  }

  Widget _buildContent() {
    final textColor = widget.textColor;
    final styleSheet = messageMarkdownStyleSheet(widget.theme, textColor);
    return SelectionArea(
      child: MarkdownBody(
        data: widget.data,
        fitContent: true,
        selectable: false,
        shrinkWrap: true,
        softLineBreak: true,
        styleSheet: styleSheet,
        syntaxHighlighter: MessageCodeSyntaxHighlighter(widget.theme),
        sizedImageBuilder:
            widget.showImages ? null : (_) => const SizedBox.shrink(),
        blockSyntaxes: [
          // Keep setext headings ahead of rules when they end a paragraph.
          const md.SetextHeaderSyntax(),
          const _MessageRuleSyntax(),
          if (widget.adaptiveTables) const SessionTableSyntax(),
        ],
        builders: {
          'message-rule': _MessageRuleBuilder(styleSheet),
          if (widget.adaptiveTables)
            'session-table':
                SessionTableBuilder((href) => widget.onTapLink(href)),
        },
        onTapLink: (text, href, title) => widget.onTapLink(href),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _content;
}

// A sized rule remains visible after scrolling. Parsing it as a Markdown block
// also preserves fenced code, headings and link definitions across sections.
class _MessageRuleSyntax extends md.HorizontalRuleSyntax {
  const _MessageRuleSyntax();

  @override
  md.Node parse(md.BlockParser parser) {
    super.parse(parser);
    return md.Element.empty('message-rule');
  }
}

class _MessageRuleBuilder extends MarkdownElementBuilder {
  _MessageRuleBuilder(this.styleSheet);

  final MarkdownStyleSheet styleSheet;

  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(BuildContext context, md.Element element,
          TextStyle? preferredStyle, TextStyle? parentStyle) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.compact / 2),
        child: DecoratedBox(
          key: const ValueKey('markdown-horizontal-rule'),
          decoration: styleSheet.horizontalRuleDecoration!,
          child: const SizedBox(width: double.infinity, height: 1),
        ),
      );
}

MarkdownStyleSheet messageMarkdownStyleSheet(ThemeData theme, Color textColor) {
  final brightness = theme.brightness;
  final codeStyle = theme.textTheme.bodyMedium?.copyWith(
    fontSize: 13,
    height: 1.55,
    color: textColor,
    letterSpacing: 0.1,
  );
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: theme.textTheme.bodyLarge?.copyWith(height: 1.45, color: textColor),
    a: theme.textTheme.bodyLarge?.copyWith(
      height: 1.45,
      color: textColor,
      decoration: TextDecoration.underline,
      decorationColor: textColor,
    ),
    code: codeStyle?.copyWith(
      backgroundColor: AppColors.tintSurfaceFor(
        brightness,
        textColor,
        base: Colors.transparent,
        darkAlpha: 0.18,
        lightAlpha: 0.10,
      ),
    ),
    strong: theme.textTheme.bodyLarge?.copyWith(
      color: textColor,
      fontWeight: FontWeight.w700,
    ),
    em: theme.textTheme.bodyLarge?.copyWith(
      color: textColor,
      fontStyle: FontStyle.italic,
    ),
    listBullet: theme.textTheme.bodyLarge?.copyWith(color: textColor),
    blockquote: theme.textTheme.bodyLarge?.copyWith(
      color: textColor.withValues(alpha: 0.9),
    ),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: textColor.withValues(alpha: 0.28),
          width: 3,
        ),
      ),
    ),
    blockquotePadding: const EdgeInsets.only(left: AppSpacing.compact),
    blockSpacing: AppSpacing.compact,
    pPadding: const EdgeInsets.symmetric(vertical: 1),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(
          width: 0.6,
          color: textColor.withValues(alpha: 0.22),
        ),
      ),
    ),
    codeblockPadding: const EdgeInsets.fromLTRB(
      AppSpacing.tileX,
      AppSpacing.tileY,
      AppSpacing.tileX,
      AppSpacing.tileX,
    ),
    codeblockDecoration: BoxDecoration(
      color: AppColors.tintSurfaceFor(
        brightness,
        textColor,
        base: Colors.transparent,
        darkAlpha: 0.14,
        lightAlpha: 0.08,
      ),
      borderRadius: BorderRadius.circular(AppSpacing.radiusPanel),
      border: Border.all(color: textColor.withValues(alpha: 0.22)),
    ),
  );
}

class MessageCodeSyntaxHighlighter extends SyntaxHighlighter {
  MessageCodeSyntaxHighlighter(this.theme);

  final ThemeData theme;

  static final RegExp _tokenPattern = RegExp(
    r'''(?<comment>//.*$|#.*$)|(?<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(?<keyword>\b(?:abstract|async|await|break|case|catch|class|const|continue|def|default|else|enum|export|extends|false|final|finally|for|from|function|if|import|in|interface|let|new|null|override|print|return|static|super|switch|this|throw|true|try|var|void|while|with|yield)\b)|(?<number>\b\d+(?:\.\d+)?\b)''',
    multiLine: true,
  );

  @override
  TextSpan format(String source) {
    final brightness = theme.brightness;
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.textFor(brightness),
      fontSize: (theme.textTheme.bodyLarge?.fontSize ?? 14) * 0.93,
      height: 1.55,
      letterSpacing: 0.1,
    );
    final commentStyle = baseStyle?.copyWith(
      color: AppColors.mutedSoftFor(brightness),
      fontStyle: FontStyle.italic,
    );
    final stringStyle = baseStyle?.copyWith(
      color: brightness == Brightness.dark
          ? const Color(0xFFFFC47A)
          : const Color(0xFF9A5200),
    );
    final keywordStyle = baseStyle?.copyWith(
      color: brightness == Brightness.dark
          ? const Color(0xFF8ED0FF)
          : const Color(0xFF005CC5),
      fontWeight: FontWeight.w700,
    );
    final numberStyle = baseStyle?.copyWith(
      color: brightness == Brightness.dark
          ? const Color(0xFFB7F287)
          : const Color(0xFF2F7D32),
    );

    final spans = <TextSpan>[];
    var currentIndex = 0;
    for (final match in _tokenPattern.allMatches(source)) {
      if (match.start > currentIndex) {
        spans.add(
          TextSpan(
            text: source.substring(currentIndex, match.start),
            style: baseStyle,
          ),
        );
      }

      final token = match.group(0)!;
      TextStyle? style = baseStyle;
      if (match.namedGroup('comment') != null) {
        style = commentStyle;
      } else if (match.namedGroup('string') != null) {
        style = stringStyle;
      } else if (match.namedGroup('keyword') != null) {
        style = keywordStyle;
      } else if (match.namedGroup('number') != null) {
        style = numberStyle;
      }

      spans.add(TextSpan(text: token, style: style));
      currentIndex = match.end;
    }

    if (currentIndex < source.length) {
      spans.add(
        TextSpan(text: source.substring(currentIndex), style: baseStyle),
      );
    }

    return TextSpan(style: baseStyle, children: spans);
  }
}
