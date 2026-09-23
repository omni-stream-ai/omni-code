import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge_client.dart';
import '../models.dart';

/// The API client is injectable so tests and alternate bridge configurations
/// can override it without making widgets own request state.
final bridgeClientProvider = Provider<BridgeClient>((ref) => bridgeClient);

final projectsProvider = FutureProvider.autoDispose<List<ProjectSummary>>((ref) {
  return ref.watch(bridgeClientProvider).listProjects(forceRefresh: true);
});

final sessionsProvider = FutureProvider.autoDispose
    .family<List<SessionSummary>, String?>((ref, projectId) {
  return ref
      .watch(bridgeClientProvider)
      .listDomainSessions(projectId: projectId, forceRefresh: true);
});

final projectProvider = FutureProvider.autoDispose
    .family<ProjectSummary, String>((ref, projectId) {
  return ref.watch(projectsProvider.future).then((projects) {
    return projects.firstWhere(
      (project) => project.id == projectId,
      orElse: () => throw StateError('Project not found: $projectId'),
    );
  });
});

final sessionProvider = FutureProvider.autoDispose
    .family<SessionSummary, ({String projectId, String sessionId})>(
        (ref, key) async {
  final sessions = await ref.watch(sessionsProvider(key.projectId).future);
  return sessions.firstWhere(
    (session) => session.id == key.sessionId,
    orElse: () => throw StateError('Session not found: ${key.sessionId}'),
  );
});

final agentsProvider = FutureProvider.autoDispose<List<AgentSummary>>((ref) {
  return ref.watch(bridgeClientProvider).listAgents(forceRefresh: true);
});

final modelProvidersProvider =
    FutureProvider.autoDispose<List<ModelProviderConfig>>((ref) {
  return ref.watch(bridgeClientProvider).getModelProviders();
});

final piPluginsProvider = FutureProvider.autoDispose
    .family<List<PiPlugin>, String?>((ref, projectId) {
  return ref.watch(bridgeClientProvider).getPiPlugins(projectId: projectId);
});

/// Invalidates all read-side API state after a mutation or authentication
/// change. Callers do not need to know which in-memory cache to update.
void invalidateBridgeReadState(Ref ref) {
  ref.invalidate(projectsProvider);
  ref.invalidate(sessionsProvider);
  ref.invalidate(agentsProvider);
}
