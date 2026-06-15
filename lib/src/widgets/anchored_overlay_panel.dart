import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

class AnchoredOverlayPanel extends StatelessWidget {
  const AnchoredOverlayPanel({
    super.key,
    required this.targetKey,
    required this.child,
    this.gap = AppSpacing.compact,
    this.minWidth = 240,
    this.maxWidth,
    this.maxHeight = 280,
    this.preferBelow = true,
  });

  final GlobalKey targetKey;
  final Widget child;
  final double gap;
  final double minWidth;
  final double? maxWidth;
  final double maxHeight;
  final bool preferBelow;

  Rect? _targetRect() {
    final renderObject = targetKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }

  @override
  Widget build(BuildContext context) {
    final rect = _targetRect();
    if (rect == null) {
      return const SizedBox.shrink();
    }
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final safeLeft = AppSpacing.screenX;
    final safeRight = screenSize.width - AppSpacing.screenX;
    final safeTop = mediaQuery.padding.top + AppSpacing.compact;
    final safeBottom =
        screenSize.height - mediaQuery.viewInsets.bottom - mediaQuery.padding.bottom;
    final availableBelow = safeBottom - (rect.bottom + gap);
    final availableAbove = (rect.top - gap) - safeTop;
    final showBelow = switch ((preferBelow, availableBelow, availableAbove)) {
      (true, final below, final above) when below >= maxHeight => true,
      (true, _, final above) when above > availableBelow => false,
      (false, _, final above) when above > 0 => false,
      _ => availableBelow >= availableAbove,
    };
    final unclampedPanelWidth =
        maxWidth == null ? rect.width : rect.width.clamp(minWidth, maxWidth!);
    final panelWidth = unclampedPanelWidth
        .clamp(minWidth, safeRight - safeLeft)
        .toDouble();
    final availableHeight =
        (showBelow ? availableBelow : availableAbove).clamp(0, maxHeight).toDouble();
    final maxLeft = (safeRight - panelWidth).clamp(safeLeft, safeRight).toDouble();
    final left = switch ((rect.left, rect.right - panelWidth)) {
      (final leftEdge, _) when leftEdge >= safeLeft && leftEdge + panelWidth <= safeRight =>
        leftEdge,
      (_, final rightAlignedLeft)
          when rightAlignedLeft >= safeLeft &&
              rightAlignedLeft + panelWidth <= safeRight =>
        rightAlignedLeft,
      _ => rect.left.clamp(safeLeft, maxLeft).toDouble(),
    };
    final top = showBelow ? rect.bottom + gap : null;
    final bottom = showBelow ? null : screenSize.height - rect.top + gap;

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            bottom: bottom,
            width: panelWidth,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: minWidth.clamp(0, panelWidth).toDouble(),
                maxWidth: panelWidth,
                maxHeight: availableHeight,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
