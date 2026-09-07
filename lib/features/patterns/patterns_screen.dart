import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/state_views.dart';

// autoDispose so leaving this screen drops the cached result — the next
// visit recomputes rather than showing a stale answer from an earlier
// point in the user's session history, matching the class doc below.
final _recurringThemesProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(memoryServiceProvider).recurringThemes(),
);

/// Cross-session theme detection — surfaces what someone keeps coming
/// back to across their recent sessions, per the Phase 2 market-research
/// direction. Recomputed on demand each time this screen opens rather than
/// persisted, since GeminiMemoryService.record() is a no-op.
class PatternsScreen extends ConsumerWidget {
  const PatternsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themesAsync = ref.watch(_recurringThemesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Patterns')),
      body: themesAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => StateView(
          icon: Icons.error_outline,
          title: 'Could not load patterns',
          message: '$error',
          action: TextButton(
            onPressed: () => ref.invalidate(_recurringThemesProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (themes) {
          if (themes.isEmpty) {
            return const StateView(
              icon: Icons.insights_outlined,
              title: 'Nothing yet',
              message:
                  'Not enough sessions yet to find patterns — check back '
                  'after a few more.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                'What you keep coming back to',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              _ThemeList(themes: themes),
            ],
          );
        },
      ),
    );
  }
}

class _ThemeList extends StatelessWidget {
  final List<String> themes;

  const _ThemeList({required this.themes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in themes)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Icon(
                    Icons.circle,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(item, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}
