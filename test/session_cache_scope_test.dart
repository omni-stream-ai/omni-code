import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/widgets/session_cache_scope.dart';

void main() {
  testWidgets('cache changes rebuild only dependent content', (tester) async {
    final revision = ValueNotifier<int>(0);
    var shellBuilds = 0;
    var dependentBuilds = 0;

    await tester.pumpWidget(
      _ShellCounter(
        onBuild: () => shellBuilds++,
        child: SessionCacheScope(
          notifier: revision,
          child: Builder(
            builder: (context) {
              SessionCacheScope.watch(context);
              dependentBuilds++;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(shellBuilds, 1);
    expect(dependentBuilds, 1);

    revision.value++;
    await tester.pump();

    expect(shellBuilds, 1);
    expect(dependentBuilds, 2);
  });
}

class _ShellCounter extends StatelessWidget {
  const _ShellCounter({required this.onBuild, required this.child});

  final VoidCallback onBuild;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );
  }
}
