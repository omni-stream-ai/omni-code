import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_card.dart';

class AppSkeletonBlock extends StatelessWidget {
  const AppSkeletonBlock({
    super.key,
    required this.height,
    this.width,
    this.borderRadius,
    this.margin,
  });

  final double height;
  final double? width;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          borderRadius:
              borderRadius ?? BorderRadius.circular(AppSpacing.radiusControl),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              AppColors.skeletonBaseFor(brightness),
              AppColors.skeletonHighlightFor(brightness),
              AppColors.skeletonBaseFor(brightness),
            ],
            stops: const [0, 0.55, 1],
          ),
        ),
      ),
    );
  }
}

class AppSkeletonCard extends StatelessWidget {
  const AppSkeletonCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.margin,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: margin,
      padding: padding,
      borderRadius:
          borderRadius ?? BorderRadius.circular(AppSpacing.radiusTile),
      child: child,
    );
  }
}
