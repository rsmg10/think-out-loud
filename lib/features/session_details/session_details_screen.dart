import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/providers.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/utils/duration_format.dart';
import '../../shared/widgets/state_views.dart';
import '../scheduling/schedule_action_points_screen.dart';
import '../sessions/thinking_session.dart';

final _sessionDetailsProvider = FutureProvider.family<ThinkingSession?, String>(
  (ref, id) => ref.watch(sessionRepositoryProvider).getById(id),
);

/// Date/duration plus playback of the saved audio, and (Phase 2) the
/// transcript and Gemini reflection results. Sections for transcript/
/// summary/ideas simply don't render when empty rather than showing
/// empty placeholders, per docs/mvp-scope.md — that rule now covers "not
/// yet processed" and "processing failed" too, not just "doesn't exist
/// yet".
class SessionDetailsScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const SessionDetailsScreen({super.key, required this.sessionId});

  @override
  ConsumerState<SessionDetailsScreen> createState() =>
      _SessionDetailsScreenState();
}

class _SessionDetailsScreenState extends ConsumerState<SessionDetailsScreen> {
  Timer? _pollTimer;

  // Reflection runs in the background (ThinkingController) and may still
  // be in flight when this screen opens. There's no push channel from
  // that background work back to a screen that might not even be
  // mounted, so this screen polls lightly while status is pending
  // instead — simpler than plumbing a stream through for something this
  // infrequent.
  void _maybeSchedulePoll(AiProcessingStatus? status) {
    final isProcessing = status == AiProcessingStatus.pending;
    if (isProcessing && _pollTimer == null) {
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        ref.invalidate(_sessionDetailsProvider(widget.sessionId));
      });
    } else if (!isProcessing && _pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _retryReflection(ThinkingSession session) async {
    final transcript = session.transcript;
    if (transcript == null || transcript.trim().isEmpty) return;
    final repository = ref.read(sessionRepositoryProvider);
    await repository.save(
      session.copyWith(status: AiProcessingStatus.pending),
    );
    ref.invalidate(_sessionDetailsProvider(widget.sessionId));
    final result = await ref.read(reflectionServiceProvider).reflect(transcript);
    final updated = result == null
        ? session.copyWith(status: AiProcessingStatus.failed)
        : session.copyWith(
            status: AiProcessingStatus.complete,
            summary: result.summary,
            keyIdeas: result.keyIdeas,
            actionPoints: result.actionPoints,
            actionPointsDone: const [],
            openQuestions: result.openQuestions,
            mood: result.mood,
          );
    await repository.save(updated);
    if (mounted) ref.invalidate(_sessionDetailsProvider(widget.sessionId));
  }

  Future<void> _toggleActionPoint(
    ThinkingSession session,
    int index,
    bool value,
  ) async {
    final done = List<bool>.generate(
      session.actionPoints.length,
      (i) =>
          i < session.actionPointsDone.length && session.actionPointsDone[i],
    );
    done[index] = value;
    await ref
        .read(sessionRepositoryProvider)
        .save(session.copyWith(actionPointsDone: done));
    if (mounted) ref.invalidate(_sessionDetailsProvider(widget.sessionId));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(_sessionDetailsProvider(widget.sessionId));
    sessionAsync.whenData((session) => _maybeSchedulePoll(session?.status));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session'),
        actions: [
          sessionAsync.maybeWhen(
            data: (session) => session == null
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete session',
                    onPressed: () => _confirmDelete(context, ref, session),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: sessionAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => StateView(
          icon: Icons.error_outline,
          title: 'Could not load session',
          message: '$error',
        ),
        data: (session) {
          if (session == null) {
            return const StateView(
              icon: Icons.search_off,
              title: 'Session not found',
              message: 'It may have already been deleted.',
            );
          }
          return _SessionDetailsBody(
            session: session,
            onRetryReflection: () => _retryReflection(session),
            onToggleActionPoint: (index, value) =>
                _toggleActionPoint(session, index, value),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ThinkingSession session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this session?'),
        content: const Text(
          'This removes the session and its audio recording. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(sessionRepositoryProvider).delete(session.id);
      if (session.audioReference != null) {
        await ref
            .read(audioFileStorageProvider)
            .delete(session.audioReference!);
      }
      ref.read(sessionListRefreshProvider.notifier).state++;
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete session: $e')));
      }
    }
  }
}

void _copyToClipboard(BuildContext context, String label, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$label copied')));
}

/// Fixed vocabulary only (see GeminiReflectionService's prompt) — anything
/// else (including null, e.g. before reflection has run) falls back to a
/// neutral dot rather than guessing at an icon for an unknown word.
const _moodIcons = <String, IconData>{
  'calm': Icons.self_improvement_outlined,
  'anxious': Icons.bolt_outlined,
  'energized': Icons.flash_on_outlined,
  'frustrated': Icons.sentiment_dissatisfied_outlined,
  'hopeful': Icons.wb_sunny_outlined,
};

IconData _moodIcon(String? mood) => _moodIcons[mood] ?? Icons.circle_outlined;

class _SessionDetailsBody extends StatefulWidget {
  final ThinkingSession session;
  final VoidCallback onRetryReflection;
  final void Function(int index, bool value) onToggleActionPoint;

  const _SessionDetailsBody({
    required this.session,
    required this.onRetryReflection,
    required this.onToggleActionPoint,
  });

  @override
  State<_SessionDetailsBody> createState() => _SessionDetailsBodyState();
}

class _SessionDetailsBodyState extends State<_SessionDetailsBody> {
  AudioPlayer? _player;
  String? _playerError;
  late List<bool> _actionPointsDone;

  @override
  void initState() {
    super.initState();
    final path = widget.session.audioReference;
    if (path != null) {
      final player = AudioPlayer();
      _player = player;
      player.setFilePath(path).catchError((Object e) {
        setState(() => _playerError = '$e');
        return null;
      });
    }
    _actionPointsDone = List<bool>.generate(
      widget.session.actionPoints.length,
      (i) => i < widget.session.actionPointsDone.length
          ? widget.session.actionPointsDone[i]
          : false,
    );
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  /// 40ms-per-section stagger step (Summary, then Key ideas, then Action
  /// points, then Open questions) — not part of AppMotion since it's a
  /// one-off offset rather than a reusable rhythm.
  static const _staggerStep = Duration(milliseconds: 40);

  /// Fade-in-and-rise entrance, once, for a completed reflection section.
  /// Keyed by session id + [index] and driven off a fixed 0->1 tween so a
  /// rebuild that doesn't change the tween's begin/end (poll tick, a
  /// checkbox toggle) leaves it sitting at its already-reached end value
  /// instead of restarting — see TweenAnimationBuilder's semantics.
  ///
  /// The stagger is a genuine delayed start, not just a slower reveal: an
  /// [Interval] curve holds the tween at 0 for the delay portion of the
  /// total duration, then eases in over AppMotion.medium — all sections
  /// finish revealing AppMotion.medium after they individually start.
  Widget _revealSection(
    BuildContext context, {
    required int index,
    required Widget child,
  }) {
    if (widget.session.status != AiProcessingStatus.complete ||
        MediaQuery.of(context).disableAnimations) {
      return child;
    }
    final delay = _staggerStep * index;
    final total = AppMotion.medium + delay;
    final delayFraction = delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      key: ValueKey('reveal_${widget.session.id}_$index'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: total,
      curve: Interval(delayFraction, 1.0, curve: AppMotion.enter),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * AppSpacing.sm),
          child: child,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final dateFormat = DateFormat('EEEE, MMM d, y · h:mm a');

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            Icon(
              _moodIcon(session.mood),
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              dateFormat.format(session.startedAt),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          formatDurationWords(session.duration),
          style: theme.textTheme.displayMedium,
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_player != null) _PlaybackControls(player: _player!, error: _playerError)
        else
          Text(
            'No audio was saved for this session.',
            style: theme.textTheme.bodyMedium,
          ),
        if (session.status == AiProcessingStatus.pending) ...[
          const SizedBox(height: AppSpacing.xl),
          const _ReflectionSkeleton(key: Key('reflection_skeleton')),
        ],
        if (session.status == AiProcessingStatus.failed) ...[
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Reflection failed.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.onRetryReflection,
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
        if (session.summary != null && session.summary!.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          _revealSection(
            context,
            index: 0,
            child: _Section(
              title: 'Summary',
              trailing: IconButton(
                icon: const Icon(Icons.copy_outlined, size: 20),
                tooltip: 'Copy summary',
                onPressed: () =>
                    _copyToClipboard(context, 'Summary', session.summary!),
              ),
              child: Text(session.summary!),
            ),
          ),
        ],
        if (session.keyIdeas.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _revealSection(
            context,
            index: 1,
            child: _Section(
              title: 'Key ideas',
              child: _BulletList(items: session.keyIdeas),
            ),
          ),
        ],
        if (session.actionPoints.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _revealSection(
            context,
            index: 2,
            child: _Section(
              title: 'Action points',
              child: _ActionPointsChecklist(
                items: session.actionPoints,
                done: _actionPointsDone,
                onChanged: (index, value) {
                  setState(() => _actionPointsDone[index] = value);
                  widget.onToggleActionPoint(index, value);
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ScheduleActionPointsScreen(
                  actionPoints: session.actionPoints,
                ),
              ),
            ),
            icon: const Icon(Icons.event_outlined),
            label: const Text('Schedule with Google Calendar'),
          ),
        ],
        if (session.openQuestions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _revealSection(
            context,
            index: 3,
            child: _Section(
              title: 'Open questions',
              child: _BulletList(
                items: session.openQuestions,
                icon: Icons.help_outline,
              ),
            ),
          ),
        ],
        if (session.transcript != null && session.transcript!.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Transcript',
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 20),
                    tooltip: 'Copy transcript',
                    onPressed: () => _copyToClipboard(
                      context,
                      'Transcript',
                      session.transcript!,
                    ),
                  ),
                ],
              ),
              childrenPadding: const EdgeInsets.only(top: AppSpacing.sm),
              expandedAlignment: Alignment.centerLeft,
              children: [Text(session.transcript!, style: theme.textTheme.bodyMedium)],
            ),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Section({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.headlineMedium)),
            ?trailing,
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

/// Placeholder shown while reflection is pending, in place of where the
/// Summary/Key ideas/Action points text will land — a pulsing set of bars
/// rather than a spinner, so the wait reads as "content is forming" (per
/// the AI-generation-wait pattern in current journaling apps) instead of
/// an indeterminate stall.
class _ReflectionSkeleton extends StatefulWidget {
  const _ReflectionSkeleton({super.key});

  @override
  State<_ReflectionSkeleton> createState() => _ReflectionSkeletonState();
}

class _ReflectionSkeletonState extends State<_ReflectionSkeleton> {
  static const _dim = 0.4;
  static const _bright = 1.0;

  double _opacity = _bright;
  Timer? _timer;
  bool _timerDecided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timerDecided) return;
    _timerDecided = true;
    if (!MediaQuery.of(context).disableAnimations) {
      _timer = Timer.periodic(AppMotion.slow, (_) {
        setState(() => _opacity = _opacity == _bright ? _dim : _bright);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    Widget bar(double widthFactor) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSpacing.xs),
        ),
      ),
    );
    final bars = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar(0.95),
        const SizedBox(height: AppSpacing.sm),
        bar(0.7),
        const SizedBox(height: AppSpacing.sm),
        bar(0.85),
        const SizedBox(height: AppSpacing.sm),
        bar(0.5),
      ],
    );
    if (_timer == null) return bars;
    return AnimatedOpacity(
      opacity: _opacity,
      duration: AppMotion.slow,
      child: bars,
    );
  }
}

class _BulletList extends StatelessWidget {
  final List<String> items;
  final IconData icon;

  const _BulletList({required this.items, this.icon = Icons.circle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(icon, size: 14, color: theme.colorScheme.primary),
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

/// Interactive, persisted checklist — unlike [_BulletList] (used for key
/// ideas/open questions, which are read-only), each action point can be
/// checked off. Rendering is purely a function of [done]; persistence is
/// the caller's job via [onChanged].
class _ActionPointsChecklist extends StatelessWidget {
  final List<String> items;
  final List<bool> done;
  final void Function(int index, bool value) onChanged;

  const _ActionPointsChecklist({
    required this.items,
    required this.done,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: i < done.length && done[i],
                    onChanged: (value) => onChanged(i, value ?? false),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: AnimatedDefaultTextStyle(
                      duration: AppMotion.fast,
                      style:
                          (i < done.length && done[i])
                              ? theme.textTheme.bodyMedium?.copyWith(
                                  decoration: TextDecoration.lineThrough,
                                  color: theme.textTheme.bodySmall?.color,
                                ) ??
                                  const TextStyle()
                          : theme.textTheme.bodyMedium ?? const TextStyle(),
                      child: Text(items[i]),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  final AudioPlayer player;
  final String? error;

  const _PlaybackControls({required this.player, required this.error});

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return StateView(
        icon: Icons.error_outline,
        title: 'Could not load audio',
        message: error!,
      );
    }
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, durationSnap) {
        final total = durationSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, positionSnap) {
            final position = positionSnap.data ?? Duration.zero;
            return Column(
              children: [
                Slider(
                  value: position.inMilliseconds
                      .clamp(0, total.inMilliseconds == 0 ? 1 : total.inMilliseconds)
                      .toDouble(),
                  max: total.inMilliseconds == 0 ? 1 : total.inMilliseconds.toDouble(),
                  onChanged: total.inMilliseconds == 0
                      ? null
                      : (value) =>
                            player.seek(Duration(milliseconds: value.round())),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatElapsed(position)),
                    StreamBuilder<PlayerState>(
                      stream: player.playerStateStream,
                      builder: (context, stateSnap) {
                        final playing = stateSnap.data?.playing ?? false;
                        return IconButton(
                          iconSize: 40,
                          tooltip: playing ? 'Pause' : 'Play',
                          icon: Icon(
                            playing
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                          ),
                          onPressed: () =>
                              playing ? player.pause() : player.play(),
                        );
                      },
                    ),
                    Text(formatElapsed(total)),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}
