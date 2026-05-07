import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = AppSpacing.cardPadding,
    this.margin,
    this.color,
    this.borderRadius,
    this.borderSide,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final BorderRadius? borderRadius;
  final BorderSide? borderSide;

  BorderRadius _defaultBorderRadius(ShapeBorder? shape) {
    if (shape is RoundedRectangleBorder) {
      return shape.borderRadius as BorderRadius;
    }
    return BorderRadius.circular(16);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardTheme = theme.cardTheme;
    final defaultRadius = _defaultBorderRadius(cardTheme.shape);
    final effectiveRadius = borderRadius ?? defaultRadius;
    final shapeSide = cardTheme.shape is RoundedRectangleBorder
        ? (cardTheme.shape as RoundedRectangleBorder).side
        : BorderSide.none;

    Widget result = Padding(
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      result = InkWell(
        onTap: onTap,
        borderRadius: effectiveRadius,
        child: result,
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? cardTheme.color,
        borderRadius: effectiveRadius,
        border: Border.fromBorderSide(borderSide ?? shapeSide),
      ),
      child: Material(
        color: Colors.transparent,
        child: result,
      ),
    );
  }
}
