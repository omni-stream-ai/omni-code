import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../services/local_bridge_setup.dart';
import '../theme/app_spacing.dart';
import 'app_card.dart';

class LocalBridgeSetupCard extends StatelessWidget {
  const LocalBridgeSetupCard({
    super.key,
    required this.onInstall,
    this.progress,
    this.failure,
    this.onContinueWithAgent,
  });

  final VoidCallback? onInstall;
  final LocalBridgeSetupProgress? progress;
  final LocalBridgeSetupFailure? failure;
  final VoidCallback? onContinueWithAgent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stage = progress?.stage;
    final status = switch (stage) {
      LocalBridgeSetupStage.checking => l10n.localBridgeChecking,
      LocalBridgeSetupStage.downloading => l10n.localBridgeDownloading,
      LocalBridgeSetupStage.installing => l10n.localBridgeInstalling,
      LocalBridgeSetupStage.configuringStartup => l10n.localBridgeConfiguring,
      LocalBridgeSetupStage.starting => l10n.localBridgeStarting,
      LocalBridgeSetupStage.authorizing => l10n.localBridgeAuthorizing,
      null => l10n.localBridgeInstallAction,
    };
    final error = switch (failure) {
      LocalBridgeSetupFailure.existingBridge => l10n.localBridgeExistingError,
      LocalBridgeSetupFailure.incompatibleVersion =>
        l10n.localBridgeIncompatibleError,
      LocalBridgeSetupFailure.downloadFailed => l10n.localBridgeDownloadError,
      LocalBridgeSetupFailure.verificationFailed => l10n.localBridgeVerifyError,
      LocalBridgeSetupFailure.startupFailed => l10n.localBridgeStartupError,
      LocalBridgeSetupFailure.authorizationFailed => l10n.localBridgeAuthError,
      LocalBridgeSetupFailure.unsupportedPlatform =>
        l10n.localBridgeUnsupportedError,
      LocalBridgeSetupFailure.busy => l10n.localBridgeBusyError,
      LocalBridgeSetupFailure.installFailed => l10n.localBridgeInstallError,
      null => null,
    };
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.tileY),
      padding: const EdgeInsets.all(AppSpacing.tileX),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.localBridgeTitle,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.compact),
          Text(l10n.localBridgeBody),
          const SizedBox(height: AppSpacing.tileY),
          FilledButton.icon(
            key: const Key('install-local-bridge'),
            onPressed: progress == null ? onInstall : null,
            icon: const Icon(Icons.download_rounded),
            label: Text(status),
          ),
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.compact),
            LinearProgressIndicator(value: progress!.fraction),
            if (progress!.fraction != null)
              Text('${(progress!.fraction! * 100).round()}%',
                  textAlign: TextAlign.end),
          ],
          if (error != null) ...[
            const SizedBox(height: AppSpacing.compact),
            Text(error,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (onContinueWithAgent != null)
              OutlinedButton.icon(
                key: const Key('continue-bridge-with-agent'),
                onPressed: progress == null ? onContinueWithAgent : null,
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: Text(l10n.bridgeAgentContinue),
              ),
          ],
        ],
      ),
    );
  }
}
