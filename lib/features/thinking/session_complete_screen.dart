import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/utils/duration_format.dart';
import '../session_details/session_details_screen.dart';
import '../sessions/thinking_session.dart';

/// Calm, positive, shows duration — and hands off to Session Details,
/// where the reflection lands. Never shows fake AI results here: when a
/// transcript was captured the reflection is still in flight, so this
/// screen only says it's being prepared and links to where it'll appear.
class SessionCompleteScreen extends ConsumerWidget {
  final ThinkingSession session;

  const SessionCompleteScreen({super.key, required this.session});

  bool get _reflectionComing => session.status == AiProcessingStatus.pending;

  void _acknowledge(WidgetRef ref) {
    ref.read(thinkingControllerProvider.notifier).acknowledgeSaved();
    ref.read(sessionListRefreshProvider.notifier).state++;
  }

  void _done(BuildContext context, WidgetRef ref) {
    _acknowledge(ref);
    Navigator.of(context).pop();
  }

  void _openDetails(BuildContext context, WidgetRef ref) {
    _acknowledge(ref);
    // Replace rather than push, so Back from Details returns to Home
    // instead of this (already acknowledged) screen.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SessionDetailsScreen(sessionId: session.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hasAudio = session.audioReference != null;
    const buttonSize = Size(double.infinity, 56);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Session complete', style: theme.textTheme.displayMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'You thought out loud for ${formatDurationWords(session.duration)}.',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _reflectionComing
                    ? 'Your reflection is being prepared — a summary, key '
                          'ideas and next steps from what you said.'
                    : 'No speech was picked up this time, so there\'s '
                          'nothing to reflect on.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxl),
              if (_reflectionComing) ...[
                ElevatedButton(
                  onPressed: () => _openDetails(context, ref),
                  style: ElevatedButton.styleFrom(minimumSize: buttonSize),
                  child: const Text('See your reflection'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => _done(context, ref),
                  style: TextButton.styleFrom(minimumSize: buttonSize),
                  child: const Text('Done'),
                ),
              ] else ...[
                ElevatedButton(
                  onPressed: () => _done(context, ref),
                  style: ElevatedButton.styleFrom(minimumSize: buttonSize),
                  child: const Text('Done'),
                ),
                if (hasAudio) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => _openDetails(context, ref),
                    style: TextButton.styleFrom(minimumSize: buttonSize),
                    child: const Text('View session'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
