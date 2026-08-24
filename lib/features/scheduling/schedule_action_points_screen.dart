import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_spacing.dart';
import '../../services/calendar/calendar_service.dart';

class _PlannableItem {
  final String title;
  bool selected = true;
  DateTime start;
  final Duration duration = const Duration(minutes: 30);

  _PlannableItem({required this.title, required this.start});

  DateTime get end => start.add(duration);
}

/// Turns a session's extracted action points into Google Calendar events —
/// but only the ones the user picks, and only after they tap the create
/// button naming exactly how many events will be made. Never silent, per
/// CLAUDE.md's Phase 2 rules on Calendar writes.
class ScheduleActionPointsScreen extends ConsumerStatefulWidget {
  final List<String> actionPoints;

  const ScheduleActionPointsScreen({super.key, required this.actionPoints});

  @override
  ConsumerState<ScheduleActionPointsScreen> createState() =>
      _ScheduleActionPointsScreenState();
}

class _ScheduleActionPointsScreenState
    extends ConsumerState<ScheduleActionPointsScreen> {
  late final List<_PlannableItem> _items;
  bool? _signedIn;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final tomorrow9am = DateTime.now()
        .add(const Duration(days: 1))
        .copyWith(hour: 9, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    _items = [
      for (var i = 0; i < widget.actionPoints.length; i++)
        _PlannableItem(
          title: widget.actionPoints[i],
          start: tomorrow9am.add(Duration(minutes: 30 * i)),
        ),
    ];
    _checkSignIn();
  }

  Future<void> _checkSignIn() async {
    final signedIn = await ref.read(calendarServiceProvider).isSignedIn();
    if (mounted) setState(() => _signedIn = signedIn);
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      await ref.read(calendarServiceProvider).signIn();
      if (mounted) setState(() => _signedIn = true);
    } catch (e) {
      _showError('Could not sign in: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDateTime(_PlannableItem item) async {
    final date = await showDatePicker(
      context: context,
      initialDate: item.start,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(item.start),
    );
    if (time == null) return;
    setState(() {
      item.start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _createEvents() async {
    final selected = _items.where((i) => i.selected).toList();
    if (selected.isEmpty) return;

    setState(() => _busy = true);
    try {
      final summary = await ref.read(calendarServiceProvider).createEvents([
        for (final item in selected)
          PlannedCalendarEvent(
            title: item.title,
            start: item.start,
            end: item.end,
          ),
      ]);
      if (!mounted) return;
      if (summary.allSucceeded) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created ${summary.succeeded} calendar event(s).'),
          ),
        );
      } else {
        _showError(
          '${summary.succeeded} created, ${summary.failures.length} failed. '
          'Try again for the ones that failed.',
        );
      }
    } catch (e) {
      _showError('Could not create events: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCount = _items.where((i) => i.selected).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule action points')),
      body: _signedIn == null
          ? const Center(child: CircularProgressIndicator())
          : _signedIn == false
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Connect Google Calendar to schedule these.',
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ElevatedButton(
                      onPressed: _busy ? null : _signIn,
                      child: const Text('Sign in with Google'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                for (final item in _items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: item.selected,
                            onChanged: (v) =>
                                setState(() => item.selected = v ?? false),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(item.title),
                                ),
                                TextButton.icon(
                                  onPressed: () => _pickDateTime(item),
                                  icon: const Icon(Icons.schedule, size: 16),
                                  label: Text(_formatWhen(item.start)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: _signedIn == true
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ElevatedButton(
                  onPressed: (_busy || selectedCount == 0)
                      ? null
                      : _createEvents,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          selectedCount == 0
                              ? 'Select at least one'
                              : 'Create $selectedCount calendar event${selectedCount == 1 ? '' : 's'}',
                        ),
                ),
              ),
            )
          : null,
    );
  }

  String _formatWhen(DateTime dt) {
    final now = DateTime.now();
    final day = dt.year == now.year && dt.month == now.month && dt.day == now.day + 1
        ? 'Tomorrow'
        : '${dt.month}/${dt.day}';
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$day, $hour:${dt.minute.toString().padLeft(2, '0')} $period';
  }
}
