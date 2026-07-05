/// Background Isolate for on-device streaming ASR (spec §4).
///
/// All ONNX Runtime inference, mel-feature extraction, VAD, and CTC decoding
/// runs on this background isolate — never the UI isolate (spec §4.5).
///
/// Communication protocol (SendPort/ReceivePort):
///
/// Main → Isolate messages (maps with 'type' key):
///   {'type': 'init', 'modelPath': String, 'tokensContent': String,
///    'vadThreshold': double}
///   {'type': 'audio', 'chunk': Float32List}
///   {'type': 'flush'}
///   {'type': 'stop'}
///   {'type': 'set_threshold', 'threshold': double}
///
/// Isolate → Main messages (maps with 'type' key):
///   {'type': 'ready'}
///   {'type': 'init_failed', 'error': String}
///   {'type': 'result', 'text': String, 'confidence': double, 'rtf': double}
///   {'type': 'log', 'message': String}
///   {'type': 'stopped'}
///
/// Architecture note (spec §4.2 deviation):
/// The spec references a streaming model with cache tensor inputs
/// (model_streaming_with_encoder.q8.onnx) that does NOT exist in the
/// HuggingFace repo. We use model_int8.onnx with full-utterance inference
/// instead — feeding complete VAD segments (not 200ms chunks with cache
/// carry). This is viable because RTF is 0.023-0.031 (Gate 0 verified),
/// there is no hallucination risk from missing cache state, and the
/// architecture is simpler and more robust.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'ctc_decoder.dart';
import 'energy_vad.dart';
import 'mel_features.dart';

/// Entry point for the ASR background isolate.
///
/// [message] is the SendPort from the main isolate — the isolate sends
/// status messages back through this port and receives commands via
/// its own ReceivePort.
void asrIsolateEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  // Send our receive port back so main can send us commands
  mainSendPort.send(receivePort.sendPort);

  AsrIsolateWorker? worker;

  receivePort.listen((message) {
    if (message is! Map) return;
    final type = message['type'] as String;

    switch (type) {
      case 'init':
        worker = AsrIsolateWorker();
        worker!.initialize(
          mainSendPort: mainSendPort,
          modelPath: message['modelPath'] as String,
          tokensContent: message['tokensContent'] as String,
          vadThreshold: message['vadThreshold'] as double,
        );
        break;

      case 'audio':
        worker?.processAudioChunk(message['chunk'] as Float32List);
        break;

      case 'flush':
        worker?.flush();
        break;

      case 'set_threshold':
        worker?.setVadThreshold(message['threshold'] as double);
        break;

      case 'stop':
        worker?.stop();
        receivePort.close();
        break;
    }
  });
}

/// Internal worker that holds all ASR state on the background isolate.
///
/// Created when the 'init' message is received. All Ort objects (session,
/// tensors, options) are isolate-specific FFI pointers and must only be
/// accessed from this isolate.
class AsrIsolateWorker {
  late SendPort _mainSendPort;
  late OrtSession _session;
  late OrtSessionOptions _sessionOptions;
  late OrtRunOptions _runOptions;
  late TokenVocab _vocab;
  late MelFeatureExtractor _melExtractor;
  late EnergyVad _vad;

  /// Input name from the ONNX model (dynamically resolved).
  late String _inputName;

  /// Whether the model expects a 'length' input tensor.
  bool _hasLengthInput = false;

  /// Total audio processed (samples) for RTF calculation.
  int _totalSamples = 0;

  /// Total inference time (microseconds) for RTF calculation.
  int _totalInferenceUs = 0;

  /// Whether initialization succeeded.
  bool _initialized = false;

  void initialize({
    required SendPort mainSendPort,
    required String modelPath,
    required String tokensContent,
    required double vadThreshold,
  }) {
    _mainSendPort = mainSendPort;

    try {
      _sendLog('Initializing ORT environment...');
      // OrtEnv is isolate-specific singleton — must init separately
      // on each isolate (FFI statics are thread-local).
      OrtEnv.instance.init();

      _sendLog('Loading model from: $modelPath');
      _sessionOptions = OrtSessionOptions();
      _sessionOptions.setIntraOpNumThreads(1);
      _sessionOptions
          .setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

      final modelFile = File(modelPath);
      if (!modelFile.existsSync()) {
        throw Exception('Model file not found: $modelPath');
      }
      _session = OrtSession.fromFile(modelFile, _sessionOptions);

      _sendLog('Session created. Inputs: ${_session.inputNames}, '
          'Outputs: ${_session.outputNames}');

      // Resolve input names dynamically
      // FastConformer-CTC typically has: audio_signal [B,80,T], length [B]
      final inputNames = _session.inputNames;
      if (inputNames.isEmpty) {
        throw Exception('Model has no inputs');
      }
      _inputName = inputNames.first;
      _hasLengthInput = inputNames.length >= 2;

      // Parse token vocabulary
      _vocab = TokenVocab.fromTokensTxt(tokensContent);
      _sendLog('Vocab loaded: ${_vocab.vocabSize} tokens');

      // Create feature extractor and VAD
      _melExtractor = MelFeatureExtractor();
      _vad = EnergyVad(rmsThreshold: vadThreshold);

      _runOptions = OrtRunOptions();

      _initialized = true;
      _sendLog('ASR isolate ready.');
      mainSendPort.send({'type': 'ready'});
    } catch (e, stackTrace) {
      _sendLog('Init failed: $e\n$stackTrace');
      mainSendPort.send({'type': 'init_failed', 'error': '$e'});
    }
  }

  /// Process a chunk of audio through VAD → inference → CTC decode.
  void processAudioChunk(Float32List chunk) {
    if (!_initialized) return;

    _totalSamples += chunk.length;

    final result = _vad.processChunk(chunk);

    // Rate-limited debug logging: log every 10th chunk
    if (_vad.totalChunks % 10 == 0) {
      _sendLog('VAD: state=${result.state.name}, rms=${result.chunkRms.toStringAsFixed(6)}, '
          'segmentComplete=${result.segmentComplete}');
    }

    if (result.segmentComplete && result.segment != null) {
      _runInference(result.segment!);
    }
  }

  /// Force-flush any buffered speech segment through inference.
  void flush() {
    if (!_initialized) return;

    final segment = _vad.forceFlush();
    if (segment != null) {
      _runInference(segment);
    }
  }

  /// Update the VAD RMS threshold at runtime.
  void setVadThreshold(double threshold) {
    _vad.rmsThreshold = threshold;
    _sendLog('VAD threshold updated: $threshold');
  }

  /// Stop and release all resources.
  void stop() {
    if (_initialized) {
      // Flush any remaining segment
      final segment = _vad.forceFlush();
      if (segment != null) {
        _runInference(segment);
      }

      // Release Ort resources
      _runOptions.release();
      _session.release();
      _sessionOptions.release();
      OrtEnv.instance.release();
      _initialized = false;
    }

    // Report cumulative RTF before shutting down
    if (_totalSamples > 0 && _totalInferenceUs > 0) {
      final totalAudioSec = _totalSamples / AudioConstants.sampleRate;
      final totalInferSec = _totalInferenceUs / 1e6;
      final cumulativeRtf = totalInferSec / totalAudioSec;
      _sendLog('Cumulative RTF: ${cumulativeRtf.toStringAsFixed(3)} '
          '($totalInferSec s inference / $totalAudioSec s audio)');
    }

    _mainSendPort.send({'type': 'stopped'});
  }

  /// Run full-utterance inference on a speech segment.
  ///
  /// Pipeline: mel features → ONNX inference → CTC greedy decode → text.
  void _runInference(Float32List segment) {
    try {
      final audioDurationSec = segment.length / AudioConstants.sampleRate;

      // Step 1: Extract mel features
      final (features, numFrames) = _melExtractor.extract(segment);
      if (numFrames == 0) {
        _sendLog('Inference: 0 mel frames, skipping');
        return;
      }

      _sendLog('Inference: $numFrames mel frames, '
          '${audioDurationSec.toStringAsFixed(2)}s audio');

      // Step 2: Create input tensor [1, 80, numFrames]
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        [features],
        [1, AudioConstants.nMels, numFrames],
      );

      // Build inputs map
      final inputs = <String, OrtValue>{
        _inputName: inputTensor,
      };

      // If model expects length input, add it
      OrtValueTensor? lengthTensor;
      if (_hasLengthInput) {
        final lengthInputName = _session.inputNames
            .firstWhere((n) => n != _inputName, orElse: () => _inputName);
        lengthTensor = OrtValueTensor.createTensorWithDataList(
          [numFrames],
          [1],
        );
 // int64 tensor
        inputs[lengthInputName] = lengthTensor;
      }

      // Step 3: Run inference (synchronous — we're already on background isolate)
      final inferenceStart = DateTime.now().microsecondsSinceEpoch;
      final outputs = _session.run(_runOptions, inputs);
      final inferenceEnd = DateTime.now().microsecondsSinceEpoch;
      final inferenceUs = inferenceEnd - inferenceStart;
      _totalInferenceUs += inferenceUs;

      // Step 4: Read output and decode
      final output = outputs.firstOrNull;
      if (output == null || output is! OrtValueTensor) {
        _sendLog('Inference: null output');
        inputTensor.release();
        lengthTensor?.release();
        return;
      }

      // Output shape: [1, T_out, 1025] (batch, time, vocab)
      // .value returns nested List for 3D float tensor
      final outputValue = output.value;
      final outputTensor = output;

      // Extract logprobs as flat Float32List [T_out, 1025]
      final logprobs = _extractLogprobs(outputValue);
      final tOut = logprobs.length ~/ (AudioConstants.blankId + 1);

      // Step 5: CTC greedy decode
      final tokenIds = ctcGreedyDecode(
        logprobs,
        tOut,
        AudioConstants.blankId + 1,
        blankId: AudioConstants.blankId,
      );

      // Step 6: Map tokens to text
      final text = decodeTokensToText(tokenIds, _vocab);

      // Step 7: Compute confidence
      final confidence = _computeConfidence(logprobs, tOut);

      // Compute RTF
      final rtf = inferenceUs / 1e6 / audioDurationSec;

      _sendLog('Result: "$text" (conf=${confidence.toStringAsFixed(3)}, '
          'rtf=${rtf.toStringAsFixed(3)}, tokens=${tokenIds.length})');

      // Send result to main isolate
      _mainSendPort.send({
        'type': 'result',
        'text': text,
        'confidence': confidence,
        'rtf': rtf,
      });

      // Release Ort resources
      outputTensor.release();
      inputTensor.release();
      lengthTensor?.release();
    } catch (e, stackTrace) {
      _sendLog('Inference error: $e\n$stackTrace');
      // Send empty result to avoid hanging the UI
      _mainSendPort.send({
        'type': 'result',
        'text': '',
        'confidence': 0.0,
        'rtf': 0.0,
      });
    }
  }

  /// Extract log-probabilities from the model output into a flat Float32List.
  ///
  /// The output value is a nested `List` for shape `[1, T, V]`.
  /// We flatten it to `T * V` in row-major order, skipping the batch dimension.
  Float32List _extractLogprobs(dynamic outputValue) {
    if (outputValue is! List) return Float32List(0);

    // Handle [1, T, V] nested list
    if (outputValue.isNotEmpty && outputValue[0] is List) {
      final batch = outputValue[0] as List; // [T, V]
      final t = batch.length;
      if (t == 0) return Float32List(0);
      final v = (batch[0] as List).length;
      final flat = Float32List(t * v);
      for (int i = 0; i < t; i++) {
        final frame = batch[i] as List;
        for (int j = 0; j < v; j++) {
          flat[i * v + j] = (frame[j] as num).toDouble();
        }
      }
      return flat;
    }

    // Handle flat List<num> (1D)
    if (outputValue is List<num>) {
      final flat = Float32List(outputValue.length);
      for (int i = 0; i < outputValue.length; i++) {
        flat[i] = outputValue[i].toDouble();
      }
      return flat;
    }

    return Float32List(0);
  }

  /// Compute a simple confidence score from the log-probabilities.
  ///
  /// Uses the sigmoid of the margin between top-1 and top-2 logits per frame,
  /// averaged over all frames. This gives a value in [0, 1] where higher
  /// means the model is more confident in its argmax choices.
  double _computeConfidence(Float32List logprobs, int tOut) {
    if (tOut == 0) return 0.0;
    final vocabSize = AudioConstants.blankId + 1; // 1025
    double totalConf = 0.0;

    for (int t = 0; t < tOut; t++) {
      final offset = t * vocabSize;
      double max1 = double.negativeInfinity;
      double max2 = double.negativeInfinity;

      for (int v = 0; v < vocabSize; v++) {
        final val = logprobs[offset + v];
        if (val > max1) {
          max2 = max1;
          max1 = val;
        } else if (val > max2) {
          max2 = val;
        }
      }

      // Sigmoid of margin → 0-1 confidence per frame
      final margin = max1 - max2;
      totalConf += 1.0 / (1.0 + exp(-margin));
    }

    return totalConf / tOut;
  }

  void _sendLog(String message) {
    _mainSendPort.send({'type': 'log', 'message': message});
  }
}
