/// Fake ASR service implementation for web preview and testing.
///
/// Simulates word-by-word speech recognition by emitting the expected
/// words from the scope one at a time with realistic timing. This allows
/// the full recitation flow to be demonstrated without a real microphone
/// or on-device ASR model.
///
/// In production, this is replaced by StreamingAsrService (spec §4) which
/// uses onnxruntime directly with the FastConformer-CTC streaming model.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:quran_tasmee3_core/recitation/asr_service.dart';
import 'package:quran_tasmee3_core/recitation/matching_engine.dart';

/// A fake ASR service that simulates recognition by emitting scope words.
class FakeAsrServiceImpl implements AsrService {
  void Function(AsrResult)? _sink;
  Timer? _emitTimer;
  List<ExpectedWord> _scope = [];
  int _currentWordIndex = 0;
  bool _running = false;
  bool _paused = false;

  // Configurable behavior for demo realism
  final double _confidence;
  final Duration _wordDelay;

  FakeAsrServiceImpl({
    double confidence = 0.92,
    Duration wordDelay = const Duration(milliseconds: 1200),
  })  : _confidence = confidence,
        _wordDelay = wordDelay;

  /// Set the recitation scope so the fake knows what words to "recognize".
  void setScope(List<ExpectedWord> scope) {
    _scope = scope;
    _currentWordIndex = 0;
  }

  @override
  Future<void> start(void Function(AsrResult) onResult) async {
    _sink = onResult;
    _running = true;
    _paused = false;
    _startEmitting();
  }

  void _startEmitting() {
    _emitTimer?.cancel();
    _emitTimer = Timer.periodic(_wordDelay, (_) {
      if (!_running || _paused || _sink == null) return;
      if (_currentWordIndex >= _scope.length) {
        _emitTimer?.cancel();
        return;
      }

      // Emit the next word (or a small group of words for multi-word utterances)
      final word = _scope[_currentWordIndex];
      final text = word.display.isNotEmpty ? word.display : word.norm;

      // Sometimes emit 2-3 words at once (simulating natural speech rhythm)
      var emitText = text;
      if (_currentWordIndex + 1 < _scope.length &&
          _scope[_currentWordIndex].surah == _scope[_currentWordIndex + 1].surah &&
          _scope[_currentWordIndex].ayah == _scope[_currentWordIndex + 1].ayah) {
        emitText = '$text ${_scope[_currentWordIndex + 1].display}';
        if (_currentWordIndex + 2 < _scope.length &&
            _scope[_currentWordIndex].surah == _scope[_currentWordIndex + 2].surah &&
            _scope[_currentWordIndex].ayah == _scope[_currentWordIndex + 2].ayah) {
          emitText = '$emitText ${_scope[_currentWordIndex + 2].display}';
          _currentWordIndex += 3;
        } else {
          _currentWordIndex += 2;
        }
      } else {
        _currentWordIndex++;
      }

      dlog('[FakeASR] emitting: "$emitText" (conf=$_confidence)');
      _sink!(AsrResult(emitText, _confidence));
    });
  }

  @override
  Future<void> pause() async {
    _paused = true;
  }

  @override
  Future<void> resume() async {
    _paused = false;
  }

  @override
  Future<void> flush() async {
    // Reset the emission position to the scope start (simulates VAD flush)
    dlog('[FakeASR] flush() called');
  }

  @override
  Future<void> stop() async {
    _running = false;
    _emitTimer?.cancel();
    _emitTimer = null;
    _sink = null;
  }

  /// Manually emit a specific utterance (for testing/demo control).
  void emitUtterance(String text, {double? confidence}) {
    _sink?.call(AsrResult(text, confidence ?? _confidence));
  }

  /// Emit a deliberate error (wrong word) for demo purposes.
  void emitError(String wrongWord) {
    _sink?.call(AsrResult(wrongWord, 0.85));
  }
}

void dlog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
