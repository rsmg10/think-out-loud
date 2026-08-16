import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_spacing.dart';
import '../../services/audio/audio_route.dart';
import '../../shared/utils/duration_format.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AudioRoute? _route;
  int? _bytesUsed;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final route = await ref.read(audioMonitoringServiceProvider).currentRoute();
    final bytes = await ref.read(audioFileStorageProvider).totalBytes();
    if (!mounted) return;
    setState(() {
      _route = route;
      _bytesUsed = bytes;
    });
  }

  String _routeLabel(AudioRoute? route) => switch (route) {
    AudioRoute.headphones => 'Wired headphones',
    AudioRoute.bluetooth => 'Bluetooth headphones',
    AudioRoute.speaker => 'Speaker (monitoring unsafe)',
    AudioRoute.unknown || null => 'Unknown',
  };

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all sessions?'),
        content: const Text(
          'This permanently deletes every saved session and its audio. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await ref.read(sessionRepositoryProvider).deleteAll();
      await ref.read(audioFileStorageProvider).deleteAll();
      ref.read(sessionListRefreshProvider.notifier).state++;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('All sessions deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete all data: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preferBluetoothMic = ref.watch(preferBluetoothMicProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Audio', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.headset_outlined),
            title: const Text('Current route'),
            subtitle: Text(_routeLabel(_route)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Use headphones' microphone"),
            subtitle: const Text(
              'On: works hands-free, but Bluetooth audio quality and '
              'latency are noticeably worse — a limit of the Bluetooth '
              'link itself, not this app. Off: uses your phone\'s '
              'microphone instead (keep it within earshot), with '
              "clearer, faster audio through your headphones' speakers.",
            ),
            value: preferBluetoothMic,
            onChanged: (value) => ref
                .read(preferBluetoothMicProvider.notifier)
                .setPreferBluetoothMic(value),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sd_storage_outlined),
            title: const Text('Storage used'),
            subtitle: Text(_bytesUsed == null ? '…' : formatBytes(_bytesUsed!)),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.lg),
          Text('Privacy', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Everything you record stays on this device. Nothing is '
            'uploaded, and no AI processing runs on your sessions in this '
            'version of the app. The live thinking audio never leaves '
            'your device, even temporarily.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: _deleting ? null : _deleteAll,
            icon: _deleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever_outlined),
            label: const Text('Delete all data'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
