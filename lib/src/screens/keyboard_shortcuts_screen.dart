import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../settings/app_settings.dart';
import '../shortcuts/desktop_shortcut.dart';
import '../shortcuts/shortcut_labels.dart';
import '../shortcuts/shortcut_recorder_dialog.dart';
import '../shortcuts/shortcut_keycaps.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_card.dart';

class KeyboardShortcutsScreen extends StatefulWidget {
  const KeyboardShortcutsScreen({super.key});

  static const routeName = '/settings/shortcuts';

  @override
  State<KeyboardShortcutsScreen> createState() =>
      _KeyboardShortcutsScreenState();
}

class _KeyboardShortcutsScreenState extends State<KeyboardShortcutsScreen> {
  bool _saving = false;

  Future<void> _save(
      Map<DesktopShortcutAction, DesktopKeyBinding?> bindings) async {
    setState(() => _saving = true);
    try {
      await appSettingsController.save(
        appSettingsController.settings.copyWith(desktopShortcuts: bindings),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.settingsSaveFailed('$error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(DesktopShortcutAction action) async {
    final binding = await showDialog<DesktopKeyBinding>(
      context: context,
      builder: (_) => ShortcutRecorderDialog(
        action: action,
        bindings: appSettingsController.settings.desktopShortcuts,
      ),
    );
    if (binding == null || !mounted) return;
    await _save(
        {...appSettingsController.settings.desktopShortcuts, action: binding});
  }

  Future<void> _reset(DesktopShortcutAction action) async {
    final bindings = {...appSettingsController.settings.desktopShortcuts}
      ..remove(action);
    final binding = defaultDesktopShortcut(action);
    for (final other in DesktopShortcutAction.values) {
      if (other != action &&
          resolveDesktopShortcut(bindings, other) == binding) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(context.l10n.shortcutConflict(other.label(context.l10n))),
        ));
        return;
      }
    }
    await _save(bindings);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: appSettingsController,
        builder: (context, _) {
          final l10n = context.l10n;
          return Scaffold(
            appBar: AppBar(title: Text(l10n.desktopShortcutsTitle)),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildIntro(context),
                    const SizedBox(height: AppSpacing.section),
                    _buildGroup(context, l10n.shortcutsGroupCreate, const [
                      DesktopShortcutAction.search,
                      DesktopShortcutAction.newWindow,
                      DesktopShortcutAction.newSession,
                    ]),
                    const SizedBox(height: AppSpacing.section),
                    _buildGroup(context, l10n.shortcutsGroupNavigate, const [
                      DesktopShortcutAction.settings,
                      DesktopShortcutAction.home,
                      DesktopShortcutAction.projects,
                      DesktopShortcutAction.toggleNavigation,
                      DesktopShortcutAction.goBack,
                    ]),
                    const SizedBox(height: AppSpacing.section),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.restore_rounded, size: 18),
                        onPressed: _saving ||
                                appSettingsController
                                    .settings.desktopShortcuts.isEmpty
                            ? null
                            : () => _save({}),
                        label: Text(l10n.shortcutResetAll),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _buildIntro(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accentBlueFor(theme.brightness)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
            ),
            child: Icon(Icons.keyboard_outlined,
                size: 28, color: AppColors.accentBlueFor(theme.brightness)),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Text(l10n.shortcutsHeroTitle,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 16),
        Text(l10n.shortcutsEditHint,
            style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.mutedSoftFor(theme.brightness), height: 1.5)),
        const SizedBox(height: 12),
        Row(children: [
          if (_saving)
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(Icons.check_circle_outline_rounded,
                size: 16, color: AppColors.accentBlueFor(theme.brightness)),
          const SizedBox(width: 6),
          Text(_saving ? l10n.saving : l10n.shortcutsAutoSaved,
              style: theme.textTheme.bodySmall),
        ]),
      ],
    );
  }

  Widget _buildGroup(BuildContext context, String title,
          List<DesktopShortcutAction> actions) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      indent: 18,
                      endIndent: 18,
                      color:
                          AppColors.outlineFor(Theme.of(context).brightness)),
                _buildShortcutRow(context, actions[i]),
              ],
            ]),
          ),
        ],
      );

  Widget _buildShortcutRow(BuildContext context, DesktopShortcutAction action) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final bindings = appSettingsController.settings.desktopShortcuts;
    final binding = resolveDesktopShortcut(bindings, action);
    final icon = switch (action) {
      DesktopShortcutAction.search => Icons.search_rounded,
      DesktopShortcutAction.newWindow => Icons.open_in_new_rounded,
      DesktopShortcutAction.newSession => Icons.add_comment_outlined,
      DesktopShortcutAction.settings => Icons.settings_outlined,
      DesktopShortcutAction.home => Icons.home_outlined,
      DesktopShortcutAction.projects => Icons.folder_open_outlined,
      DesktopShortcutAction.toggleNavigation => Icons.view_sidebar_outlined,
      DesktopShortcutAction.goBack => Icons.arrow_back_rounded,
    };
    final title = Row(children: [
      Icon(icon, size: 20, color: AppColors.mutedSoftFor(theme.brightness)),
      const SizedBox(width: 12),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(action.label(l10n),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        if (bindings.containsKey(action)) ...[
          const SizedBox(height: 3),
          Text(
              binding == null ? l10n.shortcutDisabled : l10n.shortcutCustomized,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.mutedFor(theme.brightness))),
        ],
      ])),
    ]);
    final controls = Row(mainAxisSize: MainAxisSize.min, children: [
      Tooltip(
        message: l10n.shortcutChange,
        child: TextButton(
          key: Key('shortcut-edit-${action.name}'),
          onPressed: _saving ? null : () => _edit(action),
          child: binding == null
              ? Text(l10n.shortcutDisabled)
              : ShortcutKeycaps(labels: binding.keyLabels),
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        key: Key('shortcut-disable-${action.name}'),
        tooltip: l10n.shortcutDisable,
        onPressed: _saving || binding == null
            ? null
            : () => _save({...bindings, action: null}),
        icon: const Icon(Icons.block_outlined, size: 18),
      ),
      IconButton(
        key: Key('shortcut-reset-${action.name}'),
        tooltip: l10n.shortcutReset,
        onPressed: _saving || !bindings.containsKey(action)
            ? null
            : () => _reset(action),
        icon: const Icon(Icons.restore_rounded, size: 19),
      ),
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 560
              ? Row(children: [
                  Expanded(child: title),
                  const SizedBox(width: 16),
                  controls
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  title,
                  const SizedBox(height: 8),
                  Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(fit: BoxFit.scaleDown, child: controls)),
                ])),
    );
  }
}
