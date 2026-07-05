/// Minimal WAV file parser for dev-screen audio testing (Gate 1).
///
/// Parses standard PCM WAV files (RIFF/WAVE format) and extracts raw
/// audio samples as a normalised [Float32List] at the file's native
/// sample rate. The dev screen uses this to feed bundled test WAVs
/// chunk-by-chunk through the ASR pipeline.
///
/// Supports:
///   - 16-bit signed PCM (most common)
///   - Mono and stereo (stereo is downmixed to mono)
///   - Arbitrary sample rate (dev screen verifies 16 kHz)
///
/// Does NOT support:
///   - Compressed formats (MP3, ADPCM, etc.)
///   - 8-bit or 32-bit float WAV
///   - Extensible WAV format
///
/// This is a dev-only utility — not part of the production ASR pipeline.
library;

import 'dart:typed_data';

/// Parsed WAV file data.
class WavData {
  /// Sample rate in Hz (e.g. 16000).
  final int sampleRate;

  /// Number of audio channels (1 = mono, 2 = stereo).
  final int numChannels;

  /// Bits per sample (16 for PCM16).
  final int bitsPerSample;

  /// Normalised mono audio samples in [-1, 1].
  ///
  /// If the source file is stereo, channels are averaged to mono.
  final Float32List samples;

  WavData({
    required this.sampleRate,
    required this.numChannels,
    required this.bitsPerSample,
    required this.samples,
  });

  /// Duration of the audio in seconds.
  double get durationSeconds => samples.length / sampleRate;

  /// Duration of the audio as a [Duration] object.
  Duration get duration =>
      Duration(milliseconds: (durationSeconds * 1000).round());

  /// Total number of mono samples.
  int get numSamples => samples.length;
}

/// Parse a WAV file from raw bytes.
///
/// Throws [FormatException] if the bytes are not a valid PCM WAV file
/// or if the format is unsupported.
WavData parseWav(Uint8List bytes) {
  if (bytes.length < 44) {
    throw FormatException('File too short to be a valid WAV (got ${bytes.length} bytes)');
  }

  // Verify RIFF header
  final header = String.fromCharCodes(bytes.sublist(0, 4));
  if (header != 'RIFF') {
    throw FormatException('Not a RIFF file (got "$header")');
  }

  // Verify WAVE format
  final wave = String.fromCharCodes(bytes.sublist(8, 12));
  if (wave != 'WAVE') {
    throw FormatException('Not a WAVE file (got "$wave")');
  }

  final byteData = ByteData.sublistView(bytes);

  // Parse fmt chunk fields
  final audioFormat = byteData.getInt16(20, Endian.little);
  final numChannels = byteData.getInt16(22, Endian.little);
  final sampleRate = byteData.getInt32(24, Endian.little);
  final bitsPerSample = byteData.getInt16(34, Endian.little);

  if (audioFormat != 1) {
    throw FormatException(
      'Unsupported WAV format: audioFormat=$audioFormat (only PCM=1 is supported)',
    );
  }

  if (bitsPerSample != 16) {
    throw FormatException(
      'Unsupported bitsPerSample: $bitsPerSample (only 16-bit PCM is supported)',
    );
  }

  // Find the data chunk — it may not be immediately after the fmt chunk
  int offset = 12; // Skip past RIFF header (12 bytes)
  Uint8List? pcmData;
  int pcmDataLength = 0;

  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = byteData.getInt32(offset + 4, Endian.little);

    if (chunkId == 'data') {
      pcmData = bytes;
      pcmDataLength = chunkSize;
      offset += 8; // Move to data start
      break;
    }

    // Skip this chunk (8 bytes header + chunk data, padded to even)
    offset += 8 + chunkSize;
    if (chunkSize.isOdd) offset += 1; // Padding byte
  }

  if (pcmData == null) {
    throw FormatException('No data chunk found in WAV file');
  }

  // Extract samples from the data chunk
  final dataStart = offset;
  final bytesPerSample = bitsPerSample ~/ 8; // 2 for 16-bit
  final bytesPerFrame = bytesPerSample * numChannels;
  final numFrames = pcmDataLength ~/ bytesPerFrame;

  // Read PCM16 samples and convert to Float32
  final samples = Float32List(numFrames); // mono output

  for (int i = 0; i < numFrames; i++) {
    final frameOffset = dataStart + i * bytesPerFrame;

    if (numChannels == 1) {
      // Mono: single sample per frame
      final sample = byteData.getInt16(frameOffset, Endian.little);
      samples[i] = sample / 32768.0;
    } else {
      // Stereo (or multi-channel): average all channels
      double sum = 0.0;
      for (int ch = 0; ch < numChannels; ch++) {
        final sample = byteData.getInt16(
          frameOffset + ch * bytesPerSample,
          Endian.little,
        );
        sum += sample / 32768.0;
      }
      samples[i] = sum / numChannels;
    }
  }

  return WavData(
    sampleRate: sampleRate,
    numChannels: numChannels,
    bitsPerSample: bitsPerSample,
    samples: samples,
  );
}
