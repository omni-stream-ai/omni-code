import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// Wrap the standard parser's table so inline markup and reference links are
// resolved by the same document, including definitions after the table.
class SessionTableSyntax extends md.TableSyntax {
  const SessionTableSyntax();

  @override
  md.Node? parse(md.BlockParser parser) {
    final table = super.parse(parser);
    return table == null ? null : md.Element('session-table', [table]);
  }
}

class SessionTableBuilder extends MarkdownElementBuilder {
  SessionTableBuilder(this.onOpenLink);
  final void Function(String) onOpenLink;

  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(BuildContext context, md.Element element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    final table = element.children!.single as md.Element;
    final rows = <List<md.Element>>[];
    for (final section in table.children!.whereType<md.Element>()) {
      for (final row in section.children!.whereType<md.Element>()) {
        rows.add(row.children!.whereType<md.Element>().toList());
      }
    }
    return _SessionTable(rows: rows, onOpenLink: onOpenLink);
  }
}

class _SessionTable extends StatefulWidget {
  const _SessionTable({required this.rows, required this.onOpenLink});
  final List<List<md.Element>> rows;
  final void Function(String) onOpenLink;

  @override
  State<_SessionTable> createState() => _SessionTableState();
}

class _SessionTableState extends State<_SessionTable> {
  final _scroll = ScrollController();
  bool _cards = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String t(String en, String zh) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  Widget cell(md.Element element,
          {bool heading = false, bool selectable = true}) =>
      _TableCell(
          element: element,
          heading: heading,
          selectable: selectable,
          onOpenLink: widget.onOpenLink);

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final headers = widget.rows.first;
    return LayoutBuilder(builder: (context, constraints) {
      final compact = MediaQuery.sizeOf(context).width < 600;
      // Bound individual columns: long prose wraps, while a wide table scrolls.
      final widths = List.generate(headers.length, (column) {
        final longest = widget.rows.fold<int>(0,
            (length, row) => math.max(length, row[column].textContent.length));
        return (longest * 8.0 + 28).clamp(120.0, 280.0);
      });
      final naturalWidth = widths.fold<double>(0, (a, b) => a + b);
      final availableWidth = math.max(0.0, constraints.maxWidth - 2);
      final overflow = naturalWidth > availableWidth;
      final extra =
          math.max(0.0, availableWidth - naturalWidth) / headers.length;
      final cards = compact && _cards && widget.rows.length > 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (overflow || (compact && widget.rows.length > 1))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                      cards
                          ? t('One card per row', '每行一张卡片')
                          : overflow
                              ? t('Scroll sideways to see all columns',
                                  '左右滑动查看完整表格')
                              : t('Table', '表格'),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                  if (compact && widget.rows.length > 1)
                    TextButton.icon(
                      onPressed: () => setState(() => _cards = !_cards),
                      icon: Icon(
                          cards
                              ? Icons.table_chart_outlined
                              : Icons.view_agenda_outlined,
                          size: 16),
                      label: Text(cards ? t('Table', '表格') : t('Cards', '卡片')),
                    ),
                ],
              ),
            ),
          if (cards)
            for (var row = 1; row < widget.rows.length; row++)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < headers.length; column++) ...[
                      if (column > 0) const Divider(height: 24),
                      if (headers[column].textContent.trim().isNotEmpty)
                        cell(headers[column], heading: true)
                      else
                        Text(t('Column ${column + 1}', '第 ${column + 1} 列')),
                      const SizedBox(height: 6),
                      cell(widget.rows[row][column]),
                    ],
                  ],
                ),
              )
          else
            Container(
              // Paint the frame outside the scrolling viewport so neither
              // vertical edge disappears when the content is scrolled.
              decoration: BoxDecoration(
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(1),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: overflow,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.only(bottom: overflow ? 12 : 0),
                    child: Table(
                      columnWidths: {
                        for (var i = 0; i < widths.length; i++)
                          i: FixedColumnWidth(widths[i] + extra),
                      },
                      defaultVerticalAlignment: TableCellVerticalAlignment.top,
                      border: TableBorder.symmetric(
                        inside: BorderSide(color: colors.outlineVariant),
                      ),
                      children: [
                        for (var row = 0; row < widget.rows.length; row++)
                          TableRow(
                            decoration: BoxDecoration(
                              color: row == 0
                                  ? colors.surfaceContainerHighest
                                  : row.isEven
                                      ? colors.surfaceContainerLow
                                      : colors.surface,
                            ),
                            children: [
                              for (final element in widget.rows[row])
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  child: cell(element,
                                      heading: row == 0, selectable: !compact),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

// Render the original inline AST rather than converting cells to plain text.
// This preserves links, emphasis, code and escaped pipes in both display modes.
class _TableCell extends StatefulWidget {
  const _TableCell(
      {required this.element,
      required this.heading,
      required this.selectable,
      required this.onOpenLink});
  final md.Element element;
  final bool heading;
  final bool selectable;
  final void Function(String) onOpenLink;

  @override
  State<_TableCell> createState() => _TableCellState();
}

class _TableCellState extends State<_TableCell>
    implements MarkdownBuilderDelegate {
  final _recognizers = <TapGestureRecognizer>[];

  void _clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        if (href != null) widget.onOpenLink(href);
      };
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) =>
      TextSpan(text: code, style: styleSheet.code);

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final theme = Theme.of(context);
    final alignment = switch (widget.element.attributes['align']) {
      'right' => WrapAlignment.end,
      'center' => WrapAlignment.center,
      _ => WrapAlignment.start,
    };
    final style = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.6,
          color: theme.colorScheme.onSurface,
          fontWeight: widget.heading ? FontWeight.w600 : FontWeight.w400),
      textAlign: alignment,
      code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: theme.colorScheme.onSurface,
          backgroundColor: theme.colorScheme.surfaceContainerHighest),
    );
    final builder = MarkdownBuilder(
      delegate: this,
      selectable: widget.selectable,
      styleSheet: style,
      imageDirectory: null,
      sizedImageBuilder: null,
      checkboxBuilder: null,
      bulletBuilder: null,
      builders: {},
      paddingBuilders: {},
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: builder.build([md.Element('p', widget.element.children)]),
    );
  }
}
