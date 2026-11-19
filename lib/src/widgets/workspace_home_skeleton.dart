import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_skeleton.dart';

class WorkspaceMainAgentSkeleton extends StatelessWidget {
  const WorkspaceMainAgentSkeleton({super.key});

  @override
  Widget build(BuildContext context) =>
      const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
            height: 48,
            child: Row(children: [
              AppSkeletonBlock(
                  width: 36,
                  height: 36,
                  borderRadius: BorderRadius.all(Radius.circular(18))),
              SizedBox(width: 12),
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    AppSkeletonBlock(width: 112, height: 17),
                    SizedBox(height: 7),
                    AppSkeletonBlock(width: 156, height: 10),
                  ])),
              SizedBox(width: 12),
              AppSkeletonBlock(width: 24, height: 24),
              SizedBox(width: 16),
              AppSkeletonBlock(width: 24, height: 24),
              SizedBox(width: 16),
              AppSkeletonBlock(width: 24, height: 24),
            ])),
        SizedBox(height: 12),
        _ComposerSkeleton(),
      ]);
}

class _ComposerSkeleton extends StatelessWidget {
  const _ComposerSkeleton();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
        height: 130,
        padding: const EdgeInsets.fromLTRB(18, 18, 12, 12),
        decoration: BoxDecoration(
            color: AppColors.panelFor(brightness).withValues(alpha: .5),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: AppColors.outlineFor(brightness).withValues(alpha: .6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: const AppSkeletonBlock(height: 14)),
          const Spacer(),
          const Row(children: [
            AppSkeletonBlock(width: 96, height: 12),
            Spacer(),
            AppSkeletonBlock(width: 16, height: 20),
            SizedBox(width: 16),
            AppSkeletonBlock(
                width: 36,
                height: 36,
                borderRadius: BorderRadius.all(Radius.circular(12))),
          ]),
        ]));
  }
}

class WorkspaceTasksSkeleton extends StatelessWidget {
  const WorkspaceTasksSkeleton({super.key});

  @override
  Widget build(BuildContext context) =>
      const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
            height: 44,
            child: Row(children: [
              Expanded(
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: AppSkeletonBlock(width: 76, height: 15))),
              AppSkeletonBlock(width: 22, height: 22),
              SizedBox(width: 24),
              AppSkeletonBlock(width: 22, height: 22),
            ])),
        SizedBox(height: 8),
        Row(children: [
          AppSkeletonBlock(width: 80, height: 32),
          SizedBox(width: 16),
          AppSkeletonBlock(width: 120, height: 32),
        ]),
        SizedBox(height: 16),
        _TaskSkeletonRow(),
        _TaskSkeletonRow(),
        _TaskSkeletonRow(),
      ]);
}

class _TaskSkeletonRow extends StatelessWidget {
  const _TaskSkeletonRow();

  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppSkeletonBlock(width: 34, height: 34),
        SizedBox(width: 11),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FractionallySizedBox(
              widthFactor: .8, child: AppSkeletonBlock(height: 14)),
          SizedBox(height: 12),
          FractionallySizedBox(
              widthFactor: .6, child: AppSkeletonBlock(height: 10)),
        ])),
        SizedBox(width: 16),
        AppSkeletonBlock(width: 18, height: 8),
      ]));
}
