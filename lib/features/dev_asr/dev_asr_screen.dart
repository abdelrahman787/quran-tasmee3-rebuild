/// Dev-only ASR testing screen (Gate 1 / Gate 2, spec section 4).
///
/// This screen is NOT part of the production user experience. It exists
/// to validate the on-device ASR pipeline before flipping the
/// `asrServiceProvider` swap point in providers.dart.
///
/// Two modes:
///
/// **Gate 1 — Bundled WAV (throwaway harness):**
///   Loads a bundled test WAV (test_fatihah.wav / test_ikhlas.wav) from
///   app assets and feeds it chunk-by-chunk through the ASR isolate.
///   Confirms: no crash, no hallucination, RTF < 0.1, correct text.
///
/// **Gate 2 — Live Mic:**
///   Captures real microphone audio via the `record` package and feeds
///   it through the VAD → inference → CTC decode pipeline. The VAD RMS
///   threshold can be tuned via a slider — every threshold value must
///   be justified by on-device measurement (spec section 4.4).
///
/// After Gate 2 passes (correct transcriptions on live mic, RTF < 0.1,
/// no hallucination, no crash), flip the swap point in providers.dart:
///
///   ```dart
///   import '../services/streaming_asr_service.dart';
///   final asrServiceProvider = Provider<AsrService>((ref) {
///     return StreamingAsrService();
///   });
///   ```
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/asr/wav_parser.dart';
import '../../services/streaming_asr_service.dart';

/// Testing mode for the dev screen.
enum DevAsrMode { wavFile, liveMic }

/// Bundled test WAV files available for Gate 1 testing.
const _testWavs = <String, String>{
  'Al-Fatihah (1)': 'assets/models/asr/test_fatihah.wav',
  'Al-Ikhlas (112)': 'assets/models/asr/test_ikhlas.wav',
};

/// Dev ASR testing screen — Gate 1/2 validation.
///
/// Access: tap the version/about row 7 times in Settings (Android
/// "Developer options" convention), or navigate to this screen directly
/// (hidden route).
class DevAsrScreen extends StatefulWidget {
  const DevAsrScreen({super.key});

  @override
  State<DevAsrScreen> createState() => _DevAsrScreenState();
}

class _DevAsrScreenState extends State<DevAsrScreen>
    with SingleTickerProviderStateMixin {
  final _asrService = StreamingAsrService();
  late final TabController _tabController;

  DevAsrMode _mode = DevAsrMode.wavFile;
  String _selectedWav = _testWavs.keys.first;
  bool _isRunning = false;
  bool _isInitialising = false;
  String? _initError;

  // Results display
  final List<String> _results = [];
  final List<String> _logs = [];

  // VAD tuning
  double _vadThreshold = 0.01; // STARTING POINT — must be tuned on-device
  final List<double> _recentRms = []; // For threshold calibration
  static const int _maxRecentRms = 50;

  // RTF tracking
  double _lastRtf = 0.0;
  double _avgRtf = 0.0;
  int _resultCount = 0;

  // Scroll controllers
  final _resultsScrollController = ScrollController();
  final _logsScrollController = ScrollController();

  @override
  void dispose() {
    _tabController.dispose();
    _asrService.stop();
    _resultsScrollController.dispose();
    _logsScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _asrService.onLog = _onLog;
  }

  void _onLog(String message) {
    if (!mounted) return;
    setState(() {
      _logs.add(message);
      if (_logs.length > 200) _logs.removeRange(0, _logs.length - 200);

      // Extract RMS from VAD log for calibration display
      if (message.contains('rms=')) {
        final rmsMatch = RegExp(r'rms=([\d.]+)').firstMatch(message);
        if (rmsMatch != null) {
          final rms = double.tryParse(rmsMatch.group(1)!);
          if (rms != null) {
            _recentRms.add(rms);
            if (_recentRms.length > _maxRecentRms) {
              _recentRms.removeAt(0);
            }
          }
        }
      }
    });
    _scrollToBottom(_logsScrollController);
  }

  void _onResult(String text, double confidence, double rtf) {
    if (!mounted) return;
    setState(() {
      _results.add('"$text"  (conf=${confidence.toStringAsFixed(3)}, '
          'rtf=${rtf.toStringAsFixed(3)})');
      _lastRtf = rtf;
      _resultCount++;
      _avgRtf = ((_avgRtf * (_resultCount - 1)) + rtf) / _resultCount;
    });
    _scrollToBottom(_resultsScrollController);
  }

  void _scrollToBottom(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        controller.animateTo(
          controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Start / Stop ───────────────────────────────────────────────────────

  Future<void> _start() async {
    setState(() {
      _isInitialising = true;
      _initError = null;
      _results.clear();
      _logs.clear();
      _recentRms.clear();
      _lastRtf = 0.0;
      _avgRtf = 0.0;
      _resultCount = 0;
    });

    try {
      // Initialise the ASR isolate (loads model, tokens, VAD)
      await _asrService.init();
      _asrService.setVadThreshold(_vadThreshold);

      // Dev-screen-only callback — receives (text, confidence, rtf) for every
      // result from the isolate. Set unconditionally so BOTH modes (WAV file
      // and live mic) get results. Previously this was only set in the
      // live-mic else-branch, so WAV mode silently dropped every result.
      _asrService.onDevResult = _onResult;

      setState(() {
        _isInitialising = false;
        _isRunning = true;
      });

      if (_mode == DevAsrMode.wavFile) {
        await _runWavTest();
      } else {
        await _asrService.startMicRecording();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitialising = false;
        _isRunning = false;
        _initError = e.toString();
      });
    }
  }

  Future<void> _runWavTest() async {
    // Load the selected WAV file from assets
    final wavPath = _testWavs[_selectedWav]!;
    final wavBytes = await rootBundle.load(wavPath);
    final wavData = parseWav(wavBytes.buffer.asUint8List());

    _onLog('Loaded WAV: $_selectedWav, '
        'sr=${wavData.sampleRate}Hz, '
        'samples=${wavData.numSamples}, '
        'duration=${wavData.durationSeconds.toStringAsFixed(2)}s');

    if (wavData.sampleRate != 16000) {
      _onLog('WARNING: WAV sample rate is ${wavData.sampleRate}, '
          'expected 16000. Results may be incorrect.');
    }

    // Feed audio chunk-by-chunk (200ms = 3200 samples at 16kHz)
    const chunkSize = 3200;
    const chunkDelayMs = 200; // Simulate real-time playback

    for (int offset = 0; offset < wavData.samples.length; offset += chunkSize) {
      if (!_isRunning) break;

      final end = (offset + chunkSize).clamp(0, wavData.samples.length);
      final chunk = Float32List.sublistView(wavData.samples, offset, end);

      _asrService.feedAudioChunk(chunk);

      // Simulate real-time arrival (so VAD sees realistic timing)
      await Future.delayed(const Duration(milliseconds: chunkDelayMs));
    }

    // Flush any remaining buffered speech
    _asrService.flush();

    _onLog('WAV feeding complete. Waiting for final results...');
  }

  Future<void> _stop() async {
    await _asrService.stop();
    if (!mounted) return;
    setState(() {
      _isRunning = false;
    });
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dev ASR Testing (Gate 1/2)'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Results'),
            Tab(text: 'Logs'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear logs',
            onPressed: () {
              setState(() {
                _results.clear();
                _logs.clear();
                _recentRms.clear();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildControlPanel(),
          if (_initError != null) _buildErrorBanner(),
          const Divider(height: 1),
          _buildStatsBar(),
          const Divider(height: 1),
          Expanded(child: _buildResultsAndLogs()),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode selector
          Row(
            children: [
              const Text('Mode: '),
              ToggleButtons(
                isSelected: [
                  _mode == DevAsrMode.wavFile,
                  _mode == DevAsrMode.liveMic,
                ],
                onPressed: _isRunning
                    ? null
                    : (index) {
                        setState(() {
                          _mode = DevAsrMode.values[index];
                        });
                      },
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('WAV File'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Live Mic'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // WAV file selector (Gate 1 mode only)
          if (_mode == DevAsrMode.wavFile)
            Row(
              children: [
                const Text('Test file: '),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedWav,
                    isExpanded: true,
                    items: _testWavs.keys
                        .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                        .toList(),
                    onChanged: _isRunning
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _selectedWav = value);
                            }
                          },
                  ),
                ),
              ],
            ),

          // VAD threshold slider (always visible — needed for both modes)
          if (_mode == DevAsrMode.liveMic || _isRunning) ...[
            const SizedBox(height: 12),
            Text('VAD RMS Threshold: '
                '${_vadThreshold.toStringAsFixed(4)}  '
                '(STARTING POINT — tune on-device)'),
            Slider(
              value: _vadThreshold,
              min: 0.001,
              max: 0.05,
              divisions: 490,
              label: _vadThreshold.toStringAsFixed(4),
              onChanged: (value) {
                setState(() => _vadThreshold = value);
              },
              onChangeEnd: (value) {
                _asrService.setVadThreshold(value);
              },
            ),
            if (_recentRms.isNotEmpty)
              Text(
                'Recent RMS range: '
                '${_recentRms.reduce(min).toStringAsFixed(4)} — '
                '${_recentRms.reduce(max).toStringAsFixed(4)}  '
                '(${_recentRms.length} samples)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],

          const SizedBox(height: 12),

          // Start / Stop buttons
          Row(
            children: [
              FilledButton.icon(
                onPressed: _isRunning || _isInitialising ? null : _start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _isRunning ? _stop : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
              if (_isInitialising) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                const Text('Loading model...'),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.red.shade100,
      child: Row(
        children: [
          Icon(Icons.error, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _initError!,
              style: TextStyle(color: Colors.red.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _statChip('Results', '$_resultCount'),
          const SizedBox(width: 16),
          _statChip('Last RTF', _lastRtf.toStringAsFixed(3)),
          const SizedBox(width: 16),
          _statChip('Avg RTF', _avgRtf.toStringAsFixed(3)),
          const Spacer(),
          if (_avgRtf > 0 && _avgRtf < 0.1)
            Chip(
              label: const Text('RTF < 0.1 ✓'),
              backgroundColor: Colors.green.shade100,
            )
          else if (_avgRtf >= 0.1)
            Chip(
              label: const Text('RTF >= 0.1 ✗'),
              backgroundColor: Colors.red.shade100,
            ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildResultsAndLogs() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildResultsTab(),
        _buildLogsTab(),
      ],
    );
  }

  Widget _buildResultsTab() {
    if (_results.isEmpty) {
      return const Center(
        child: Text(
          'No results yet.\nPress Start to begin testing.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      controller: _resultsScrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        final isEmpty = result.contains('""') || result.contains('conf=0.000');
        return Card(
          color: isEmpty ? Colors.orange.shade50 : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              result,
              style: TextStyle(
                fontFamily: isEmpty ? null : 'monospace',
                fontSize: 14,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogsTab() {
    if (_logs.isEmpty) {
      return const Center(
        child: Text(
          'No logs yet.\nLogs will appear here during testing.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      controller: _logsScrollController,
      padding: const EdgeInsets.all(8),
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final log = _logs[index];
        final isError = log.contains('error') || log.contains('Error');
        final isResult = log.contains('Result:');
        return ListTile(
          dense: true,
          leading: Icon(
            isError
                ? Icons.error_outline
                : isResult
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
            size: 16,
            color: isError
                ? Colors.red
                : isResult
                    ? Colors.green
                    : Colors.grey,
          ),
          title: Text(
            log,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: isError ? Colors.red.shade700 : null,
            ),
          ),
        );
      },
    );
  }

  double min(double a, double b) => a < b ? a : b;
  double max(double a, double b) => a > b ? a : b;
}
