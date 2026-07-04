import 'dart:async';

import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../responsive/app_responsive_layout.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_navigation_scaffold.dart';
import '../widgets/app_back_header.dart';
import '../widgets/app_card.dart';
import '../widgets/new_session_flow.dart';
import '../../l10n/generated/app_localizations.dart';

class ModelProviderScreen extends StatefulWidget {
  const ModelProviderScreen({super.key});

  static const routeName = '/settings/model-providers';

  @override
  State<ModelProviderScreen> createState() => _ModelProviderScreenState();
}

class _ModelProviderScreenState extends State<ModelProviderScreen> {
  static const double _desktopRailWidth = 300;
  List<ModelProviderConfig> _providers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProviders());
  }

  Future<void> _loadProviders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final providers = await bridgeClient.getModelProviders();
      if (!mounted) return;
      setState(() {
        _providers = providers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _saveProviders() async {
    try {
      await bridgeClient.updateBridgeSettings(
        appSettingsController.settings,
        modelProviders: _providers,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsSaveFailed('$e'))),
      );
    }
  }

  void _addProvider() async {
    final result = await showDialog<ModelProviderConfig>(
      context: context,
      builder: (context) => _ProviderEditDialog(),
    );
    if (result != null) {
      setState(() {
        _providers = [..._providers, result];
      });
      unawaited(_saveProviders());
    }
  }

  void _editProvider(int index) async {
    final result = await showDialog<ModelProviderConfig>(
      context: context,
      builder: (context) => _ProviderEditDialog(provider: _providers[index]),
    );
    if (result != null) {
      setState(() {
        _providers = [
          for (int i = 0; i < _providers.length; i++)
            if (i == index) result else _providers[i],
        ];
      });
      unawaited(_saveProviders());
    }
  }

  void _deleteProvider(int index) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteProvider),
        content: Text(_providers[index].name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _providers = [
                  for (int i = 0; i < _providers.length; i++)
                    if (i != index) _providers[i],
                ];
              });
              unawaited(_saveProviders());
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  void _toggleEnabled(int index, bool value) {
    setState(() {
      _providers = [
        for (int i = 0; i < _providers.length; i++)
          if (i == index)
            _providers[i].copyWith(enabled: value)
          else
            _providers[i],
      ];
    });
    unawaited(_saveProviders());
  }

  void _onReorderItem(int oldIndex, int newIndex) {
    setState(() {
      final item = _providers.removeAt(oldIndex);
      _providers.insert(newIndex, item);
      // Update priorities based on new order
      _providers = [
        for (int i = 0; i < _providers.length; i++)
          _providers[i].copyWith(priority: i),
      ];
    });
    unawaited(_saveProviders());
  }

  Future<void> _startNewSession() async {
    await startNewSessionFlow(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final recentProjects =
        bridgeClient.peekProjects() ?? const <ProjectSummary>[];
    final recentSessions =
        bridgeClient.peekSessions() ?? const <SessionSummary>[];
    final desktopSidebarCollapsed =
        appSettingsController.settings.desktopNavigationCollapsed;
    return AppNavigationScaffold(
      activeRoute: AppRouteKind.settings,
      recentProjects: recentProjects,
      recentSessions: recentSessions,
      desktopBreakpoint: AppResponsiveLayout.desktopBreakpoint,
      desktopSidebarWidth: AppResponsiveLayout.desktopSidebarWidth,
      desktopSidebarCollapsedWidth:
          AppResponsiveLayout.desktopSidebarCollapsedWidth,
      desktopSidebarCollapsed: desktopSidebarCollapsed,
      onToggleDesktopSidebar: _toggleDesktopSidebarCollapsed,
      onNavigateHome: () => Navigator.of(context).popUntil(
        (route) => route.settings.name == AppRoutes.home || route.isFirst,
      ),
      onNavigateProjects: () =>
          Navigator.of(context).pushNamed(AppRoutes.projects),
      onNavigateSettings: () => Navigator.of(context).pop(),
      onOpenProject: (project) {
        Navigator.of(context).pushNamed(
          AppRoutes.project(project.id),
          arguments: project,
        );
      },
      onOpenSession: (session) {
        Navigator.of(context).pushNamed(
          AppRoutes.session(session.projectId, session.id),
          arguments: session,
        );
      },
      onNewSession: _startNewSession,
      bodyBuilder: (context, useDesktop, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenX,
            AppSpacing.card,
            AppSpacing.screenX,
            AppSpacing.block,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: useDesktop ? 1240 : AppSpacing.contentMaxWidth,
                ),
                child: useDesktop
                    ? _buildDesktopLayout(context, l10n)
                    : _buildMobileLayout(context, l10n),
              ),
            ),
          ),
        );
      },
      floatingActionButton: _buildFloatingActionButton(context),
    );
  }

  Widget? _buildFloatingActionButton(BuildContext context) {
    final useDesktop =
        AppResponsiveLayout.isDesktopWidth(MediaQuery.sizeOf(context).width);
    if (useDesktop) {
      return null;
    }
    return FloatingActionButton(
      onPressed: _addProvider,
      child: const Icon(Icons.add_rounded),
    );
  }

  Widget _buildMobileLayout(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context, l10n),
        const SizedBox(height: AppSpacing.fieldGap),
        _buildProviderBody(context, l10n),
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context, AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, l10n),
              const SizedBox(height: AppSpacing.fieldGap),
              _buildProviderBody(context, l10n),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.card),
        SizedBox(
          width: _desktopRailWidth,
          child: _ModelProviderDesktopRail(
            providers: _providers,
            loading: _loading,
            error: _error,
            onAddProvider: _addProvider,
            onReload: _loadProviders,
          ),
        ),
      ],
    );
  }

  Widget _buildProviderBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.block),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return _buildErrorState(context, l10n);
    }
    if (_providers.isEmpty) {
      return _buildEmptyState(context, l10n);
    }
    return _buildProviderList(context, l10n);
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final useDesktop =
        AppResponsiveLayout.isDesktopWidth(MediaQuery.sizeOf(context).width);
    final titleStyle = theme.textTheme.headlineMedium?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      height: 1.1,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (!useDesktop) ...[
          Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.only(right: AppSpacing.compact),
              child: SizedBox(
                width: 34,
                height: 34,
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.panelDeepFor(theme.brightness),
                    side: BorderSide.none,
                    minimumSize: const Size.square(34),
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                  ),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  tooltip: 'Open navigation',
                  icon: const Icon(Icons.menu_rounded, size: 18),
                ),
              ),
            ),
          ),
        ],
        Expanded(
          child: AppBackHeader(
            title: l10n.modelProvidersSection.toUpperCase(),
            titleStyle: titleStyle,
          ),
        ),
        SizedBox(
          height: 32,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              minimumSize: const Size(72, 32),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.tileX,
              ),
              shape: const StadiumBorder(),
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            onPressed: _addProvider,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(l10n.addProvider),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return AppCard(
      padding: AppSpacing.cardPadding,
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 32,
            color: AppColors.errorIconFor(theme.brightness),
          ),
          const SizedBox(height: AppSpacing.stack),
          Text(
            _error!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.errorTextFor(theme.brightness),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.stack),
          TextButton(
            onPressed: _loadProviders,
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleDesktopSidebarCollapsed() {
    return toggleDesktopNavigationCollapsed().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return AppCard(
      padding: AppSpacing.cardPadding,
      child: Column(
        children: [
          Icon(
            Icons.dns_outlined,
            size: 32,
            color: theme.iconTheme.color?.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSpacing.stack),
          Text(
            l10n.noProvidersYet,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.micro),
          Text(
            l10n.noProvidersHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProviderList(BuildContext context, AppLocalizations l10n) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: _providers.length,
      onReorderItem: _onReorderItem,
      itemBuilder: (context, index) {
        final provider = _providers[index];
        return _ProviderCard(
          key: ValueKey(provider.id),
          provider: provider,
          index: index,
          onEdit: () => _editProvider(index),
          onDelete: () => _deleteProvider(index),
          onToggle: (value) => _toggleEnabled(index, value),
        );
      },
    );
  }
}

class _ModelProviderDesktopRail extends StatelessWidget {
  const _ModelProviderDesktopRail({
    required this.providers,
    required this.loading,
    required this.error,
    required this.onAddProvider,
    required this.onReload,
  });

  final List<ModelProviderConfig> providers;
  final bool loading;
  final String? error;
  final VoidCallback onAddProvider;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final enabledCount = providers.where((provider) => provider.enabled).length;
    final defaultProvider = providers.isEmpty ? null : providers.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Provider order',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.stackTight),
              _ProviderRailRow(
                label: 'Configured',
                value: loading ? '...' : '${providers.length}',
              ),
              _ProviderRailRow(
                label: 'Enabled',
                value: loading ? '...' : '$enabledCount',
              ),
              _ProviderRailRow(
                label: 'Default',
                value: defaultProvider?.name ?? 'None',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.stackTight),
        AppCard(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Actions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.compact),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onAddProvider,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.l10n.addProvider),
                ),
              ),
              const SizedBox(height: AppSpacing.compact),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: loading ? null : onReload,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.l10n.retry),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.compact),
                Text(
                  error!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.errorTextFor(brightness),
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.stackTight),
        AppCard(
          padding: AppSpacing.cardPadding,
          child: Text(
            'Drag providers to change priority. Disabled providers stay saved but will not be used for new sessions.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedSoftFor(brightness),
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProviderRailRow extends StatelessWidget {
  const _ProviderRailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.compact),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.mutedFor(brightness),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.compact),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    super.key,
    required this.provider,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final ModelProviderConfig provider;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.stackTight),
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: AppSpacing.cardPadding,
        leading: ReorderableDragStartListener(
          index: index,
          child: Icon(
            Icons.drag_handle_rounded,
            color: theme.iconTheme.color?.withValues(alpha: 0.5),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                provider.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.micro),
            _FormatBadge(format: provider.format),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.micro),
            Text(
              provider.baseUrl,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (provider.model != null && provider.model!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Model: ${provider.model}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color
                        ?.withValues(alpha: 0.5),
                  ),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: provider.enabled,
              onChanged: onToggle,
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(context.l10n.editProvider),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    context.l10n.deleteProvider,
                    style: TextStyle(
                      color: AppColors.errorTextFor(theme.brightness),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}

class _FormatBadge extends StatelessWidget {
  const _FormatBadge({required this.format});

  final ApiFormat format;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (format) {
      ApiFormat.anthropicMessages => AppColors.accentBlueFor(theme.brightness),
      ApiFormat.codex => AppColors.accentBlueFor(theme.brightness),
      ApiFormat.openaiCompatible =>
        theme.colorScheme.onSurface.withValues(alpha: 0.6),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        format.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProviderEditDialog extends StatefulWidget {
  const _ProviderEditDialog({this.provider});

  final ModelProviderConfig? provider;

  @override
  State<_ProviderEditDialog> createState() => _ProviderEditDialogState();
}

class _ProviderEditDialogState extends State<_ProviderEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late ApiFormat _format;
  late bool _enabled;

  bool get _isEditing => widget.provider != null;

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _nameController = TextEditingController(text: p?.name ?? '');
    _baseUrlController = TextEditingController(text: p?.baseUrl ?? '');
    _apiKeyController = TextEditingController(text: p?.apiKey ?? '');
    _modelController = TextEditingController(text: p?.model ?? '');
    _format = p?.format ?? ApiFormat.openaiCompatible;
    _enabled = p?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final provider = ModelProviderConfig(
      id: widget.provider?.id ?? _generateId(),
      name: _nameController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim().isEmpty
          ? null
          : _modelController.text.trim(),
      format: _format,
      enabled: _enabled,
      priority: widget.provider?.priority ?? 0,
    );
    Navigator.of(context).pop(provider);
  }

  String _generateId() {
    return 'provider_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final formValueTextStyle = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w400,
    );
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = (screenWidth * 0.85).clamp(320.0, 400.0);
    return AlertDialog(
      title: Text(_isEditing ? l10n.editProvider : l10n.addProvider),
      content: SizedBox(
        width: dialogWidth,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  style: formValueTextStyle,
                  decoration: InputDecoration(
                    labelText: l10n.providerName,
                    hintText: l10n.providerNameHint,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.fieldRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.stack),
                TextFormField(
                  controller: _baseUrlController,
                  style: formValueTextStyle,
                  decoration: InputDecoration(
                    labelText: l10n.providerBaseUrl,
                    hintText: l10n.providerBaseUrlHint,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.fieldRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.stack),
                TextFormField(
                  controller: _apiKeyController,
                  obscureText: true,
                  style: formValueTextStyle,
                  decoration: InputDecoration(
                    labelText: l10n.providerApiKey,
                  ),
                ),
                const SizedBox(height: AppSpacing.stack),
                TextFormField(
                  controller: _modelController,
                  style: formValueTextStyle,
                  decoration: InputDecoration(
                    labelText: l10n.providerModel,
                    hintText: l10n.providerModelHint,
                  ),
                ),
                const SizedBox(height: AppSpacing.stack),
                DropdownButtonFormField<ApiFormat>(
                  initialValue: _format,
                  style: formValueTextStyle,
                  decoration: InputDecoration(
                    labelText: l10n.providerFormat,
                  ),
                  items: ApiFormat.values
                      .map(
                        (f) => DropdownMenuItem(
                          value: f,
                          child: Text(f.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _format = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.stack),
                SwitchListTile(
                  value: _enabled,
                  onChanged: (value) {
                    setState(() {
                      _enabled = value;
                    });
                  },
                  title: Text(l10n.providerEnabled),
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
