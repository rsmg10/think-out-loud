import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_spacing.dart';
import '../../services/audio/audio_monitoring_service.dart';
import '../../services/audio/audio_route.dart';
import '../history/history_screen.dart';
import '../patterns/patterns_screen.dart';
import '../settings/settings_screen.dart';
import 'active_thinking_screen.dart';
import 'session_complete_screen.dart';
import 'thinking_state.dart';
import 'widgets/think_button.dart';
import '../../core/providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Recovery after a prior mic-permission denial: if the user granted
    // it from system Settings and returned, retry silently — per
    // docs/audio-architecture.md, this must work without an app restart.
    final current = ref.read(thinkingControllerProvider);
    if (current.error?.type == AudioEngineErrorType.permissionDenied) {
      ref.read(thinkingControllerProvider.notifier).start();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(thinkingControllerProvider, _onStateChanged);
    final state = ref.watch(thinkingControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Think Out Loud'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_outlined),
            tooltip: 'History',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            tooltip: 'Patterns',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PatternsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: state.error != null
              ? _ErrorContent(
                  error: state.error!,
                  onRetry: () =>
                      ref.read(thinkingControllerProvider.notifier).start(),
                )
              : _IdleContent(
                  loading: state.phase == ThinkingPhase.starting,
                  connectingBluetooth:
                      state.phase == ThinkingPhase.starting &&
                      state.route == AudioRoute.bluetooth &&
                      state.useBluetoothMic,
                  onThink: () =>
                      ref.read(thinkingControllerProvider.notifier).start(),
                ),
        ),
      ),
    );
  }

  void _onStateChanged(ThinkingUiState? previous, ThinkingUiState next) {
    final wasActive =
        previous?.phase == ThinkingPhase.thinking ||
        previous?.phase == ThinkingPhase.starting ||
        previous?.phase == ThinkingPhase.interrupted ||
        previous?.phase == ThinkingPhase.stopping;

    if (next.phase == ThinkingPhase.thinking &&
        previous?.phase != ThinkingPhase.thinking &&
        previous?.phase != ThinkingPhase.interrupted) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ActiveThinkingScreen()));
    }
    if (next.phase == ThinkingPhase.saved &&
        previous?.phase != ThinkingPhase.saved) {
      if (wasActive) {
        Navigator.of(context).pop();
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SessionCompleteScreen(session: next.savedSession!),
        ),
      );
    }
    if (next.phase == ThinkingPhase.idle &&
        wasActive &&
        next.error == null) {
      // Interruption was cancelled from the Active screen.
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}

class _IdleContent extends StatelessWidget {
  final bool loading;
  final bool connectingBluetooth;
  final VoidCallback onThink;

  const _IdleContent({
    required this.loading,
    required this.connectingBluetooth,
    required this.onThink,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ThinkButton(onPressed: loading ? null : onThink, loading: loading),
          const SizedBox(height: AppSpacing.xl),
          Text(
            connectingBluetooth
                ? 'Connecting to your headphones…'
                : 'Press Think, put your headphones on,\nand hear yourself think.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ErrorContent extends StatelessWidget {
  final AudioEngineException error;
  final VoidCallback onRetry;

  const _ErrorContent({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, message, primaryAction) = switch (error.type) {
      AudioEngineErrorType.permissionDenied => (
        Icons.mic_off_outlined,
        'Microphone access needed',
        "Think Out Loud needs your microphone to work. Grant access in "
            "Settings, then come back here.",
        _Action('Open Settings', openAppSettings),
      ),
      AudioEngineErrorType.noSafeRoute => (
        Icons.headset_off_outlined,
        'Headphones needed',
        'Monitoring through the speaker would cause feedback. Plug in '
            'headphones and try again.',
        _Action('Try again', onRetry),
      ),
      AudioEngineErrorType.storageFailure => (
        Icons.sd_storage_outlined,
        'Storage problem',
        error.message,
        _Action('Try again', onRetry),
      ),
      AudioEngineErrorType.unsupportedPlatform => (
        Icons.error_outline,
        'Not supported here',
        'This platform does not have a native audio engine implemented.',
        null,
      ),
      AudioEngineErrorType.engineFailure => (
        Icons.error_outline,
        'Something went wrong',
        error.message,
        _Action('Try again', onRetry),
      ),
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.error),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (primaryAction != null) ...[
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: primaryAction.onPressed,
              child: Text(primaryAction.label),
            ),
          ],
        ],
      ),
    );
  }
}

class _Action {
  final String label;
  final VoidCallback onPressed;
  _Action(this.label, this.onPressed);
}
