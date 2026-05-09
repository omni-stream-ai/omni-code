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
    return BorderRadius.circular(AppSpacing.radiusCard);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final cardTheme = theme.cardTheme;
    final defaultRadius = _defaultBorderRadius(cardTheme.shape);
    final effectiveRadius = borderRadius ?? defaultRadius;
    final shapeSide = cardTheme.shape is RoundedRectangleBorder
        ? (cardTheme.shape as RoundedRectangleBorder).side
        : BorderSide.none;
    final shadow = brightness == Brightness.dark
        ? const BoxShadow(
            color: Color.fromRGBO(31, 41, 55, 0.14),
            offset: Offset(0, 28),
            blurRadius: 50,
            spreadRadius: 0,
          )
        : const BoxShadow(
            color: Color.fromRGBO(17, 24, 39, 0.06),
            offset: Offset(0, 10),
            blurRadius: 24,
            spreadRadius: 0,
          );

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
        boxShadow: [shadow],
      ),
      child: Material(
        color: Colors.transparent,
        child: result,
      ),
    );
  }
}
