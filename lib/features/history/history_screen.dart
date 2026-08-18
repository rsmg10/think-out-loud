import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/utils/duration_format.dart';
import '../../shared/widgets/state_views.dart';
import '../session_details/session_details_screen.dart';

/// Reverse-chronological list, date, duration, and either the real
/// summary (Phase 2 — once reflection has actually completed for that
/// session) or an auto-generated placeholder label. Never a fake preview
/// implying processing happened when it hasn't, per docs/mvp-scope.md.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: sessionsAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => StateView(
          icon: Icons.error_outline,
          title: 'Could not load history',
          message: '$error',
          action: TextButton(
            onPressed: () => ref.invalidate(sessionListProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return const StateView(
              icon: Icons.self_improvement_outlined,
              title: 'Nothing yet',
              message: 'Sessions you finish will show up here.',
            );
          }
          final dateFormat = DateFormat('EEE, MMM d');
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final session = sessions[index];
              final hasSummary = session.summary != null &&
                  session.summary!.trim().isNotEmpty;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                title: Text(
                  hasSummary ? session.summary! : session.placeholderLabel,
                  maxLines: hasSummary ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${dateFormat.format(session.startedAt)} · '
                  '${formatDurationWords(session.duration)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SessionDetailsScreen(sessionId: session.id),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
