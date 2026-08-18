import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'transcription_service.dart';

/// Live, on-device transcription running alongside a thinking session,
/// via the platform's own speech recognizer (Android SpeechRecognizer /
/// iOS SFSpeechRecognizer, through the speech_to_text package).
///
/// Verified (Phase 2 plan, A0) to coexist with the native audio
/// monitoring engine's own mic tap on one Android device without either
/// side losing signal — not yet confirmed on iOS or other Android OEMs.
///
/// The platform recognizer doesn't reliably keep listening for an entire
/// multi-minute session — it can time out after a pause or a fixed
/// duration depending on OS/OEM — so this restarts listening
/// automatically underneath and stitches the segments together into one
/// transcript.
class OnDeviceTranscriptionService implements TranscriptionService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;
  bool _active = false;
  final List<String> _segments = [];
  String _currentSegment = '';

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onStatus: _onStatus,
      onError: (_) {},
    );
    return _initialized;
  }

  void _onStatus(String status) {
    if (!_active) return;
    if (status == 'done' || status == 'notListening') {
      _commitCurrentSegment();
      _listenOnce();
    }
  }

  void _commitCurrentSegment() {
    final text = _currentSegment.trim();
    if (text.isNotEmpty) {
      _segments.add(text);
    }
    _currentSegment = '';
  }

  Future<void> _listenOnce() async {
    if (!_active || _speech.isListening) return;
    await _speech.listen(
      onResult: (result) => _currentSegment = result.recognizedWords,
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(minutes: 10),
        pauseFor: const Duration(seconds: 8),
        partialResults: true,
        // Honors the "start on-device" choice explicitly rather than
        // silently falling back to a network recognizer.
        onDevice: true,
      ),
    );
  }

  @override
  Future<void> startLiveTranscription() async {
    final available = await _ensureInitialized();
    if (!available) return;
    _active = true;
    _segments.clear();
    _currentSegment = '';
    await _listenOnce();
  }

  @override
  Future<String?> stopLiveTranscription() async {
    _active = false;
    if (_speech.isListening) {
      await _speech.stop();
    }
    _commitCurrentSegment();
    if (_segments.isEmpty) return null;
    return _segments.join(' ');
  }
}
