/// Pure-Dart energy-based Voice Activity Detection (VAD).
///
/// Implements the energy VAD state machine described in spec §4.4.
///
/// Design:
///   - RMS energy thresholding on raw PCM audio chunks
///   - Two-state machine: SILENCE → SPEECH → SILENCE
///   - Voice onset: `voiceOnChunks` consecutive chunks above threshold
///     to transition SILENCE → SPEECH
///   - Voice offset: `silenceChunks` consecutive chunks below threshold
///     to transition SPEECH → SILENCE (and emit a speech segment)
///   - Max segment duration: force-flush if speech exceeds `maxSegmentSeconds`
///   - Lookback buffer: keeps recent chunks so that when speech is
///     detected, we include the chunks that triggered the transition
///     (no clipping of onset)
///
/// NO Silero, NO native VAD library. Pure Dart RMS computation.
///
/// Tuning note (spec §4.4): The RMS threshold must be tuned on-device
/// with rate-limited debug logging. The default value is a starting
/// point only — it MUST be measured against real device microphone
/// data before being considered correct.
///
/// Constants justification:
///   chunkDurationMs = 200   — spec §4.2 references 200ms chunks for
///                              streaming inference. VAD operates on
///                              same chunk granularity.
///   voiceOnChunks = 2       — spec §4.4: 2 consecutive chunks to enter
///                              speech (400ms of voice activity)
///   silenceChunks = 6       — spec §4.4: 6 consecutive chunks to exit
///                              speech (1200ms of silence)
///   maxSegmentSeconds = 5.0 — spec §4.4: force-flush at 5s max segment
///   defaultRmsThreshold — STARTING POINT ONLY. Must be tuned on-device.
///   sampleRate = 16000      — from AudioConstants (model requirement)
library;

import 'dart:math';
import 'dart:typed_data';

/// VAD state.
enum VadState { silence, speech }

/// Result of processing a chunk through the VAD.
class VadResult {
  /// Current VAD state after processing this chunk.
  final VadState state;

  /// True if a complete speech segment was emitted (silence detected
  /// after speech, or max segment duration reached).
  final bool segmentComplete;

  /// The speech segment audio samples (Float32List at 16kHz).
  /// Only non-null when [segmentComplete] is true.
  final Float32List? segment;

  /// RMS energy of the current chunk (for debug logging / threshold tuning).
  final double chunkRms;

  VadResult({
    required this.state,
    required this.segmentComplete,
    this.segment,
    required this.chunkRms,
  });
}

/// Energy-based VAD state machine.
///
/// Feed audio chunks via [processChunk]. When a speech segment is
/// complete (silence after speech or max duration reached), the
/// returned [VadResult] will have [segmentComplete] = true and
/// [segment] containing the full speech audio.
class EnergyVad {
  /// RMS energy threshold. Chunks with RMS above this are "voice".
  /// STARTING POINT — must be tuned on real device microphone data.
  double rmsThreshold;

  /// Number of consecutive voice chunks to enter speech state.
  final int voiceOnChunks;

  /// Number of consecutive silence chunks to exit speech state.
  final int silenceChunks;

  /// Maximum speech segment duration before force-flush (seconds).
  final double maxSegmentSeconds;

  /// Sample rate (Hz). Must match model: 16000.
  final int sampleRate;

  // Internal state
  VadState _state = VadState.silence;
  int _consecutiveVoice = 0;
  int _consecutiveSilence = 0;

  /// Buffer accumulating speech segment audio samples.
  final List<double> _segmentBuffer = <double>[];

  /// Current segment duration in samples.
  int _segmentSamples = 0;

  /// Total chunks processed (for debug logging).
  int _totalChunks = 0;

  EnergyVad({
    this.rmsThreshold = 0.01,
    this.voiceOnChunks = 2,
    this.silenceChunks = 6,
    this.maxSegmentSeconds = 5.0,
    this.sampleRate = 16000,
  });

  /// Current VAD state.
  VadState get state => _state;

  /// Total chunks processed.
  int get totalChunks => _totalChunks;

  /// Compute RMS energy of a chunk of audio samples.
  static double computeRms(Float32List samples) {
    if (samples.isEmpty) return 0.0;
    double sumSquares = 0.0;
    for (int i = 0; i < samples.length; i++) {
      sumSquares += samples[i] * samples[i];
    }
    return sqrt(sumSquares / samples.length);
  }

  /// Process a chunk of audio samples through the VAD state machine.
  ///
  /// [chunk] — Float32List of mono audio samples at [sampleRate] Hz.
  ///
  /// Returns a [VadResult] indicating the current state and whether
  /// a complete speech segment was emitted.
  VadResult processChunk(Float32List chunk) {
    _totalChunks++;
    final rms = computeRms(chunk);
    final isVoice = rms > rmsThreshold;
    final maxSegmentSamples = (maxSegmentSeconds * sampleRate).round();

    bool segmentComplete = false;
    Float32List? segment;

    switch (_state) {
      case VadState.silence:
        if (isVoice) {
          _consecutiveVoice++;
          _consecutiveSilence = 0;

          // Start buffering in case we transition to speech
          _segmentBuffer.addAll(chunk);
          _segmentSamples += chunk.length;

          if (_consecutiveVoice >= voiceOnChunks) {
            // Transition to speech
            _state = VadState.speech;
            _consecutiveVoice = 0;
            _consecutiveSilence = 0;
          }
        } else {
          _consecutiveVoice = 0;
          _consecutiveSilence++;

          // If we were buffering but didn't reach voiceOnChunks,
          // discard the buffer (was just noise)
          if (_segmentBuffer.isNotEmpty && _consecutiveSilence > voiceOnChunks) {
            _segmentBuffer.clear();
            _segmentSamples = 0;
          }
        }

      case VadState.speech:
        // Always add to segment buffer while in speech state
        _segmentBuffer.addAll(chunk);
        _segmentSamples += chunk.length;

        if (isVoice) {
          _consecutiveVoice++;
          _consecutiveSilence = 0;
        } else {
          _consecutiveSilence++;
          _consecutiveVoice = 0;
        }

        // Check for silence-based segment end
        if (_consecutiveSilence >= silenceChunks) {
          segmentComplete = true;
          // The segment includes all buffered audio. The trailing silence
          // chunks are included as a natural tail — this helps the model
          // with word endings.
          segment = _buildSegment();
          _resetSegment();
          _state = VadState.silence;
          _consecutiveSilence = 0;
          _consecutiveVoice = 0;
        }
        // Check for max duration force-flush
        else if (_segmentSamples >= maxSegmentSamples) {
          segmentComplete = true;
          segment = _buildSegment();
          _resetSegment();
          // Stay in speech state — the speaker may continue
          // but we flush what we have so far
          _consecutiveSilence = 0;
          _consecutiveVoice = 0;
        }
    }

    return VadResult(
      state: _state,
      segmentComplete: segmentComplete,
      segment: segment,
      chunkRms: rms,
    );
  }

  /// Force-flush the current segment (if any) regardless of state.
  ///
  /// Called when the ASR service is stopped or flushed.
  Float32List? forceFlush() {
    if (_segmentBuffer.isEmpty) return null;

    final segment = _buildSegment();
    _resetSegment();
    _state = VadState.silence;
    _consecutiveVoice = 0;
    _consecutiveSilence = 0;
    return segment;
  }

  /// Reset the VAD to initial silence state.
  void reset() {
    _state = VadState.silence;
    _consecutiveVoice = 0;
    _consecutiveSilence = 0;
    _segmentBuffer.clear();
    _segmentSamples = 0;
    _totalChunks = 0;
  }

  /// Build a Float32List from the segment buffer.
  Float32List _buildSegment() {
    final result = Float32List(_segmentBuffer.length);
    for (int i = 0; i < _segmentBuffer.length; i++) {
      result[i] = _segmentBuffer[i];
    }
    return result;
  }

  /// Clear the segment buffer and reset sample count.
  void _resetSegment() {
    _segmentBuffer.clear();
    _segmentSamples = 0;
  }
}
