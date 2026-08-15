import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_spacing.dart';
import '../../services/audio/audio_monitoring_service.dart';
import '../../shared/utils/duration_format.dart';
import 'thinking_state.dart';
import 'widgets/waveform_visualizer.dart';

/// Status, elapsed time, subtle waveform, Stop — nothing else. Should
/// work with the phone in a pocket, per docs/mvp-scope.md.
class ActiveThinkingScreen extends ConsumerWidget {
  const ActiveThinkingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(thinkingControllerProvider);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                const Spacer(),
                Semantics(
                  liveRegion: true,
                  label: state.phase == ThinkingPhase.interrupted
                      ? 'Thinking paused'
                      : 'Thinking',
                  child: Text(
                    state.phase == ThinkingPhase.interrupted
                        ? 'Paused'
                        : 'Thinking…',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  formatElapsed(state.elapsed),
                  style: theme.textTheme.displayLarge,
                ),
                const SizedBox(height: AppSpacing.xl),
                WaveformVisualizer(
                  level: state.phase == ThinkingPhase.thinking
                      ? state.level
                      : 0.0,
                ),
                const Spacer(),
                if (state.phase == ThinkingPhase.interrupted)
                  _InterruptedControls(reason: state.interruptionReason)
                else
                  _StopControl(
                    disabled: state.phase == ThinkingPhase.stopping,
                  ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StopControl extends ConsumerWidget {
  final bool disabled;
  const _StopControl({required this.disabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'Stop',
      hint: 'End the thinking session',
      child: ElevatedButton(
        onPressed: disabled
            ? null
            : () => ref.read(thinkingControllerProvider.notifier).stop(),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
        child: disabled
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text('Stop'),
      ),
    );
  }
}

class _InterruptedControls extends ConsumerWidget {
  final InterruptionReason? reason;
  const _InterruptedControls({required this.reason});

  String get _message => switch (reason) {
    InterruptionReason.bluetoothDisconnected =>
      'Your Bluetooth headphones disconnected.',
    InterruptionReason.routeBecameUnsafe =>
      'Headphones were disconnected — resuming would cause feedback '
          'through the speaker.',
    InterruptionReason.systemAudioInterruption =>
      'Another app interrupted audio.',
    null => 'Monitoring paused.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(thinkingControllerProvider.notifier);
    return Column(
      children: [
        Text(_message, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.md),
        ElevatedButton(
          onPressed: controller.resumeAfterInterruption,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
          ),
          child: const Text('Resume'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: controller.cancelFromInterruption,
          child: const Text('Discard session'),
        ),
      ],
    );
  }
}
