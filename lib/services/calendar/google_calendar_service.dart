import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:http/http.dart' as http;

import 'calendar_service.dart';
import 'google_calendar_config.dart';

class _AuthorizedClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _AuthorizedClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class CalendarAuthException implements Exception {
  final String message;
  const CalendarAuthException(this.message);

  @override
  String toString() => 'CalendarAuthException($message)';
}

/// Wraps google_sign_in + googleapis's CalendarApi. Every event this
/// creates traces back to an explicit user confirmation in the
/// scheduling UI — this service never runs on its own.
class GoogleCalendarService implements CalendarService {
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: GoogleCalendarConfig.serverClientId,
    );
    _initialized = true;
  }

  @override
  Future<bool> isSignedIn() async {
    await _ensureInitialized();
    try {
      final account = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
      return account != null;
    } on GoogleSignInException {
      return false;
    }
  }

  @override
  Future<void> signIn() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.authenticate();
  }

  @override
  Future<void> signOut() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.signOut();
  }

  Future<GoogleSignInAccount> _currentAccountOrThrow() async {
    final account =
        await GoogleSignIn.instance.attemptLightweightAuthentication() ??
        await GoogleSignIn.instance.authenticate();
    return account;
  }

  @override
  Future<CalendarEventCreationSummary> createEvents(
    List<PlannedCalendarEvent> events,
  ) async {
    await _ensureInitialized();
    final account = await _currentAccountOrThrow();
    final headers = await account.authorizationClient.authorizationHeaders(
      GoogleCalendarConfig.scopes,
      promptIfNecessary: true,
    );
    if (headers == null) {
      throw const CalendarAuthException(
        'Google did not grant calendar access.',
      );
    }

    final client = _AuthorizedClient(headers);
    try {
      final api = calendar.CalendarApi(client);
      var succeeded = 0;
      final failures = <CalendarEventCreationFailure>[];
      for (final planned in events) {
        try {
          await api.events.insert(
            calendar.Event(
              summary: planned.title,
              start: calendar.EventDateTime(dateTime: planned.start.toUtc()),
              end: calendar.EventDateTime(dateTime: planned.end.toUtc()),
            ),
            'primary',
          );
          succeeded++;
        } catch (e) {
          failures.add(CalendarEventCreationFailure(planned, e));
        }
      }
      return CalendarEventCreationSummary(
        succeeded: succeeded,
        failures: failures,
      );
    } finally {
      client.close();
    }
  }
}
