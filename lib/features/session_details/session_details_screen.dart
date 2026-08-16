import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/providers.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/utils/duration_format.dart';
import '../../shared/widgets/state_views.dart';
import '../sessions/thinking_session.dart';

final _sessionDetailsProvider = FutureProvider.family<ThinkingSession?, String>(
  (ref, id) => ref.watch(sessionRepositoryProvider).getById(id),
);

/// Date/duration plus playback of the saved audio. Sections for
/// transcript/summary/ideas simply don't render when empty rather than
/// showing empty placeholders, per docs/mvp-scope.md.
class SessionDetailsScreen extends ConsumerWidget {
  final String sessionId;

  const SessionDetailsScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(_sessionDetailsProvider(sessionId));

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
          return _SessionDetailsBody(session: session);
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

class _SessionDetailsBody extends StatefulWidget {
  final ThinkingSession session;
  const _SessionDetailsBody({required this.session});

  @override
  State<_SessionDetailsBody> createState() => _SessionDetailsBodyState();
}

class _SessionDetailsBodyState extends State<_SessionDetailsBody> {
  AudioPlayer? _player;
  String? _playerError;

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
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final dateFormat = DateFormat('EEEE, MMM d, y · h:mm a');

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(dateFormat.format(session.startedAt), style: theme.textTheme.bodyMedium),
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
        // Transcript/summary/ideas/etc. don't exist in Phase 1 — sections
        // for them simply don't render, per docs/mvp-scope.md.
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
