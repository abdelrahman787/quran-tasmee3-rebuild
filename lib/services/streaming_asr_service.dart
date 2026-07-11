/// Real on-device streaming ASR service (spec section 4).
///
/// Implements the [AsrService] interface using a background [Isolate] for
/// all ONNX Runtime inference. Audio is captured via the `record` package
/// (PCM16, 16 kHz, mono) and fed to the isolate in chunks.
///
/// This implementation is **mobile-only** — it uses `dart:io`, `record`,
/// and `onnxruntime` (via the isolate). On web, the [FakeAsrServiceImpl]
/// is used instead (see swap point 1 in providers.dart).
///
/// Architecture (spec section 4.5):
///   Main Isolate:
///     mic capture (record) -> PCM16-to-Float32 -> SendPort -> isolate
///   Background Isolate:
///     VAD -> mel features -> ONNX inference -> CTC decode -> result
///
/// **SWAP POINT**: Replace `FakeAsrServiceImpl` with `StreamingAsrService`
/// in `providers.dart` **AFTER Gate 2 passes on device**. Do NOT flip
/// the swap point until live-mic testing confirms correct behaviour.
///
/// Architecture note (spec section 4.2 deviation):
/// The streaming model with cache tensor inputs does NOT exist in the
/// HuggingFace repo. We use `model_int8.onnx` with full-utterance
/// inference — VAD accumulates complete speech segments, each run as a
/// single utterance. RTF is 0.023-0.031 (Gate 0 verified), no
/// hallucination risk, simpler architecture.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quran_tasmee3_core/recitation/asr_service.dart';
import 'package:record/record.dart';

import 'asr/asr_isolate.dart';

/// On-device streaming ASR service backed by onnxruntime + background isolate.
///
/// Implements the [AsrService] contract:
///   [start] — initialises the isolate, loads the model, starts mic capture.
///   [pause] — pauses the mic stream (isolate keeps its state).
///   [resume] — resumes the mic stream.
///   [flush] — forces the VAD to emit any buffered speech segment.
///   [stop] — stops mic, shuts down isolate, releases all resources.
///
/// Extended API for the dev screen (Gate 1/2 testing):
///   [init] — initialise isolate without starting mic (for WAV-file testing).
///   [feedAudioChunk] — feed raw Float32 audio directly (bypasses mic).
///   [setVadThreshold] — tune VAD RMS threshold at runtime.
///   [onLog] — callback for isolate log messages (debug/tuning).
///   [isReady] — whether the isolate is initialised and accepting audio.
class StreamingAsrService implements AsrService {
  // ── Callbacks ──────────────────────────────────────────────────────────
  /// Result callback — set by [start] or directly for dev-screen use.
  /// Carries only the AsrService-contract (text, confidence) — no RTF.
  void Function(AsrResult)? onResultCallback;
  void Function(AsrResult)? get _onResult => onResultCallback;

  /// Dev-screen-only: receives (text, confidence, rtf) for every result.
  /// Production code should use [onResultCallback] instead, which only
  /// carries the AsrService-contract (text, confidence).
  void Function(String text, double confidence, double rtf)? onDevResult;

  /// Optional log callback — receives all isolate log messages.
  /// Used by the dev screen for VAD tuning and diagnostics.
  void Function(String)? onLog;

  // ── Isolate state ──────────────────────────────────────────────────────
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  ReceivePort? _mainReceivePort;
  bool _initialized = false;

  /// Completer for the isolate's 'stopped' acknowledgment.
  /// Created in [stop()] and completed in _handleIsolateMessage's
  /// case 'stopped'. Allows [stop()] to wait for the isolate to flush
  /// any final buffered speech before killing it.
  Completer<void>? _stopCompleter;

  // ── Mic state ──────────────────────────────────────────────────────────
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _micSubscription;
  bool _running = false;
  bool _paused = false;

  // ── VAD threshold (starting point — must be tuned on-device) ───────────
  double _vadThreshold = 0.01;

  // ── Asset paths ────────────────────────────────────────────────────────
  static const _modelAssetPath = 'assets/models/asr/model_int8.onnx';
  static const _tokensAssetPath = 'assets/models/asr/tokens.txt';

  // ── AsrService implementation ──────────────────────────────────────────

  @override
  Future<void> start(void Function(AsrResult) onResult) async {
    onResultCallback = onResult;
    _running = true;
    _paused = false;

    if (!_initialized) {
      await init();
    }

    await _startMicRecording();
  }

  @override
  Future<void> pause() async {
    _paused = true;
    _micSubscription?.pause();
  }

  @override
  Future<void> resume() async {
    _paused = false;
    _micSubscription?.resume();
  }

  @override
  Future<void> flush() async {
    _isolateSendPort?.send({'type': 'flush'});
  }

  @override
  Future<void> stop() async {
    _running = false;

    // Stop mic — do NOT clear callbacks yet. The isolate may still
    // flush a final buffered speech segment and deliver its last result.
    await _micSubscription?.cancel();
    _micSubscription = null;
    try {
      await _recorder?.stop();
    } catch (_) {
      // Recorder may already be stopped
    }
    await _recorder?.dispose();
    _recorder = null;

    // Send 'stop' and wait for the isolate to acknowledge 'stopped'.
    // The isolate's stop() handler flushes any remaining VAD segment,
    // runs one final inference, then sends {'type': 'stopped'}.
    // We give it a short grace period (500 ms) so the final result
    // can still flow through the callbacks before we tear everything down.
    if (_isolateSendPort != null) {
      _stopCompleter = Completer<void>();
      _isolateSendPort!.send({'type': 'stop'});
      await _stopCompleter!.future.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
    }

    // Now safe to clear callbacks — the isolate has either flushed
    // its final result (within the grace period) or timed out.
    onResultCallback = null;
    onDevResult = null;

    // Kill the isolate and release resources.
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _isolateSendPort = null;
    _stopCompleter = null;
    _initialized = false;
  }

  // ── Extended API for dev screen (Gate 1/2) ─────────────────────────────

  /// Initialise the background isolate without starting the mic.
  ///
  /// Loads the model and tokens from app assets, writes the model to a
  /// temp file, spawns the isolate, and waits for it to signal ready.
  ///
  /// Call this before [feedAudioChunk] when using WAV-file mode.
  /// [start] calls this internally — no need to call separately for mic mode.
  Future<void> init() async {
    if (_initialized) return;

    // Load tokens from assets
    final tokensContent = await rootBundle.loadString(_tokensAssetPath);

    // Load model bytes from assets and write to temp file.
    // The model is ~175 MB — rootBundle.load reads it all into memory,
    // then we write it to the app's temporary directory for OrtSession.fromFile.
    final modelBytes = await rootBundle.load(_modelAssetPath);
    final tempDir = await getTemporaryDirectory();
    final modelFile = File('${tempDir.path}/asr_model_int8.onnx');
    await modelFile.writeAsBytes(modelBytes.buffer.asUint8List());

    // Spawn isolate and set up bidirectional communication
    _mainReceivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      asrIsolateEntry,
      _mainReceivePort!.sendPort,
      debugName: 'asr-isolate',
    );

    final readyCompleter = Completer<void>();
    SendPort? isolatePort;

    _mainReceivePort!.listen((message) {
      if (message is SendPort) {
        // Isolate sent us its ReceivePort's SendPort — use it to send commands
        isolatePort = message;
        isolatePort!.send({
          'type': 'init',
          'modelPath': modelFile.path,
          'tokensContent': tokensContent,
          'vadThreshold': _vadThreshold,
        });
      } else if (message is Map) {
        _handleIsolateMessage(message, readyCompleter, isolatePort);
      }
    });

    await readyCompleter.future;
    _initialized = true;
  }

  /// Feed a chunk of raw Float32 audio directly to the isolate.
  ///
  /// Used by the dev screen for WAV-file testing (Gate 1). Each chunk
  /// should be ~200 ms (3200 samples at 16 kHz) to match the VAD chunk size.
  void feedAudioChunk(Float32List chunk) {
    if (_isolateSendPort == null || !_running) return;
    _isolateSendPort!.send({'type': 'audio', 'chunk': chunk});
  }

  /// Update the VAD RMS threshold at runtime.
  ///
  /// The threshold is a **starting point only** — it MUST be tuned against
  /// real device microphone data (spec section 4.4). The dev screen
  /// provides a slider for this purpose.
  void setVadThreshold(double threshold) {
    _vadThreshold = threshold;
    _isolateSendPort?.send({'type': 'set_threshold', 'threshold': threshold});
  }

  /// Whether the isolate is initialised and ready to accept audio.
  bool get isReady => _initialized && _isolateSendPort != null;

  /// Current VAD threshold value.
  double get vadThreshold => _vadThreshold;

  // ── Internal: mic recording ────────────────────────────────────────────

  /// Start microphone recording — public for dev-screen use.
  ///
  /// Called internally by [start]. The dev screen calls this directly
  /// after [init] to begin live mic capture without going through [start].
  Future<void> startMicRecording() async {
    await _startMicRecording();
  }

  Future<void> _startMicRecording() async {
    _recorder = AudioRecorder();

    // Check permission — startStream will request if not granted
    if (!await _recorder!.hasPermission()) {
      // On Android, startStream triggers the system permission dialog.
      // If denied, the stream will be empty or throw.
    }

    final stream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );

    _micSubscription = stream.listen((data) {
      if (!_running || _paused || _isolateSendPort == null) return;

      // Convert PCM16 bytes to Float32 [-1, 1]
      final samples = _pcm16ToFloat32(data);

      // Send to isolate for VAD + inference
      _isolateSendPort!.send({'type': 'audio', 'chunk': samples});
    });
  }

  /// Convert PCM16 little-endian bytes to normalised Float32 samples.
  Float32List _pcm16ToFloat32(Uint8List bytes) {
    // Ensure even length (each sample is 2 bytes)
    final sampleCount = bytes.length ~/ 2;
    final view = ByteData.sublistView(bytes, 0, sampleCount * 2);
    final result = Float32List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      final sample = view.getInt16(i * 2, Endian.little);
      result[i] = sample / 32768.0;
    }
    return result;
  }

  // ── Internal: isolate message handling ─────────────────────────────────

  void _handleIsolateMessage(
    Map message,
    Completer<void> readyCompleter,
    SendPort? isolatePort,
  ) {
    final type = message['type'] as String;

    switch (type) {
      case 'ready':
        _isolateSendPort = isolatePort;
        readyCompleter.complete();

      case 'init_failed':
        final error = message['error'] as String? ?? 'Unknown init error';
        readyCompleter.completeError(Exception('ASR isolate init failed: $error'));

      case 'result':
        final text = message['text'] as String? ?? '';
        final confidence = (message['confidence'] as num?)?.toDouble() ?? 0.0;
        final rtf = (message['rtf'] as num?)?.toDouble() ?? 0.0;
        if (!_paused) {
          _onResult?.call(AsrResult(text, confidence));
          onDevResult?.call(text, confidence, rtf);
        }

      case 'log':
        final msg = message['message'] as String? ?? '';
        onLog?.call(msg);
        if (kDebugMode) {
          debugPrint('[ASR] $msg');
        }

      case 'stopped':
        // Isolate has finished flushing its final result and releasing
        // resources. Complete the stop Completer so [stop()] can proceed
        // to clear callbacks and kill the isolate.
        if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
          _stopCompleter!.complete();
        }
    }
  }
}
