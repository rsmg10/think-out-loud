import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/utils/duration_format.dart';
import '../../shared/widgets/state_views.dart';
import '../session_details/session_details_screen.dart';
import '../sessions/thinking_session.dart';

/// Reverse-chronological list, date, duration, and either the real
/// summary (Phase 2 — once reflection has actually completed for that
/// session) or an auto-generated placeholder label. Never a fake preview
/// implying processing happened when it hasn't, per docs/mvp-scope.md.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  bool _searching = false;
  String _query = '';
  final _searchController = TextEditingController();

  void _startSearch() {
    setState(() => _searching = true);
  }

  void _stopSearch() {
    _searchController.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(ThinkingSession session, String query) {
    final q = query.toLowerCase();
    return (session.summary?.toLowerCase().contains(q) ?? false) ||
        (session.transcript?.toLowerCase().contains(q) ?? false) ||
        session.placeholderLabel.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(sessionListProvider);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search sessions…',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : const Text('History'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: _searching ? 'Close search' : 'Search sessions',
            onPressed: _searching ? _stopSearch : _startSearch,
          ),
        ],
      ),
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
          final query = _query.trim();
          final visible = query.isEmpty
              ? sessions
              : sessions.where((s) => _matches(s, query)).toList();
          if (visible.isEmpty) {
            return StateView(
              icon: Icons.search_off,
              title: 'No matches',
              message: "No sessions match '$query'",
            );
          }
          final dateFormat = DateFormat('EEE, MMM d');
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final session = visible[index];
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
