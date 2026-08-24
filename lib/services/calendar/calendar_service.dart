/// A single event to create, chosen and timed by the user — never
/// created without their explicit action, per CLAUDE.md's Phase 2 rules
/// on Calendar/Notion writes.
class PlannedCalendarEvent {
  final String title;
  final DateTime start;
  final DateTime end;

  const PlannedCalendarEvent({
    required this.title,
    required this.start,
    required this.end,
  });
}

class CalendarEventCreationFailure {
  final PlannedCalendarEvent event;
  final Object error;

  const CalendarEventCreationFailure(this.event, this.error);
}

class CalendarEventCreationSummary {
  final int succeeded;
  final List<CalendarEventCreationFailure> failures;

  const CalendarEventCreationSummary({
    required this.succeeded,
    required this.failures,
  });

  bool get allSucceeded => failures.isEmpty;
}

/// Google Calendar integration (Phase B). Never called silently — every
/// call to [createEvents] corresponds to an explicit user confirmation
/// in the UI, per CLAUDE.md.
abstract class CalendarService {
  Future<bool> isSignedIn();

  /// Triggers the interactive Google sign-in flow. Throws on failure or
  /// cancellation.
  Future<void> signIn();

  Future<void> signOut();

  /// Creates every event in [events], continuing past individual
  /// failures rather than aborting the whole batch — the summary reports
  /// exactly what succeeded and what didn't.
  Future<CalendarEventCreationSummary> createEvents(
    List<PlannedCalendarEvent> events,
  );
}
