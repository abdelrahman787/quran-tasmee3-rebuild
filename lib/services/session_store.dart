/// Session store — bridges the pure-Dart [RecitationController] to Riverpod
/// state management for the UI layer.
///
/// The controller is framework-agnostic; this notifier wraps it, supplies
/// a real clock, feeds ASR results, and exposes reactive state for widgets.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quran_tasmee3_core/recitation/asr_service.dart';
import 'package:quran_tasmee3_core/recitation/matching_engine.dart';
import 'package:quran_tasmee3_core/recitation/recitation_controller.dart';
import 'package:quran_tasmee3_core/recitation/recitation_config.dart';
import 'package:quran_tasmee3_core/recitation/session_report.dart';

/// The reactive state surfaced to the UI.
class SessionState {
  final RecitationStatus status;
  final int cursor;
  final Set<int> revealedIndices;
  final RecordedError? lastError;
  final bool silenceIndicatorVisible;
  final List<RecitationEvent> recentEvents;
  final List<RecordedError> errors;
  final String? partialTranscript;

  const SessionState({
    this.status = RecitationStatus.idle,
    this.cursor = 0,
    this.revealedIndices = const {},
    this.lastError,
    this.silenceIndicatorVisible = false,
    this.recentEvents = const [],
    this.errors = const [],
    this.partialTranscript,
  });

  SessionState copyWith({
    RecitationStatus? status,
    int? cursor,
    Set<int>? revealedIndices,
    RecordedError? lastError,
    bool? silenceIndicatorVisible,
    List<RecitationEvent>? recentEvents,
    List<RecordedError>? errors,
    String? partialTranscript,
  }) {
    return SessionState(
      status: status ?? this.status,
      cursor: cursor ?? this.cursor,
      revealedIndices: revealedIndices ?? this.revealedIndices,
      lastError: lastError ?? this.lastError,
      silenceIndicatorVisible: silenceIndicatorVisible ?? this.silenceIndicatorVisible,
      recentEvents: recentEvents ?? this.recentEvents,
      errors: errors ?? this.errors,
      partialTranscript: partialTranscript ?? this.partialTranscript,
    );
  }

  bool get isListening => status == RecitationStatus.listening;
  bool get isPaused => status == RecitationStatus.paused;
  bool get isCompleted => status == RecitationStatus.completed;
  bool get isActive => status == RecitationStatus.listening ||
      status == RecitationStatus.matching ||
      status == RecitationStatus.revealing;
}

/// The state notifier that owns the [RecitationController] and drives the UI.
class SessionStore extends StateNotifier<SessionState> {
  RecitationController? _controller;
  AsrService? _asrService;
  SessionLogger? _logger;
  Timer? _silenceTimer;
  List<ExpectedWord>? _scope;

  SessionStore() : super(const SessionState());

  RecitationController? get controller => _controller;

  /// Initialize a new recitation session.
  void startSession({
    required List<ExpectedWord> scope,
    required RecitationConfig mode,
    required int Function() clock,
    required AsrService asrService,
    required SessionLogger logger,
  }) {
    _scope = scope;
    _asrService = asrService;
    _logger = logger;

    final events = <RecitationEvent>[];

    _controller = RecitationController(
      scope: scope,
      mode: mode,
      now: clock,
      logger: logger,
      onReveal: (index) {
        // Reveal handled via state update below
      },
      onEvent: (event) {
        events.add(event);
        _updateState(events: events);
      },
    );

    _controller!.start();

    state = SessionState(
      status: _controller!.status,
      cursor: _controller!.cursor,
      revealedIndices: {},
      recentEvents: events,
    );

    // Start the ASR service
    asrService.start((result) {
      _controller?.submitAsr(result);
      _updateState();
    });

    // Start silence checker (every 1 second)
    _silenceTimer?.cancel();
    _silenceTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        _controller?.checkSilence();
        _updateState();
      },
    );
  }

  /// Submit an ASR result to the controller (used by fake/demo ASR).
  void submitAsrResult(AsrResult result) {
    _controller?.submitAsr(result);
    _updateState();
  }

  /// Pause the session.
  void pause() {
    _controller?.pause();
    _asrService?.pause();
    _updateState();
  }

  /// Resume the session.
  void resume() {
    _controller?.resume();
    _asrService?.resume();
    _updateState();
  }

  /// Reveal the next word (manual reveal button).
  void revealNextWord() {
    _controller?.revealNextWord();
    _updateState();
  }

  /// Reveal the full current ayah (manual reveal button).
  void revealFullAyah() {
    _controller?.revealFullAyah();
    _updateState();
  }

  /// Stop the session and build the report.
  SessionReport? stopAndReport() {
    _controller?.stop();
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _asrService?.stop();
    _updateState();

    if (_scope == null || _logger == null) return null;
    return buildSessionReport(
      scope: _scope!,
      errors: (_logger as InMemorySessionLogger).errors,
    );
  }

  /// Flush ASR state (for requestAsrReset event).
  void flushAsr() {
    _asrService?.flush();
  }

  void _updateState({List<RecitationEvent>? events}) {
    if (_controller == null) return;
    final c = _controller!;
    state = SessionState(
      status: c.status,
      cursor: c.cursor,
      revealedIndices: Set.from(c.revealedIndices),
      lastError: c.lastError,
      silenceIndicatorVisible: c.silenceIndicatorVisible,
      recentEvents: events ?? state.recentEvents,
      errors: _logger is InMemorySessionLogger
          ? List.from((_logger as InMemorySessionLogger).errors)
          : [],
    );
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _asrService?.stop();
    super.dispose();
  }
}
